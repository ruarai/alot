//! Point batches rasterised with prebuilt coverage sprites.
//!
//! Symbol geometry mirrors R's `GESymbol()` (R 4.6.1 src/main/engine.c) for
//! pch 0-25, drawn as ragg draws each primitive (ragg 1.5.2
//! src/AggDevice.h): `drawCircle()` with its fixed polygon step counts,
//! `drawRect()` (fill-only rects snap to whole pixels), `drawPolygon()` and
//! `drawLine()`, each a fill and then a separately blended stroke, with
//! grid's default round caps and joins. Coverage comes from the port of
//! AGG's rasteriser and stroker (`agg`), so a sprite has exactly the alpha
//! ragg would give a symbol at that subpixel position. `size` is the symbol
//! size in pixels (grid's fontsize, scaled by res / 72) and `lwd` the line
//! width in pixels (lwd * res / 96).
//!
//! A sprite set holds, for one (shape, size, lwd), the coverage masks of
//! each primitive at SUB x SUB subpixel offsets, built lazily the first
//! time an offset is drawn. Drawing a point is then a masked blend with no
//! geometry. A `PointBatch` is a display-list item; the band executor
//! (`raster`) draws it, each band visiting its points in data order, so
//! overlaps composite as they do on a device.

use crate::render::agg::{self, Cap, Join};
use crate::render::display::{DisplayList, Item, Rect};
use crate::render::raster::{self, ClipShares};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

const RADIUS: f64 = 0.375;
const SMALL: f64 = 0.25;
const SQRC: f64 = 0.88622692545275801364;
const DMDC: f64 = 1.25331413731550025119;
const TRC0: f64 = 1.55512030155621416073;
const TRC1: f64 = 1.34677368708859836060;
const TRC2: f64 = 0.77756015077810708036;
/// grid's default `linemitre`.
const MITRE: f64 = 10.0;

/// Subpixel positions per axis.
const SUB: usize = 32;

/// pch 22 with no visible stroke: `drawRect()` snaps fill-only rects.
const SQUARE_SNAPPED: i32 = 122;

/// Shapes this module draws; anything else should fall back.
pub fn supported_shape(shape: i32) -> bool {
    (0..=25).contains(&shape)
}

/// A point in canvas pixels (origin top-left, pixel i covers [i, i + 1]),
/// with its colour and fill as non-premultiplied RGBA bytes (alpha 0 for
/// NA).
#[derive(Clone, Copy, Debug)]
pub struct Point {
    pub x: f64,
    pub y: f64,
    pub shape: i32,
    pub size: f64,
    pub lwd: f64,
    pub col: [u8; 4],
    pub fill: [u8; 4],
}

/// Which of a point's colours a primitive is drawn in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Role {
    Col,
    Fill,
}

/// One separately blended primitive of a symbol: closed contours filled
/// with the non-zero rule, relative to the symbol's centre.
struct Layer {
    contours: Vec<Vec<[f64; 2]>>,
    role: Role,
    /// A fill-only rect that snaps to whole pixels (`snap_rect`); its
    /// contour is the unsnapped square.
    snap: bool,
}

/// The polygon ragg draws for a circle of radius `r`: `drawCircle()` fixes
/// the step count of `agg::ellipse` below a radius of 20 px and clamps tiny
/// radii to 0.5; above that AGG picks it (`ellipse::calc_num_steps`).
fn circle(r: f64) -> Vec<[f64; 2]> {
    let (r, n) = match r {
        r if r < 1.0 => (r.max(0.5), 4),
        r if r < 2.5 => (r, 8),
        r if r < 5.0 => (r, 16),
        r if r < 10.0 => (r, 32),
        r if r < 20.0 => (r, 64),
        r => {
            let da = (r / (r + 0.125)).acos() * 2.0;
            (r, (2.0 * std::f64::consts::PI / da + 0.5) as usize)
        }
    };
    agg::ellipse(0.0, 0.0, r, n)
}

/// `drawRect(x0, y0, x1, y1)`'s path.
fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
    vec![[x0, y0], [x0, y1], [x1, y1], [x1, y0]]
}

/// A fill-only rect of half width `half` centred at `v` snaps its edges to
/// `round(v - half)` and `round(v + half)` (`drawRect()`), which depends on
/// the exact position, not just its 1/SUB subpixel. Relative to `floor(v)`
/// each edge takes one of two values, so the pair is coded in 0..4.
fn snap_code(v: f64, half: f64) -> usize {
    let f = v - v.floor();
    let (lo, hi) = ((f - half).round(), (f + half).round());
    ((lo - (-half).round()) as usize) * 2 + (hi - half.round()) as usize
}

fn snap_edges(half: f64, code: usize) -> (f64, f64) {
    ((-half).round() + (code / 2) as f64, half.round() + (code % 2) as f64)
}

/// Builds the layers of one symbol, in drawing order.
struct Symbol {
    lwd: f64,
    layers: Vec<Layer>,
}

impl Symbol {
    fn fill(&mut self, poly: Vec<[f64; 2]>, role: Role) {
        self.layers.push(Layer { contours: vec![poly], role, snap: false });
    }

    fn stroke(&mut self, path: &[[f64; 2]], closed: bool) {
        if self.lwd > 0.0 {
            let contours = agg::stroke(path, closed, self.lwd, Join::Round, Cap::Round, MITRE);
            self.layers.push(Layer { contours, role: Role::Col, snap: false });
        }
    }

    fn line(&mut self, a: [f64; 2], b: [f64; 2]) {
        self.stroke(&[a, b], false);
    }

    /// A primitive with an optional fill and the col stroke.
    fn shape(&mut self, poly: Vec<[f64; 2]>, fill: Option<Role>) {
        if let Some(role) = fill {
            self.fill(poly.clone(), role);
        }
        self.stroke(&poly, true);
    }
}

/// The layers of `shape` centred on the origin, device y pointing down. As
/// in `GESymbol()`, heights are negated (`toDeviceHeight()` is negative
/// when device y points down).
fn layers(shape: i32, size: f64, lwd: f64) -> Vec<Layer> {
    let mut s = Symbol { lwd, layers: Vec::new() };
    let r = RADIUS * size;
    let sq2 = std::f64::consts::SQRT_2;
    let square = |xc: f64, yc: f64| rect(-xc, -yc, xc, yc);
    let plus = |s: &mut Symbol, xc: f64, yc: f64| {
        s.line([-xc, 0.0], [xc, 0.0]);
        s.line([0.0, -yc], [0.0, yc]);
    };
    let times = |s: &mut Symbol, xc: f64, yc: f64| {
        s.line([-xc, -yc], [xc, yc]);
        s.line([-xc, yc], [xc, -yc]);
    };
    let diamond = |xc: f64, yc: f64| vec![[-xc, 0.0], [0.0, yc], [xc, 0.0], [0.0, -yc]];
    // Triangles: apex height `tr`, base height `tyc`, half width `txc`.
    let (tr, tyc, txc) = (-TRC0 * r, -TRC2 * r, TRC1 * r);
    let up = vec![[0.0, tr], [txc, -tyc], [-txc, -tyc]];
    let down = vec![[0.0, -tr], [txc, tyc], [-txc, tyc]];
    match shape {
        0 => s.shape(square(r, -r), None),
        1 => s.shape(circle(r), None),
        2 => s.shape(up, None),
        3 => plus(&mut s, sq2 * r, -sq2 * r),
        4 => times(&mut s, r, -r),
        5 => s.shape(diamond(sq2 * r, -sq2 * r), None),
        6 => s.shape(down, None),
        7 => {
            s.shape(square(r, -r), None);
            times(&mut s, r, -r);
        }
        8 => {
            times(&mut s, r, -r);
            plus(&mut s, sq2 * r, -sq2 * r);
        }
        9 => {
            plus(&mut s, sq2 * r, -sq2 * r);
            s.shape(diamond(sq2 * r, -sq2 * r), None);
        }
        10 => {
            s.shape(circle(r), None);
            plus(&mut s, r, -r);
        }
        11 => {
            let yc = 0.5 * (tyc + tr);
            s.shape(vec![[0.0, -tr], [txc, yc], [-txc, yc]], None);
            s.shape(vec![[0.0, tr], [txc, -yc], [-txc, -yc]], None);
        }
        12 => {
            plus(&mut s, r, -r);
            s.shape(square(r, -r), None);
        }
        13 => {
            s.shape(circle(r), None);
            times(&mut s, r, -r);
        }
        14 => {
            s.shape(vec![[0.0, -r], [r, r], [-r, r]], None);
            s.shape(square(r, -r), None);
        }
        15 => s.fill(vec![[-r, r], [r, r], [r, -r], [-r, -r]], Role::Col),
        16 => s.fill(circle(r), Role::Col),
        17 => s.fill(up, Role::Col),
        18 => s.fill(diamond(r, -r), Role::Col),
        19 => s.shape(circle(r), Some(Role::Col)),
        20 => s.shape(circle(SMALL * size), Some(Role::Col)),
        21 => s.shape(circle(r), Some(Role::Fill)),
        22 => s.shape(square(r * SQRC, -r * SQRC), Some(Role::Fill)),
        SQUARE_SNAPPED => {
            s.layers.push(Layer { contours: vec![square(r * SQRC, -r * SQRC)], role: Role::Fill, snap: true });
        }
        23 => {
            let (xc, yc) = (r * DMDC, -r * DMDC);
            s.shape(vec![[0.0, -yc], [xc, 0.0], [0.0, yc], [-xc, 0.0]], Some(Role::Fill));
        }
        24 => s.shape(up, Some(Role::Fill)),
        25 => s.shape(down, Some(Role::Fill)),
        _ => {}
    }
    s.layers
}

/// Coverage of one layer, over pixels [x0, x0 + w) x [y0, y0 + h) relative
/// to the pixel holding the point, as alpha bytes.
struct Mask {
    x0: i32,
    y0: i32,
    w: usize,
    h: usize,
    cov: Vec<u8>,
    role: Role,
    /// Index of the layer in the sprite set.
    layer: usize,
}

/// One (shape, size, lwd): its layers and the masks built so far, one slot
/// per subpixel offset.
struct SpriteSet {
    layers: Vec<Layer>,
    /// SUB rows of SUB slots; a row is allocated when first used, so a set
    /// drawn for a few points stays small.
    slots: Box<[OnceLock<Box<[OnceLock<Box<[Mask]>>]>>]>,
    /// Pixel rows any mask can reach relative to its point's pixel:
    /// `[reach.0, reach.1)`.
    reach: (i32, i32),
}

impl SpriteSet {
    fn new(shape: i32, size: f64, lwd: f64) -> Self {
        let layers = layers(shape, size, lwd);
        let ext = layers.iter().flat_map(|l| l.contours.iter().flatten()).fold(0.0f64, |m, p| m.max(p[0].abs()).max(p[1].abs()));
        let e = ext.ceil() as i32 + 1;
        SpriteSet { layers, slots: (0..SUB).map(|_| OnceLock::new()).collect(), reach: (-e, e + 2) }
    }

    fn masks(&self, sub: usize) -> &[Mask] {
        let row = self.slots[sub / SUB].get_or_init(|| (0..SUB).map(|_| OnceLock::new()).collect());
        row[sub % SUB].get_or_init(|| {
            let fx = ((sub % SUB) as f64 + 0.5) / SUB as f64;
            let fy = ((sub / SUB) as f64 + 0.5) / SUB as f64;
            self.layers
                .iter()
                .enumerate()
                .filter_map(|(layer, l)| {
                    let placed: Vec<Vec<[f64; 2]>> = if l.snap {
                        // `sub` holds the rounded edges (see `snap_code()`).
                        let half = l.contours[0][2][0];
                        let (x0, x1) = snap_edges(half, sub % SUB);
                        let (y0, y1) = snap_edges(half, sub / SUB);
                        vec![rect(x0, y0, x1, y1)]
                    } else {
                        l.contours.iter().map(|c| c.iter().map(|&[x, y]| [x + fx, y + fy]).collect()).collect()
                    };
                    let c = agg::rasterize(&placed);
                    (c.w > 0).then_some(Mask { x0: c.x0, y0: c.y0, w: c.w, h: c.h, cov: c.alpha, role: l.role, layer })
                })
                .collect()
        })
    }
}

impl SpriteSet {
    /// The coverage of layer `layer` of a point at pixel (`ix`, `iy`) and
    /// subpixel `sub`, clipped to `clip` geometrically as ragg clips each
    /// mark, in page pixels. Used where the clip edge crosses a mask.
    fn clipped(&self, layer: usize, ix: i32, iy: i32, sub: usize, clip: &Rect) -> agg::Coverage {
        let fx = ix as f64 + ((sub % SUB) as f64 + 0.5) / SUB as f64;
        let fy = iy as f64 + ((sub / SUB) as f64 + 0.5) / SUB as f64;
        let placed: Vec<Vec<[f64; 2]>> = self.layers[layer].contours.iter().map(|c| c.iter().map(|&[x, y]| [x + fx, y + fy]).collect()).collect();
        agg::rasterize(&agg::clip_contours(&placed, clip.x0, clip.y0, clip.x1, clip.y1))
    }
}

type Key = (i32, u64, u64);

/// Sprite sets built so far in this process, shared across panels and
/// draws. Cleared when it grows past `CACHE_MAX` sets (plots mapping size
/// to many distinct values).
static CACHE: Mutex<Option<HashMap<Key, Arc<SpriteSet>>>> = Mutex::new(None);
const CACHE_MAX: usize = 1 << 14;

fn sprite_set(key: Key) -> Arc<SpriteSet> {
    if let Some(set) = CACHE.lock().unwrap_or_else(|e| e.into_inner()).as_ref().and_then(|c| c.get(&key)) {
        return set.clone();
    }
    // Built outside the lock so workers placing different sizes don't wait
    // on each other; a set built twice by two workers is identical.
    let set = Arc::new(SpriteSet::new(key.0, f64::from_bits(key.1), f64::from_bits(key.2)));
    let mut cache = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    let cache = cache.get_or_insert_with(HashMap::new);
    if cache.len() >= CACHE_MAX {
        cache.clear();
    }
    cache.entry(key).or_insert(set).clone()
}

const NONE: u32 = u32::MAX;

/// A worker's sprite-set lookup during placement. The latest (size, lwd)
/// seen for each shape is checked first, so a batch with constant size and
/// stroke never hashes; other keys go through a local map.
struct Lookup {
    sets: Vec<Arc<SpriteSet>>,
    recent: [(u64, u64, u32); 128],
    index: HashMap<Key, u32>,
}

impl Lookup {
    fn new() -> Self {
        Lookup { sets: Vec::new(), recent: [(0, 0, NONE); 128], index: HashMap::new() }
    }

    /// Shapes 0-25 and 122 have distinct slots in `recent`.
    fn get(&mut self, key: Key) -> u32 {
        let slot = key.0 as usize & 127;
        let (size, lwd, i) = self.recent[slot];
        if i != NONE && (size, lwd) == (key.1, key.2) {
            return i;
        }
        let i = match self.index.get(&key) {
            Some(&i) => i,
            None => {
                self.sets.push(sprite_set(key));
                let i = (self.sets.len() - 1) as u32;
                self.index.insert(key, i);
                i
            }
        };
        self.recent[slot] = (key.1, key.2, i);
        i
    }
}

/// A point snapped to its pixel and subpixel sprite; `set` is `NONE` for
/// points that draw nothing.
#[derive(Clone, Copy)]
struct Placed {
    ix: i32,
    iy: i32,
    set: u32,
    sub: u16,
    col: [u8; 4],
    fill: [u8; 4],
}

const SKIPPED: Placed = Placed { ix: 0, iy: 0, set: NONE, sub: 0, col: [0; 4], fill: [0; 4] };

fn place(p: &Point, lookup: &mut Lookup) -> Placed {
    let finite = p.x.is_finite() && p.y.is_finite() && p.size.is_finite() && p.lwd.is_finite();
    if !finite || !supported_shape(p.shape) || (p.col[3] == 0 && p.fill[3] == 0) {
        return SKIPPED;
    }
    // Pixel and subpixel in one step (`floor()` is a libm call on the
    // baseline x86-64 target). Positions beyond i32 are off any canvas.
    let split = |v: f64| {
        let t = (v * SUB as f64).clamp(-1e9, 1e9);
        let k = t as i64 - (t < (t as i64) as f64) as i64;
        ((k.div_euclid(SUB as i64)) as i32, k.rem_euclid(SUB as i64) as usize)
    };
    let (ix, mut sx) = split(p.x);
    let (iy, mut sy) = split(p.y);
    // drawRect() snaps a fill-only rect: pch 22 whose stroke doesn't draw.
    let snapped = p.shape == 22 && (p.lwd <= 0.0 || p.col[3] == 0);
    let shape = if snapped { SQUARE_SNAPPED } else { p.shape };
    let lwd = if p.lwd > 0.0 { p.lwd } else { 0.0 };
    let set = lookup.get((shape, p.size.to_bits(), lwd.to_bits()));
    if snapped {
        let half = RADIUS * SQRC * p.size;
        sx = snap_code(p.x, half);
        sy = snap_code(p.y, half);
    }
    Placed { ix, iy, set, sub: (sy * SUB + sx) as u16, col: p.col, fill: p.fill }
}

/// Placement buffers kept between batches: fresh multi-megabyte
/// allocations cost more in page faults than placing the points.
static PLACED_POOL: Mutex<Vec<Vec<Placed>>> = Mutex::new(Vec::new());

/// A display-list point batch (`display::Item::Points`): points snapped to
/// their sprites, drawn in data order.
pub struct PointBatch {
    placed: Vec<Placed>,
    sets: Vec<Arc<SpriteSet>>,
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
    /// Places `points` with up to `threads` workers (0: the default).
    /// Points with unsupported shapes, no visible colour or non-finite
    /// positions draw nothing; callers check `supported_shape()` first.
    pub fn new(points: &[Point], threads: usize) -> Self {
        Self::from_fn(points.len(), threads, |i| Some(points[i]))
    }

    /// Like `new()`, for points `0..n` computed by `point` (`None` draws
    /// nothing) inside the parallel placement, so callers need not
    /// materialise them.
    pub fn from_fn(n: usize, threads: usize, point: impl Fn(usize) -> Option<Point> + Sync) -> Self {
        let threads = if threads == 0 { raster::default_threads() } else { threads };
        let mut placed = PLACED_POOL.lock().unwrap_or_else(|e| e.into_inner()).pop().unwrap_or_default();
        placed.clear();
        placed.resize(n, SKIPPED);
        // Small batches aren't worth a thread each.
        let chunk = n.div_ceil(threads).max(4096);
        let point = &point;
        let lookups: Vec<Lookup> = std::thread::scope(|scope| {
            let handles: Vec<_> = placed
                .chunks_mut(chunk)
                .enumerate()
                .map(|(c, dst)| {
                    scope.spawn(move || {
                        let mut lookup = Lookup::new();
                        for (k, d) in dst.iter_mut().enumerate() {
                            if let Some(p) = point(c * chunk + k) {
                                *d = place(&p, &mut lookup);
                            }
                        }
                        lookup
                    })
                })
                .collect();
            handles.into_iter().map(|h| h.join().unwrap()).collect()
        });
        // Workers numbered their own sets; offset them into one list.
        let mut sets = Vec::new();
        let mut offsets = Vec::new();
        for mut l in lookups {
            offsets.push(sets.len() as u32);
            sets.append(&mut l.sets);
        }
        if offsets.iter().any(|&o| o > 0) {
            std::thread::scope(|scope| {
                for (dst, &off) in placed.chunks_mut(chunk).zip(&offsets) {
                    scope.spawn(move || {
                        for d in dst.iter_mut().filter(|d| d.set != NONE) {
                            d.set += off;
                        }
                    });
                }
            });
        }
        let (lo, hi) = placed.iter().filter(|p| p.set != NONE).fold((i64::MAX, i64::MIN), |(lo, hi), p| {
            let r = sets[p.set as usize].reach;
            (lo.min(p.iy as i64 + r.0 as i64), hi.max(p.iy as i64 + r.1 as i64))
        });
        let rows = if lo > hi { (0, 0) } else { (lo, hi) };
        PointBatch { placed, sets, rows }
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
            if p.set == NONE {
                return (0, -1);
            }
            let r = self.sets[p.set as usize].reach;
            let lo = ((p.iy as i64 + r.0 as i64).div_euclid(band_rows)).max(0);
            let hi = ((p.iy as i64 + r.1 as i64 - 1).div_euclid(band_rows)).min(n_bands as i64 - 1);
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
        let premul = |c: [u8; 4]| {
            let a = c[3] as f32 / 255.0;
            [c[0] as f32 / 255.0 * a, c[1] as f32 / 255.0 * a, c[2] as f32 / 255.0 * a, a]
        };
        for &i in idx {
            let p = &self.placed[i as usize];
            let set = &self.sets[p.set as usize];
            let (col, fill) = (premul(p.col), premul(p.fill));
            for m in set.masks(p.sub as usize) {
                let colour = if m.role == Role::Fill { fill } else { col };
                let a = colour[3];
                if a == 0.0 {
                    continue;
                }
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
                let snap = set.layers[m.layer].snap;
                if !snap && clip.crosses_edge(j0 as usize, j1 as usize, (x0 + i0) as usize, (x0 + i1) as usize) {
                    let c = set.clipped(m.layer, p.ix, p.iy, p.sub as usize, &clip.rect);
                    blend_coverage(buf, top, width, h, &c, colour);
                    continue;
                }
                for j in j0..j1 {
                    let ry = clip.rows[j as usize] / 255.0;
                    let mrow = &m.cov[(j - y0) as usize * m.w..][..m.w];
                    let crow = &mut buf[j as usize * width..][..width];
                    for i in i0..i1 {
                        let c = mrow[i as usize];
                        if c == 0 {
                            continue;
                        }
                        let x = (x0 + i) as usize;
                        let k = c as f32 * ry * clip.cols[x];
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

/// Blends page-pixel coverage `c` in `colour` (premultiplied) into a
/// band's rows.
fn blend_coverage(buf: &mut [[f32; 4]], top: i32, width: usize, h: i32, c: &agg::Coverage, colour: [f32; 4]) {
    let a = colour[3];
    for j in 0..c.h as i32 {
        let y = c.y0 + j - top;
        if y < 0 || y >= h {
            continue;
        }
        for i in 0..c.w as i32 {
            let x = c.x0 + i;
            let k = c.alpha[(j * c.w as i32 + i) as usize];
            if k == 0 || x < 0 || x >= width as i32 {
                continue;
            }
            let k = k as f32 / 255.0;
            let d = &mut buf[y as usize * width + x as usize];
            let inv = 1.0 - a * k;
            for ch in 0..4 {
                d[ch] = colour[ch] * k + d[ch] * inv;
            }
        }
    }
}

/// Draws `points` in order on a transparent `width` x `height` canvas, as
/// a one-item display list. Returns non-premultiplied RGBA packed as R's
/// nativeRaster (`R | G << 8 | B << 16 | A << 24`), row-major from the
/// top-left.
pub fn render(width: usize, height: usize, points: &[Point]) -> Vec<u32> {
    let mut out = vec![0u32; width * height];
    render_into(width, height, points, &raster::Options::default(), None, &mut out);
    out
}

/// `render()` into `out`, which must hold `width * height` pixels, with
/// each point clipped to `clip` if given (as ragg clips each mark).
pub fn render_into(width: usize, height: usize, points: &[Point], opts: &raster::Options, clip: Option<Rect>, out: &mut [u32]) {
    render_batch(width, height, PointBatch::new(points, opts.threads), opts, clip, out);
}

/// Draws a placed batch as `render_into()` does.
pub fn render_batch(width: usize, height: usize, batch: PointBatch, opts: &raster::Options, clip: Option<Rect>, out: &mut [u32]) {
    let mut list = DisplayList::new();
    if let Some(r) = clip {
        list.push(Item::PushClip(r));
    }
    list.push(Item::Points(batch));
    raster::render_into(&list, width, height, opts, out);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(x: f64, y: f64, shape: i32) -> Point {
        Point { x, y, shape, size: 100.0, lwd: 10.0, col: [0, 0, 0, 76], fill: [0; 4] }
    }

    fn alpha_at(img: &[u32], w: usize, x: usize, y: usize) -> u32 {
        img[y * w + x] >> 24
    }

    #[test]
    fn disc_has_radius_three_eighths_of_size() {
        let img = render(400, 400, &[point(200.0, 200.0, 16)]);
        let row: Vec<u32> = (0..400).map(|x| alpha_at(&img, 400, x, 200)).collect();
        // ragg: 74 full pixels plus a partial one each side (radius 37.5).
        assert_eq!(row.iter().filter(|&&a| a == 76).count(), 74);
        assert!(row[162] > 0 && row[162] < 76 && row[237] > 0 && row[237] < 76);
        assert_eq!(row[161], 0);
    }

    #[test]
    fn plus_blends_twice_where_lines_cross() {
        let img = render(400, 400, &[point(200.0, 200.0, 3)]);
        let a = 76.0 / 255.0;
        let twice = ((1.0 - (1.0 - a) * (1.0 - a)) * 255.0f64).round() as u32;
        assert_eq!(alpha_at(&img, 400, 200, 200), twice);
        assert_eq!(alpha_at(&img, 400, 230, 200), 76);
    }

    #[test]
    fn triangles_point_up_and_down() {
        let img = render(400, 400, &[point(200.0, 200.0, 17)]);
        // Apex 58.3 px above the centre, base 29.2 px below.
        assert!(alpha_at(&img, 400, 200, 143) > 0);
        assert_eq!(alpha_at(&img, 400, 200, 140), 0);
        assert_eq!(alpha_at(&img, 400, 200, 232), 0);
        let mut p = point(200.0, 200.0, 25);
        p.fill = [0, 0, 0, 255];
        let img = render(400, 400, &[p]);
        assert!(alpha_at(&img, 400, 200, 256) > 0);
        assert_eq!(alpha_at(&img, 400, 200, 140), 0);
    }

    #[test]
    fn clips_to_canvas_and_skips_non_finite() {
        let mut pts = [point(-2.0, 5.0, 15), point(f64::NAN, 5.0, 16), point(15.0, 5.0, 99)];
        for p in &mut pts {
            p.size = 10.0;
        }
        let img = render(20, 20, &pts);
        assert_eq!(alpha_at(&img, 20, 0, 5), 76);
        assert_eq!(alpha_at(&img, 20, 19, 5), 0);
    }

    #[test]
    fn later_points_draw_on_top() {
        let mut a = point(10.0, 10.0, 15);
        a.col = [255, 0, 0, 255];
        let mut b = a;
        b.col = [0, 0, 255, 255];
        let img = render(20, 20, &[a, b]);
        assert_eq!(img[10 * 20 + 10], 0xFF_FF_00_00);
    }

    #[test]
    fn filled_shapes_use_fill_inside_and_col_outline() {
        for shape in 21..=25 {
            let mut p = point(50.0, 50.0, shape);
            p.size = 40.0;
            p.lwd = 4.0;
            p.col = [255, 0, 0, 255];
            p.fill = [0, 0, 255, 255];
            let img = render(100, 100, &[p]);
            assert_eq!(img[50 * 100 + 50], 0xFF_FF_00_00, "shape {shape}: centre is fill");
            // NA fill: only the outline.
            p.fill = [0; 4];
            let img = render(100, 100, &[p]);
            assert_eq!(img[50 * 100 + 50], 0, "shape {shape}: hollow without fill");
        }
    }

    #[test]
    fn every_shape_draws_and_hollow_ones_are_hollow() {
        for shape in 0..=25 {
            let mut p = point(50.0, 50.0, shape);
            p.size = 40.0;
            p.lwd = 2.0;
            p.col = [0, 0, 0, 255];
            let img = render(100, 100, &[p]);
            assert!(img.iter().any(|&px| px >> 24 > 0), "shape {shape}");
            let off_centre = img[46 * 100 + 47] >> 24;
            if matches!(shape, 0 | 1 | 2 | 5 | 6 | 21..=25) {
                assert_eq!(off_centre, 0, "shape {shape} is hollow");
            }
            if matches!(shape, 15..=20) {
                assert_eq!(off_centre, 255, "shape {shape} is filled");
            }
        }
    }

    #[test]
    fn fill_only_square_snaps_to_pixels() {
        let mut p = point(10.3, 10.3, 22);
        p.size = 8.0 / (RADIUS * SQRC * 2.0) + 0.4;
        p.lwd = 0.0;
        p.fill = [0, 0, 0, 255];
        let img = render(20, 20, &[p]);
        assert!(img.iter().all(|&px| px >> 24 == 0 || px >> 24 == 255));
        p.lwd = 1.0;
        let img = render(20, 20, &[p]);
        assert!(img.iter().any(|&px| px >> 24 > 0 && px >> 24 < 255));
    }

    #[test]
    fn placement_is_the_same_with_any_thread_count() {
        let pts: Vec<Point> = (0..20_000)
            .map(|i| {
                let mut p = point((i * 7 % 300) as f64 + 0.37, (i * 13 % 200) as f64 + 0.71, (i % 26) as i32);
                p.size = 3.0 + (i % 5) as f64;
                p.lwd = 1.0;
                p.fill = [10, 200, 30, 120];
                p
            })
            .collect();
        let draw = |threads| {
            let mut out = vec![0u32; 300 * 200];
            render_into(300, 200, &pts, &raster::Options { threads, band_rows: 32 }, None, &mut out);
            out
        };
        assert_eq!(draw(1), draw(7));
    }
}
