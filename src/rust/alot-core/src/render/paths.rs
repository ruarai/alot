//! Path batches: polylines, polygons and multi-ring paths drawn as ragg's
//! `drawPolyline()`, `drawPolygon()` and `drawPath()` draw them (ragg 1.5.2
//! src/AggDevice.h): the fill, then a separately blended stroke, each with
//! AGG's exact-area rasteriser (`agg`). Strokes use AGG's stroker with R's
//! line end, join and mitre limit; dashed line types go through AGG's dash
//! generator first, with R's `lty` digits scaled by the line width as
//! ragg's `makeDash()` does.
//!
//! Outlines are computed once per path. Each band rasterises only the
//! edges reaching its rows (`agg::rasterize_in`), so a long line is drawn
//! by all bands in parallel. A path reaching past the clip box is clipped
//! to it geometrically first, as ragg clips each mark.

use crate::render::agg::{self, Cap, Join, Rule};
use crate::render::raster::{self, Buckets, ClipShares};

/// One path in device pixels: `rings` are polylines (open, for a polyline)
/// or rings (closed, for a polygon or path), filled with `rule` in `fill`
/// and stroked in `col` (alpha 0 for none).
#[derive(Clone, Debug)]
pub struct PathSpec {
    pub rings: Vec<Vec<[f64; 2]>>,
    pub closed: bool,
    pub fill: [u8; 4],
    pub rule: Rule,
    pub col: [u8; 4],
    pub stroke: Stroke,
}

/// How a path is stroked: width in pixels, R's `lty` as packed hex digits
/// (0 for solid), end, join and mitre limit.
#[derive(Clone, Copy, Debug)]
pub struct Stroke {
    pub lwd: f64,
    pub lty: u32,
    pub cap: Cap,
    pub join: Join,
    pub mitre: f64,
}

/// Dash and gap lengths for R's `lty` at line width `lwd`, as ragg's
/// `makeDash()` builds them: up to four (dash, gap) pairs of hex digits,
/// lowest first, stopping at a zero digit.
pub fn dashes(lty: u32, lwd: f64) -> Vec<f64> {
    let mut out = Vec::new();
    let mut lty = lty;
    let mut i = 0;
    while i < 8 && lty & 15 != 0 {
        let dash = (lty & 15) as f64 * lwd;
        lty >>= 4;
        let gap = (lty & 15) as f64 * lwd;
        lty >>= 4;
        out.push(dash);
        out.push(gap);
        i += 2;
    }
    out
}

/// A path's outline contours: dashes stroked piece by piece, or the whole
/// path at once (`setStroke()`).
fn outline(rings: &[Vec<[f64; 2]>], closed: bool, s: &Stroke) -> Vec<Vec<[f64; 2]>> {
    let mut out = Vec::new();
    for r in rings {
        if s.lty == 0 {
            out.extend(agg::stroke(r, closed, s.lwd, s.join, s.cap, s.mitre));
        } else {
            for piece in agg::dash(r, closed, &dashes(s.lty, s.lwd)) {
                out.extend(agg::stroke(&piece, false, s.lwd, s.join, s.cap, s.mitre));
            }
        }
    }
    out
}

struct Prepared {
    fill: Option<(Vec<Vec<[f64; 2]>>, [u8; 4], Rule)>,
    stroke: Option<(Vec<Vec<[f64; 2]>>, [u8; 4])>,
    /// Bounding box of everything drawn: x0, y0, x1, y1.
    bbox: [f64; 4],
}

/// A display-list path batch (`display::Item::Paths`), drawn in data order.
pub struct PathBatch {
    paths: Vec<Prepared>,
    rows: (i64, i64),
}

fn bbox(contours: &[Vec<[f64; 2]>]) -> [f64; 4] {
    contours.iter().flatten().fold([f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY], |b, p| {
        [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
    })
}

fn prepare(p: &PathSpec) -> Prepared {
    let finite = |r: &Vec<[f64; 2]>| r.iter().all(|q| q[0].is_finite() && q[1].is_finite());
    let rings: Vec<Vec<[f64; 2]>> = p.rings.iter().filter(|r| r.len() >= 2 && finite(r)).cloned().collect();
    let fill = (p.closed && p.fill[3] > 0 && !rings.is_empty()).then(|| (rings.clone(), p.fill, p.rule));
    let stroked = p.col[3] > 0 && p.stroke.lwd > 0.0 && p.stroke.lwd.is_finite();
    let stroke = stroked.then(|| (outline(&rings, p.closed, &p.stroke), p.col)).filter(|(c, _)| !c.is_empty());
    let mut b = [f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY];
    for c in fill.iter().map(|f| &f.0).chain(stroke.iter().map(|s| &s.0)) {
        let o = bbox(c);
        b = [b[0].min(o[0]), b[1].min(o[1]), b[2].max(o[2]), b[3].max(o[3])];
    }
    Prepared { fill, stroke, bbox: b }
}

impl PathBatch {
    /// Prepares the paths' outlines in parallel. Rings with a non-finite
    /// vertex are dropped (callers split polylines at NA, as grid does).
    pub fn new(specs: &[PathSpec]) -> Self {
        let threads = raster::default_threads();
        let chunk = specs.len().div_ceil(threads).max(1);
        let paths: Vec<Prepared> = std::thread::scope(|scope| {
            let handles: Vec<_> = specs.chunks(chunk).map(|c| scope.spawn(move || c.iter().map(prepare).collect::<Vec<_>>())).collect();
            handles.into_iter().flat_map(|h| h.join().unwrap()).collect()
        });
        let rows = paths.iter().filter_map(Self::span).fold((i64::MAX, i64::MIN), |(lo, hi), (a, b)| (lo.min(a), hi.max(b)));
        let rows = if rows.0 > rows.1 { (0, 0) } else { rows };
        PathBatch { paths, rows }
    }

    fn span(p: &Prepared) -> Option<(i64, i64)> {
        (p.bbox[1] <= p.bbox[3]).then(|| (p.bbox[1].floor() as i64, p.bbox[3].floor() as i64 + 1))
    }

    /// Pixel rows `[top, bottom)` the batch can touch.
    pub fn rows(&self) -> (i64, i64) {
        self.rows
    }

    pub fn bucket(&self, band_rows: usize, n_bands: usize) -> Buckets {
        Buckets::new(self.paths.len(), band_rows, n_bands, |i| Self::span(&self.paths[i]))
    }

    /// Blends paths `idx` into a band's premultiplied rows (`buf`, starting
    /// at page row `top`), clipped to the current clip.
    pub fn draw(&self, buf: &mut [[f32; 4]], top: usize, width: usize, idx: &[u32], clip: &ClipShares) {
        let h = buf.len() / width;
        let c = clip.rect;
        for &i in idx {
            let p = &self.paths[i as usize];
            let inside = p.bbox[0] >= c.x0 && p.bbox[1] >= c.y0 && p.bbox[2] <= c.x1 && p.bbox[3] <= c.y1;
            let layer = |contours: &Vec<Vec<[f64; 2]>>, rule: Rule| {
                let clipped;
                let contours = if inside {
                    contours
                } else {
                    clipped = agg::clip_contours(contours, c.x0, c.y0, c.x1, c.y1);
                    &clipped
                };
                agg::rasterize_in(contours, rule, 0, top as i32, width as i32, (top + h) as i32)
            };
            if let Some((contours, colour, rule)) = &p.fill {
                blend(buf, width, &layer(contours, *rule), *colour);
            }
            if let Some((contours, colour)) = &p.stroke {
                blend(buf, width, &layer(contours, Rule::NonZero), *colour);
            }
        }
    }
}

/// Blends band-shaped coverage (`c` covers the band's rows and columns).
fn blend(buf: &mut [[f32; 4]], width: usize, c: &agg::Coverage, colour: [u8; 4]) {
    let a = colour[3] as f32 / 255.0;
    let col = [colour[0] as f32 / 255.0 * a, colour[1] as f32 / 255.0 * a, colour[2] as f32 / 255.0 * a, a];
    if c.w != width {
        return;
    }
    for (d, &k) in buf.iter_mut().zip(&c.alpha) {
        if k == 0 {
            continue;
        }
        let k = k as f32 / 255.0;
        let inv = 1.0 - a * k;
        for ch in 0..4 {
            d[ch] = col[ch] * k + d[ch] * inv;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::display::{DisplayList, Item, Rect};
    use crate::render::raster::{render, Options};

    fn solid(lwd: f64) -> Stroke {
        Stroke { lwd, lty: 0, cap: Cap::Butt, join: Join::Round, mitre: 10.0 }
    }

    fn line(points: Vec<[f64; 2]>, stroke: Stroke) -> PathSpec {
        PathSpec { rings: vec![points], closed: false, fill: [0; 4], rule: Rule::NonZero, col: [0, 0, 0, 255], stroke }
    }

    fn draw(specs: Vec<PathSpec>, w: usize, h: usize, band_rows: usize) -> Vec<u32> {
        let mut list = DisplayList::new();
        list.push(Item::Paths(PathBatch::new(&specs)));
        render(&list, w, h, &Options { threads: 3, band_rows })
    }

    #[test]
    fn r_line_types_become_ragg_dashes() {
        // "dashed" is 0x44, "dotdash" 0x3431 (R's lty digits, lowest first).
        assert_eq!(dashes(0x44, 2.0), vec![8.0, 8.0]);
        assert_eq!(dashes(0x3431, 1.0), vec![1.0, 3.0, 4.0, 3.0]);
        assert!(dashes(0, 1.0).is_empty());
    }

    #[test]
    fn bands_do_not_change_a_long_line() {
        let pts: Vec<[f64; 2]> = (0..400).map(|i| [i as f64 * 0.5 + 0.3, 20.0 + 15.0 * (i as f64 * 0.11).sin()]).collect();
        let specs = vec![line(pts.clone(), solid(1.7)), line(pts, Stroke { lty: 0x44, ..solid(1.1) })];
        let one = draw(specs.clone(), 210, 40, 1000);
        assert_eq!(draw(specs, 210, 40, 3), one);
        assert!(one.iter().any(|&p| p >> 24 == 255));
    }

    #[test]
    fn a_horizontal_line_covers_its_width() {
        // 2 px wide at y = 10, butt ends at x = 5 and 15.
        let img = draw(vec![line(vec![[5.0, 10.0], [15.0, 10.0]], solid(2.0))], 20, 20, 4);
        let a = |x: usize, y: usize| img[y * 20 + x] >> 24;
        assert_eq!((a(10, 8), a(10, 9), a(10, 10), a(10, 11)), (0, 255, 255, 0));
        assert_eq!((a(4, 9), a(5, 9), a(14, 9), a(15, 9)), (0, 255, 255, 0));
    }

    #[test]
    fn dashed_lines_have_gaps() {
        let img = draw(vec![line(vec![[0.0, 10.0], [40.0, 10.0]], Stroke { lty: 0x44, ..solid(1.0) })], 40, 20, 8);
        let row: Vec<u32> = (0..40).map(|x| img[10 * 40 + x] >> 24).collect();
        assert!(row[1] > 0 && row[5] == 0 && row[9] > 0 && row[13] == 0, "{row:?}");
    }

    #[test]
    fn polygons_fill_then_stroke_and_follow_the_rule() {
        let square = |x: f64| vec![[x, 2.0], [x + 10.0, 2.0], [x + 10.0, 12.0], [x, 12.0]];
        let mut p = PathSpec { rings: vec![square(2.0), square(6.0)], closed: true, fill: [0, 0, 255, 255], rule: Rule::EvenOdd, col: [0; 4], stroke: solid(0.0) };
        let img = draw(vec![p.clone()], 20, 14, 5);
        assert_eq!(img[7 * 20 + 9] >> 24, 0, "even-odd overlap is a hole");
        assert_eq!(img[7 * 20 + 3] >> 24, 255);
        p.rule = Rule::NonZero;
        p.col = [255, 0, 0, 255];
        p.stroke = solid(2.0);
        let img = draw(vec![p], 20, 14, 5);
        assert_eq!(img[7 * 20 + 9], 0xFF_FF_00_00, "non-zero overlap is filled");
        assert_eq!(img[2 * 20 + 4] & 0xFF, 255, "outline on top");
    }

    #[test]
    fn paths_clip_geometrically() {
        let mut list = DisplayList::new();
        list.push(Item::PushClip(Rect { x0: 0.0, y0: 0.0, x1: 10.5, y1: 20.0 }));
        list.push(Item::Paths(PathBatch::new(&[line(vec![[2.0, 5.0], [18.0, 5.0]], solid(2.0))])));
        let img = render(&list, 20, 10, &Options { threads: 1, band_rows: 4 });
        let a = |x: usize| img[4 * 20 + x] >> 24;
        assert_eq!((a(9), a(10), a(11)), (255, 128, 0));
    }

    #[test]
    fn non_finite_rings_are_dropped() {
        let img = draw(vec![line(vec![[1.0, 1.0], [f64::NAN, 5.0]], solid(1.0))], 8, 8, 4);
        assert!(img.iter().all(|&p| p == 0));
    }
}
