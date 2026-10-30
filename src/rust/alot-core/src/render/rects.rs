//! Rect batches: axis-aligned rects drawn as ragg's `drawRect()` draws them
//! (ragg 1.5.2 src/AggDevice.h): the fill, then a separately blended
//! stroke. A fill-only rect has its corners rounded to whole pixels when
//! `snap_rect` is on (ragg's default); a stroked one is drawn at its exact
//! position, its outline from AGG's stroker (`agg::stroke`) with the given
//! join and mitre limit. This is the drawer for bars, tiles, panel
//! backgrounds and legend keys.
//!
//! Fills are computed analytically: AGG's coverage of an axis-aligned rect
//! in a pixel is the product of the pixel's overlaps in 24.8 fixed point,
//! `(ox * oy) >> 8` capped at 255, which is what its cell rasteriser gives
//! (`tests::analytic_fill_matches_the_rasteriser`). Clipping a rect leaves
//! a rect, so fills are clipped geometrically, as ragg clips each mark.

use crate::render::agg::{self, Cap, Join};
use crate::render::display::Rect;
use crate::render::raster::{self, Buckets, ClipShares};

/// One rect in device pixels (any corner order), its fill and stroke
/// colours as non-premultiplied RGBA (alpha 0 for none) and its stroke
/// width in pixels.
#[derive(Clone, Copy, Debug)]
pub struct RectSpec {
    pub x0: f64,
    pub y0: f64,
    pub x1: f64,
    pub y1: f64,
    pub fill: [u8; 4],
    pub col: [u8; 4],
    pub lwd: f64,
}

/// Stroke settings shared by a batch (a layer's `linejoin`, grid's
/// `linemitre`) and whether fill-only rects snap.
#[derive(Clone, Copy, Debug)]
pub struct RectStyle {
    pub join: Join,
    pub mitre: f64,
    pub snap: bool,
}

/// A display-list rect batch (`display::Item::Rects`), drawn in data order.
pub struct RectBatch {
    rects: Vec<RectSpec>,
    style: RectStyle,
    rows: (i64, i64),
}

fn stroked(r: &RectSpec) -> bool {
    r.col[3] > 0 && r.lwd > 0.0
}

/// The rect ragg fills, normalised, and its stroke outline contours.
fn geometry(r: &RectSpec, style: &RectStyle) -> (Rect, bool) {
    let s = stroked(r);
    let (mut x0, mut y0, mut x1, mut y1) = (r.x0, r.y0, r.x1, r.y1);
    if style.snap && !s {
        x0 = x0.round();
        y0 = y0.round();
        x1 = x1.round();
        y1 = y1.round();
    }
    (Rect { x0: x0.min(x1), y0: y0.min(y1), x1: x0.max(x1), y1: y0.max(y1) }, s)
}

fn iround(v: f64) -> i64 {
    (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i64
}

impl RectBatch {
    /// Rects with a non-finite corner draw nothing (grid skips NA rects).
    pub fn new(rects: Vec<RectSpec>, style: RectStyle) -> Self {
        let fold = |rs: &[RectSpec]| {
            rs.iter().filter_map(Self::span).fold((i64::MAX, i64::MIN), |(lo, hi), (top, bottom)| (lo.min(top), hi.max(bottom)))
        };
        let chunk = rects.len().div_ceil(raster::default_threads()).max(1 << 16);
        let parts: Vec<(i64, i64)> = std::thread::scope(|scope| {
            let handles: Vec<_> = rects.chunks(chunk).map(|c| scope.spawn(move || fold(c))).collect();
            handles.into_iter().map(|h| h.join().unwrap()).collect()
        });
        let mut rows = parts.into_iter().fold((i64::MAX, i64::MIN), |(lo, hi), (a, b)| (lo.min(a), hi.max(b)));
        if rows.0 > rows.1 {
            rows = (0, 0);
        }
        RectBatch { rects, style, rows }
    }

    /// Rows `[top, bottom)` a rect can touch, with room for its stroke.
    fn span(r: &RectSpec) -> Option<(i64, i64)> {
        let finite = [r.x0, r.y0, r.x1, r.y1, r.lwd].iter().all(|v| v.is_finite());
        if !finite || (r.fill[3] == 0 && !stroked(r)) {
            return None;
        }
        let pad = if stroked(r) { r.lwd + 2.0 } else { 1.0 };
        let (lo, hi) = (r.y0.min(r.y1), r.y0.max(r.y1));
        Some(((lo - pad).floor() as i64, (hi + pad).ceil() as i64 + 1))
    }

    /// Pixel rows `[top, bottom)` the batch can touch.
    pub fn rows(&self) -> (i64, i64) {
        self.rows
    }

    pub fn bucket(&self, band_rows: usize, n_bands: usize) -> Buckets {
        Buckets::new(self.rects.len(), band_rows, n_bands, |i| Self::span(&self.rects[i]))
    }

    /// Blends rects `idx` into a band's premultiplied rows (`buf`, starting
    /// at page row `top`), clipped to the current clip.
    pub fn draw(&self, buf: &mut [[f32; 4]], top: usize, width: usize, idx: &[u32], clip: &ClipShares) {
        let h = buf.len() / width;
        // The clip, limited to the band: cutting at whole rows leaves each
        // pixel's coverage unchanged.
        let band = clip.rect.intersect(&Rect { x0: 0.0, y0: top as f64, x1: width as f64, y1: (top + h) as f64 });
        if band.x0 >= band.x1 || band.y0 >= band.y1 {
            return;
        }
        for &i in idx {
            let r = &self.rects[i as usize];
            let (fill_rect, s) = geometry(r, &self.style);
            if r.fill[3] > 0 {
                fill(buf, top, width, &fill_rect.intersect(&band), premul(r.fill));
            }
            if s {
                let path = [[r.x0, r.y0], [r.x0, r.y1], [r.x1, r.y1], [r.x1, r.y0]];
                let contours = agg::stroke(&path, true, r.lwd, self.style.join, Cap::Butt, self.style.mitre);
                let clipped = agg::clip_contours(&contours, band.x0, band.y0, band.x1, band.y1);
                let c = agg::rasterize(&clipped);
                blend(buf, top, width, &c, premul(r.col));
            }
        }
    }
}

fn premul(c: [u8; 4]) -> [f32; 4] {
    let a = c[3] as f32 / 255.0;
    [c[0] as f32 / 255.0 * a, c[1] as f32 / 255.0 * a, c[2] as f32 / 255.0 * a, a]
}

/// AGG's alpha for each pixel of a rect: overlaps in 24.8 fixed point.
fn fill(buf: &mut [[f32; 4]], top: usize, width: usize, r: &Rect, colour: [f32; 4]) {
    if r.x0 >= r.x1 || r.y0 >= r.y1 {
        return;
    }
    let (fx0, fx1, fy0, fy1) = (iround(r.x0 * 256.0), iround(r.x1 * 256.0), iround(r.y0 * 256.0), iround(r.y1 * 256.0));
    let overlap = |i: i64, lo: i64, hi: i64| (hi.min((i + 1) * 256) - lo.max(i * 256)).clamp(0, 256);
    let (i0, i1) = (fx0 >> 8, (fx1 + 255) >> 8);
    let (j0, j1) = (fy0 >> 8, (fy1 + 255) >> 8);
    let a = colour[3];
    // Whole-pixel edges (snapped rects away from a fractional clip edge):
    // every pixel is fully covered.
    if (fx0 | fx1 | fy0 | fy1) & 255 == 0 {
        for j in j0..j1 {
            let row = &mut buf[(j - top as i64) as usize * width..][i0 as usize..i1 as usize];
            if a == 1.0 {
                row.fill(colour);
            } else {
                for d in row {
                    for c in 0..4 {
                        d[c] = colour[c] + d[c] * (1.0 - a);
                    }
                }
            }
        }
        return;
    }
    for j in j0..j1 {
        let oy = overlap(j, fy0, fy1);
        let row = (j - top as i64) as usize;
        let crow = &mut buf[row * width..][..width];
        for i in i0..i1 {
            let alpha = ((overlap(i, fx0, fx1) * oy) >> 8).min(255);
            if alpha == 0 {
                continue;
            }
            let k = alpha as f32 / 255.0;
            let d = &mut crow[i as usize];
            if k == 1.0 && a == 1.0 {
                *d = colour;
                continue;
            }
            let inv = 1.0 - a * k;
            for c in 0..4 {
                d[c] = colour[c] * k + d[c] * inv;
            }
        }
    }
}

/// Blends page-pixel coverage `c` into a band's rows (`c` lies within it).
fn blend(buf: &mut [[f32; 4]], top: usize, width: usize, c: &agg::Coverage, colour: [f32; 4]) {
    let a = colour[3];
    for j in 0..c.h {
        let y = c.y0 as i64 + j as i64 - top as i64;
        if y < 0 || y as usize >= buf.len() / width {
            continue;
        }
        for i in 0..c.w {
            let x = c.x0 as i64 + i as i64;
            let alpha = c.alpha[j * c.w + i];
            if alpha == 0 || x < 0 || x as usize >= width {
                continue;
            }
            let k = alpha as f32 / 255.0;
            let d = &mut buf[y as usize * width + x as usize];
            let inv = 1.0 - a * k;
            for ch in 0..4 {
                d[ch] = colour[ch] * k + d[ch] * inv;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::display::{DisplayList, Item};
    use crate::render::raster::{render, Options};

    fn spec(x0: f64, y0: f64, x1: f64, y1: f64) -> RectSpec {
        RectSpec { x0, y0, x1, y1, fill: [0, 0, 0, 255], col: [0; 4], lwd: 0.0 }
    }

    fn draw(rects: Vec<RectSpec>, style: RectStyle, w: usize, h: usize) -> Vec<u32> {
        let mut list = DisplayList::new();
        list.push(Item::Rects(RectBatch::new(rects, style)));
        render(&list, w, h, &Options { threads: 2, band_rows: 7 })
    }

    const SNAP: RectStyle = RectStyle { join: Join::Miter, mitre: 10.0, snap: true };
    const EXACT: RectStyle = RectStyle { join: Join::Miter, mitre: 10.0, snap: false };

    #[test]
    fn analytic_fill_matches_the_rasteriser() {
        let mut seed = 3u64;
        let mut rnd = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 11) as f64 / (1u64 << 53) as f64
        };
        for _ in 0..200 {
            let (x0, y0) = (rnd() * 10.0, rnd() * 10.0);
            let (x1, y1) = (x0 + rnd() * 6.0, y0 + rnd() * 6.0);
            let img = draw(vec![spec(x0, y0, x1, y1)], EXACT, 20, 20);
            let c = agg::rasterize(&[vec![[x0, y0], [x0, y1], [x1, y1], [x1, y0]]]);
            for y in 0..20i32 {
                for x in 0..20i32 {
                    let (i, j) = (x - c.x0, y - c.y0);
                    let want = if i >= 0 && j >= 0 && (i as usize) < c.w && (j as usize) < c.h { c.alpha[j as usize * c.w + i as usize] } else { 0 };
                    assert_eq!(img[(y * 20 + x) as usize] >> 24, want as u32, "{x0} {y0} {x1} {y1} at {x},{y}");
                }
            }
        }
    }

    #[test]
    fn fill_only_rects_snap_to_whole_pixels() {
        let img = draw(vec![spec(2.4, 1.6, 5.5, 3.4)], SNAP, 8, 6);
        let a = |x: usize, y: usize| img[y * 8 + x] >> 24;
        // round(): x 2..6, y 2..3.
        assert_eq!((a(1, 2), a(2, 2), a(5, 2), a(6, 2)), (0, 255, 255, 0));
        assert_eq!((a(3, 1), a(3, 2), a(3, 3)), (0, 255, 0));
        // Unsnapped, the edges are partial.
        let img = draw(vec![spec(2.4, 1.6, 5.5, 3.4)], EXACT, 8, 6);
        assert!(img[2 * 8 + 2] >> 24 > 0 && img[2 * 8 + 2] >> 24 < 255);
    }

    #[test]
    fn stroked_rects_are_not_snapped_and_draw_the_outline() {
        let mut r = spec(2.4, 2.4, 12.6, 12.6);
        r.col = [255, 0, 0, 255];
        r.fill = [0, 0, 255, 255];
        r.lwd = 2.0;
        let img = draw(vec![r], SNAP, 16, 16);
        assert_eq!(img[7 * 16 + 7], 0xFF_FF_00_00, "fill inside");
        assert_eq!(img[7 * 16 + 2] & 0xFF, 255, "outline red at the left edge");
        // Mitre join: the corner is square, so pixel (1, 1) is touched.
        assert!(img[16 + 1] >> 24 > 0);
    }

    #[test]
    fn rects_clip_geometrically() {
        let mut list = DisplayList::new();
        list.push(Item::PushClip(Rect { x0: 3.25, y0: 0.0, x1: 20.0, y1: 4.5 }));
        list.push(Item::Rects(RectBatch::new(vec![spec(1.0, 1.0, 9.0, 9.0)], SNAP)));
        let img = render(&list, 12, 12, &Options { threads: 1, band_rows: 3 });
        let a = |x: usize, y: usize| img[y * 12 + x] >> 24;
        assert_eq!((a(2, 2), a(3, 2), a(4, 2)), (0, 192, 255));
        assert_eq!((a(5, 4), a(5, 5)), (128, 0));
    }

    #[test]
    fn non_finite_and_invisible_rects_draw_nothing() {
        let mut none = spec(1.0, 1.0, 3.0, 3.0);
        none.fill = [0; 4];
        let img = draw(vec![spec(f64::NAN, 1.0, 3.0, 3.0), none], SNAP, 5, 5);
        assert!(img.iter().all(|&p| p == 0));
    }
}
