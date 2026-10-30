//! Point batches rasterised with prebuilt coverage sprites.
//!
//! Symbol geometry mirrors R's `GESymbol()` (src/main/engine.c) as drawn by
//! ragg: `size` is the symbol size in pixels (grid's fontsize * cex, scaled
//! by res / 72) and `lwd` the line width in pixels (lwd * res / 96). Filled
//! shapes 15-17 are fill only; lines have round caps and joins (grid's
//! default gpar); 19 and 20 are a fill and then an outline. Circles are
//! the polygons ragg draws (`agg_circle()`), not true discs. Each `Part` of a symbol is composited on its own, so where
//! the two lines of a `+` cross, the colour is blended twice, as in ragg.
//!
//! A sprite holds the coverage of each part for one (shape, size, lwd) at
//! one of SUB x SUB subpixel offsets, so drawing a point is a masked blend
//! with no geometry. A `PointBatch` is a display-list item; the band
//! executor (`raster`) draws it, each band visiting its points in data
//! order, so overlaps composite as they do on a device.

use crate::render::display::{DisplayList, Item};
use crate::render::raster::{self, ClipShares};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

const RADIUS: f64 = 0.375;
const SMALL: f64 = 0.25;
const TRC0: f64 = 1.55512030155621416073;
const TRC1: f64 = 1.34677368708859836060;
const TRC2: f64 = 0.77756015077810708036;

/// Subpixel positions per axis.
const SUB: usize = 16;
/// Coverage samples per pixel axis when building sprites.
const SAMPLES: usize = 16;

/// Shapes this module draws; anything else should fall back.
pub fn supported_shape(shape: i32) -> bool {
    matches!(shape, 0..=4 | 15..=17 | 19 | 20)
}

/// A point in canvas pixels (origin top-left, pixel i covers [i, i + 1]),
/// with its colour as non-premultiplied RGBA bytes.
#[derive(Clone, Copy, Debug)]
pub struct Point {
    pub x: f64,
    pub y: f64,
    pub shape: i32,
    pub size: f64,
    pub lwd: f64,
    pub rgba: [u8; 4],
}

enum Part {
    Polygon(Vec<[f64; 2]>),
    /// Segments stroked with round caps and joins, half-width `.1`.
    Stroke(Vec<[[f64; 2]; 2]>, f64),
}

impl Part {
    fn extent(&self) -> f64 {
        match self {
            Part::Polygon(v) => v.iter().map(|p| p[0].abs().max(p[1].abs())).fold(0.0, f64::max),
            Part::Stroke(s, h) => s.iter().flatten().map(|p| p[0].abs().max(p[1].abs())).fold(0.0, f64::max) + h,
        }
    }

    /// A bound on the signed distance from (x, y) to the part's edge,
    /// negative inside: the point is at least this far out (or, if
    /// negative, in). Exact for strokes; for polygons, the largest signed
    /// edge-line distance never exceeds the true distance.
    fn distance(&self, x: f64, y: f64) -> f64 {
        match self {
            Part::Polygon(v) => {
                let edges = || (0..v.len()).map(|i| (v[i], v[(i + 1) % v.len()]));
                // Cross products are negative outside edges of a polygon with
                // positive signed area, positive outside the other way round.
                let area: f64 = edges().map(|([ax, ay], [bx, by])| ax * by - bx * ay).sum();
                let out = if area > 0.0 { -1.0 } else { 1.0 };
                edges()
                    .map(|([ax, ay], [bx, by])| {
                        let len = (bx - ax).hypot(by - ay);
                        out * ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) / len
                    })
                    .fold(f64::NEG_INFINITY, f64::max)
            }
            Part::Stroke(s, h) => s.iter().map(|&[a, b]| seg_dist2(x, y, a, b)).fold(f64::INFINITY, f64::min).sqrt() - h,
        }
    }

    fn contains(&self, x: f64, y: f64) -> bool {
        match self {
            Part::Polygon(v) => {
                // Convex, so inside means the same side of every edge.
                let mut sign = 0.0;
                for i in 0..v.len() {
                    let [ax, ay] = v[i];
                    let [bx, by] = v[(i + 1) % v.len()];
                    let c = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
                    if c != 0.0 {
                        if sign != 0.0 && c.signum() != sign {
                            return false;
                        }
                        sign = c.signum();
                    }
                }
                true
            }
            Part::Stroke(s, h) => s.iter().any(|&[a, b]| seg_dist2(x, y, a, b) <= h * h),
        }
    }
}

fn seg_dist2(x: f64, y: f64, [ax, ay]: [f64; 2], [bx, by]: [f64; 2]) -> f64 {
    let (dx, dy) = (bx - ax, by - ay);
    let len2 = dx * dx + dy * dy;
    let t = if len2 > 0.0 { (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0) } else { 0.0 };
    let (ex, ey) = (ax + t * dx - x, ay + t * dy - y);
    ex * ex + ey * ey
}

/// The polygon ragg draws for a circle of radius `r`: `drawCircle()`
/// (ragg 1.5.2 src/AggDevice.h) fixes the step count of `agg::ellipse`
/// below a radius of 20 px and clamps tiny radii to 0.5; above that, AGG
/// picks it (`ellipse::calc_num_steps`, agg_ellipse.h). Vertices start at
/// angle 0 and run counter-clockwise in device space.
fn agg_circle(r: f64) -> Vec<[f64; 2]> {
    let (r, n) = match r {
        r if r < 1.0 => (r.max(0.5), 4),
        r if r < 2.5 => (r, 8),
        r if r < 5.0 => (r, 16),
        r if r < 10.0 => (r, 32),
        r if r < 20.0 => (r, 64),
        r => {
            let da = (r / (r + 0.125)).acos() * 2.0;
            (r, (2.0 * std::f64::consts::PI / da).round() as usize)
        }
    };
    (0..n)
        .map(|k| {
            let a = k as f64 / n as f64 * 2.0 * std::f64::consts::PI;
            [r * a.cos(), r * a.sin()]
        })
        .collect()
}

/// Parts of `shape` centred on the origin, device y pointing down.
fn parts(shape: i32, size: f64, lwd: f64) -> Vec<Part> {
    let r = RADIUS * size;
    let h = lwd / 2.0;
    let closed = |v: Vec<[f64; 2]>| (0..v.len()).map(|i| [v[i], v[(i + 1) % v.len()]]).collect::<Vec<_>>();
    let square = vec![[-r, -r], [r, -r], [r, r], [-r, r]];
    let triangle = vec![[0.0, -TRC0 * r], [TRC1 * r, TRC2 * r], [-TRC1 * r, TRC2 * r]];
    match shape {
        0 => vec![Part::Stroke(closed(square), h)],
        1 => vec![Part::Stroke(closed(agg_circle(r)), h)],
        2 => vec![Part::Stroke(closed(triangle), h)],
        3 => {
            let xc = std::f64::consts::SQRT_2 * r;
            vec![
                Part::Stroke(vec![[[-xc, 0.0], [xc, 0.0]]], h),
                Part::Stroke(vec![[[0.0, -xc], [0.0, xc]]], h),
            ]
        }
        4 => vec![
            Part::Stroke(vec![[[-r, -r], [r, r]]], h),
            Part::Stroke(vec![[[-r, r], [r, -r]]], h),
        ],
        15 => vec![Part::Polygon(square)],
        16 => vec![Part::Polygon(agg_circle(r))],
        17 => vec![Part::Polygon(triangle)],
        19 => vec![Part::Polygon(agg_circle(r)), Part::Stroke(closed(agg_circle(r)), h)],
        20 => {
            let c = agg_circle(SMALL * size);
            vec![Part::Polygon(c.clone()), Part::Stroke(closed(c), h)]
        }
        _ => Vec::new(),
    }
}

/// Coverage of one part, over pixels [x0, x0 + w) x [y0, y0 + h) relative
/// to the pixel holding the point.
struct Mask {
    x0: i32,
    y0: i32,
    w: usize,
    h: usize,
    cov: Vec<f32>,
}

fn build_mask(part: &Part, fx: f64, fy: f64) -> Mask {
    let ext = part.extent();
    let x0 = (fx - ext).floor() as i32;
    let y0 = (fy - ext).floor() as i32;
    let w = ((fx + ext).ceil() as i32 - x0).max(0) as usize;
    let h = ((fy + ext).ceil() as i32 - y0).max(0) as usize;
    let mut cov = vec![0.0f32; w * h];
    let step = 1.0 / SAMPLES as f64;
    // Pixels whose centre is more than half a diagonal from the edge are
    // fully in or out; only the rest are sampled.
    let half_diag = std::f64::consts::FRAC_1_SQRT_2 + 1e-9;
    for j in 0..h {
        for i in 0..w {
            let cx = (x0 + i as i32) as f64 + 0.5 - fx;
            let cy = (y0 + j as i32) as f64 + 0.5 - fy;
            let dist = part.distance(cx, cy);
            if dist > half_diag {
                continue;
            }
            if dist < -half_diag {
                cov[j * w + i] = 1.0;
                continue;
            }
            let mut n = 0u32;
            for sj in 0..SAMPLES {
                let y = (y0 + j as i32) as f64 + (sj as f64 + 0.5) * step - fy;
                for si in 0..SAMPLES {
                    let x = (x0 + i as i32) as f64 + (si as f64 + 0.5) * step - fx;
                    n += part.contains(x, y) as u32;
                }
            }
            cov[j * w + i] = n as f32 / (SAMPLES * SAMPLES) as f32;
        }
    }
    // Trim empty rows and columns so blending skips them.
    let row_used = |j: usize| cov[j * w..(j + 1) * w].iter().any(|&c| c > 0.0);
    let col_used = |i: usize| (0..h).any(|j| cov[j * w + i] > 0.0);
    let (Some(j0), Some(j1)) = ((0..h).find(|&j| row_used(j)), (0..h).rev().find(|&j| row_used(j))) else {
        return Mask { x0, y0, w: 0, h: 0, cov: Vec::new() };
    };
    let i0 = (0..w).find(|&i| col_used(i)).unwrap();
    let i1 = (0..w).rev().find(|&i| col_used(i)).unwrap();
    let (tw, th) = (i1 - i0 + 1, j1 - j0 + 1);
    let mut trimmed = Vec::with_capacity(tw * th);
    for j in j0..=j1 {
        trimmed.extend_from_slice(&cov[j * w + i0..j * w + i1 + 1]);
    }
    Mask { x0: x0 + i0 as i32, y0: y0 + j0 as i32, w: tw, h: th, cov: trimmed }
}

/// One sprite per subpixel offset (`SUB * SUB`), each a mask per part.
type SpriteSet = Vec<Vec<Mask>>;

type Key = (i32, u64, u64);

/// Sprite sets built so far in this process, shared across panels and
/// draws. Cleared when it grows past `CACHE_MAX` sets (plots mapping size
/// to many distinct values).
static CACHE: Mutex<Option<HashMap<Key, Arc<SpriteSet>>>> = Mutex::new(None);
const CACHE_MAX: usize = 1024;

fn build_set(shape: i32, size: f64, lwd: f64) -> SpriteSet {
    let parts = parts(shape, size, lwd);
    let build = |k: usize| -> Vec<Mask> {
        let fx = ((k % SUB) as f64 + 0.5) / SUB as f64;
        let fy = ((k / SUB) as f64 + 0.5) / SUB as f64;
        parts.iter().map(|p| build_mask(p, fx, fy)).collect()
    };
    let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).min(SUB);
    let mut set: Vec<Vec<Mask>> = (0..SUB * SUB).map(|_| Vec::new()).collect();
    std::thread::scope(|scope| {
        for (c, chunk) in set.chunks_mut(SUB * SUB / threads).enumerate() {
            let build = &build;
            scope.spawn(move || {
                for (i, slot) in chunk.iter_mut().enumerate() {
                    *slot = build(c * (SUB * SUB / threads) + i);
                }
            });
        }
    });
    set
}

/// The sprite sets used by one batch, looked up by (shape, size, lwd).
/// Size and lwd are usually constant, so sets for the first (size, lwd)
/// seen are also indexed by shape, avoiding the hash map.
struct Sprites {
    sets: Vec<Arc<SpriteSet>>,
    index: HashMap<Key, usize>,
    common: Option<(u64, u64)>,
    by_shape: [u16; 32],
}

const UNSET: u16 = u16::MAX;

impl Sprites {
    fn new() -> Self {
        Sprites { sets: Vec::new(), index: HashMap::new(), common: None, by_shape: [UNSET; 32] }
    }

    fn get(&mut self, shape: i32, size: f64, lwd: f64) -> usize {
        let key = (shape, size.to_bits(), lwd.to_bits());
        let common = *self.common.get_or_insert((key.1, key.2)) == (key.1, key.2) && (0..32).contains(&shape);
        if common && self.by_shape[shape as usize] != UNSET {
            return self.by_shape[shape as usize] as usize;
        }
        if let Some(&i) = self.index.get(&key) {
            return i;
        }
        let set = {
            let mut cache = CACHE.lock().unwrap();
            let cache = cache.get_or_insert_with(HashMap::new);
            if cache.len() >= CACHE_MAX {
                cache.clear();
            }
            cache.entry(key).or_insert_with(|| Arc::new(build_set(shape, size, lwd))).clone()
        };
        self.sets.push(set);
        let i = self.sets.len() - 1;
        if common && i < UNSET as usize {
            self.by_shape[shape as usize] = i as u16;
        }
        self.index.insert(key, i);
        self.sets.len() - 1
    }
}

/// A point snapped to its pixel and subpixel sprite.
#[derive(Clone, Copy)]
struct Placed {
    ix: i32,
    iy: i32,
    set: u16,
    sub: u16,
    rgba: [u8; 4],
}

fn place(p: &Point, sprites: &mut Sprites) -> Option<Placed> {
    if !(p.x.is_finite() && p.y.is_finite()) || p.rgba[3] == 0 || !supported_shape(p.shape) {
        return None;
    }
    // Pixel and subpixel in one step (`floor()` is a libm call on the
    // baseline x86-64 target). Positions beyond i32 are off any canvas.
    let split = |v: f64| {
        let t = (v * SUB as f64).clamp(-1e9, 1e9);
        let k = t as i64 - (t < (t as i64) as f64) as i64;
        ((k.div_euclid(SUB as i64)) as i32, k.rem_euclid(SUB as i64) as usize)
    };
    let (ix, sx) = split(p.x);
    let (iy, sy) = split(p.y);
    let set = sprites.get(p.shape, p.size, p.lwd);
    Some(Placed { ix, iy, set: u16::try_from(set).ok()?, sub: (sy * SUB + sx) as u16, rgba: p.rgba })
}

/// Placement buffers kept between batches: fresh multi-megabyte
/// allocations cost more in page faults than placing the points.
static PLACED_POOL: Mutex<Vec<Vec<Placed>>> = Mutex::new(Vec::new());

/// A display-list point batch (`display::Item::Points`): points snapped to
/// their sprites, drawn in data order.
pub struct PointBatch {
    placed: Vec<Placed>,
    sets: Vec<Arc<SpriteSet>>,
    /// Rows any mask reaches relative to its point, so bands can skip
    /// points without touching their sprites.
    reach: (i32, i32),
    rows: (i64, i64),
}

impl Drop for PointBatch {
    fn drop(&mut self) {
        let mut placed = std::mem::take(&mut self.placed);
        placed.clear();
        PLACED_POOL.lock().unwrap_or_else(|e| e.into_inner()).push(placed);
    }
}

/// For each band, the indices of the points that reach it, in data order.
pub struct Buckets {
    starts: Vec<usize>,
    index: Vec<u32>,
}

impl Buckets {
    pub fn band(&self, b: usize) -> &[u32] {
        &self.index[self.starts[b]..self.starts[b + 1]]
    }
}

impl PointBatch {
    /// Points with unsupported shapes, zero alpha or non-finite positions
    /// are dropped; callers check `supported_shape()` first.
    pub fn new(points: impl IntoIterator<Item = Point>) -> Self {
        let mut sprites = Sprites::new();
        let mut placed = PLACED_POOL.lock().unwrap_or_else(|e| e.into_inner()).pop().unwrap_or_default();
        placed.extend(points.into_iter().filter_map(|p| place(&p, &mut sprites)));
        let sets = sprites.sets;
        let masks = || sets.iter().flat_map(|set| set.iter().flatten());
        let reach = (masks().map(|m| m.y0).min().unwrap_or(0), masks().map(|m| m.y0 + m.h as i32).max().unwrap_or(0));
        let (lo, hi) = placed.iter().fold((i32::MAX, i32::MIN), |(lo, hi), p| (lo.min(p.iy), hi.max(p.iy)));
        let rows = if lo > hi { (0, 0) } else { (lo as i64 + reach.0 as i64, hi as i64 + reach.1 as i64) };
        PointBatch { placed, sets, reach, rows }
    }

    /// Pixel rows `[top, bottom)` the batch can touch.
    pub fn rows(&self) -> (i64, i64) {
        self.rows
    }

    /// Splits the points by the `n_bands` bands of `band_rows` rows they
    /// reach (a point spanning two bands is in both), keeping data order.
    pub fn bucket(&self, band_rows: usize, n_bands: usize) -> Buckets {
        let band_rows = band_rows as i64;
        let span = |p: &Placed| {
            let lo = ((p.iy as i64 + self.reach.0 as i64).div_euclid(band_rows)).max(0);
            let hi = ((p.iy as i64 + self.reach.1 as i64 - 1).div_euclid(band_rows)).min(n_bands as i64 - 1);
            (lo, hi)
        };
        let mut starts = vec![0usize; n_bands + 1];
        for p in &self.placed {
            let (lo, hi) = span(p);
            for b in lo..=hi {
                starts[b as usize + 1] += 1;
            }
        }
        for b in 0..n_bands {
            starts[b + 1] += starts[b];
        }
        let mut fill = starts.clone();
        let mut index = vec![0u32; starts[n_bands]];
        for (i, p) in self.placed.iter().enumerate() {
            let (lo, hi) = span(p);
            for b in lo..=hi {
                index[fill[b as usize]] = i as u32;
                fill[b as usize] += 1;
            }
        }
        Buckets { starts, index }
    }

    /// Blends the points `idx` into a band's premultiplied rows (`buf`,
    /// starting at page row `top`), scaled by the clip's pixel shares.
    pub fn draw(&self, buf: &mut [[f32; 4]], top: usize, width: usize, idx: &[u32], clip: &ClipShares) {
        let h = (buf.len() / width) as i32;
        let top = top as i32;
        let (cx0, cx1) = (clip.x.0 as i32, clip.x.1 as i32);
        let (cy0, cy1) = (clip.y.0 as i32, clip.y.1 as i32);
        for &i in idx {
            let p = &self.placed[i as usize];
            let masks = &self.sets[p.set as usize][p.sub as usize];
            let a = p.rgba[3] as f32 / 255.0;
            let colour = [p.rgba[0] as f32 / 255.0 * a, p.rgba[1] as f32 / 255.0 * a, p.rgba[2] as f32 / 255.0 * a, a];
            for m in masks {
                let y0 = p.iy + m.y0 - top;
                let y1 = y0 + m.h as i32;
                let (j0, j1) = (y0.max(cy0), y1.min(cy1).min(h));
                if j0 >= j1 {
                    continue;
                }
                let x0 = p.ix + m.x0;
                let (i0, i1) = ((cx0 - x0).max(0), (cx1 - x0).min(m.w as i32));
                if i0 >= i1 {
                    continue;
                }
                for j in j0..j1 {
                    let ry = clip.rows[j as usize];
                    let mrow = &m.cov[(j - y0) as usize * m.w..][..m.w];
                    let crow = &mut buf[j as usize * width..][..width];
                    for i in i0..i1 {
                        let mut k = mrow[i as usize];
                        if k == 0.0 {
                            continue;
                        }
                        let x = (x0 + i) as usize;
                        k *= ry * clip.cols[x];
                        let d = &mut crow[x];
                        let inv = 1.0 - a * k;
                        for c in 0..4 {
                            d[c] = colour[c] * k + d[c] * inv;
                        }
                    }
                }
            }
        }
    }
}

/// Draws `points` in order on a transparent `width` x `height` canvas, as
/// a one-item display list. Returns non-premultiplied RGBA packed as R's
/// nativeRaster (`R | G << 8 | B << 16 | A << 24`), row-major from the
/// top-left.
pub fn render(width: usize, height: usize, points: impl IntoIterator<Item = Point>) -> Vec<u32> {
    let mut out = vec![0u32; width * height];
    render_into(width, height, points, &raster::Options::default(), &mut out);
    out
}

/// `render()` into `out`, which must hold `width * height` pixels.
pub fn render_into(width: usize, height: usize, points: impl IntoIterator<Item = Point>, opts: &raster::Options, out: &mut [u32]) {
    let mut list = DisplayList::new();
    list.push(Item::Points(PointBatch::new(points)));
    raster::render_into(&list, width, height, opts, out);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(x: f64, y: f64, shape: i32) -> Point {
        Point { x, y, shape, size: 100.0, lwd: 10.0, rgba: [0, 0, 0, 76] }
    }

    fn alpha_at(img: &[u32], w: usize, x: usize, y: usize) -> u32 {
        img[y * w + x] >> 24
    }

    #[test]
    fn disc_has_radius_three_eighths_of_size() {
        let img = render(400, 400, [point(200.0, 200.0, 16)]);
        let row: Vec<u32> = (0..400).map(|x| alpha_at(&img, 400, x, 200)).collect();
        // ragg: 74 full pixels plus a partial one each side (radius 37.5).
        assert_eq!(row.iter().filter(|&&a| a == 76).count(), 74);
        assert!(row[162] > 0 && row[162] < 76 && row[237] > 0 && row[237] < 76);
        assert_eq!(row[161], 0);
    }

    #[test]
    fn plus_blends_twice_where_lines_cross() {
        let img = render(400, 400, [point(200.0, 200.0, 3)]);
        let a = 76.0 / 255.0;
        let twice = ((1.0 - (1.0 - a) * (1.0 - a)) * 255.0f64).round() as u32;
        assert_eq!(alpha_at(&img, 400, 200, 200), twice);
        assert_eq!(alpha_at(&img, 400, 230, 200), 76);
    }

    #[test]
    fn triangle_points_up() {
        let img = render(400, 400, [point(200.0, 200.0, 17)]);
        // Apex 58.3 px above the centre, base 29.2 px below.
        assert!(alpha_at(&img, 400, 200, 143) > 0);
        assert_eq!(alpha_at(&img, 400, 200, 140), 0);
        assert_eq!(alpha_at(&img, 400, 200, 232), 0);
    }

    #[test]
    fn clips_to_canvas_and_skips_non_finite() {
        let mut pts = [point(-2.0, 5.0, 15), point(f64::NAN, 5.0, 16), point(15.0, 5.0, 99)];
        for p in &mut pts {
            p.size = 10.0;
        }
        let img = render(20, 20, pts);
        assert_eq!(alpha_at(&img, 20, 0, 5), 76);
        assert_eq!(alpha_at(&img, 20, 19, 5), 0);
    }

    #[test]
    fn later_points_draw_on_top() {
        let mut a = point(10.0, 10.0, 15);
        a.rgba = [255, 0, 0, 255];
        let mut b = a;
        b.rgba = [0, 0, 255, 255];
        let img = render(20, 20, [a, b]);
        assert_eq!(img[10 * 20 + 10], 0xFF_FF_00_00);
    }
}
