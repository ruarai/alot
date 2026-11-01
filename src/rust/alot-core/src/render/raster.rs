//! The band executor (PHASE2.md, Architecture 6). The page is split into
//! row bands drawn in parallel. Each worker draws into an f32 premultiplied
//! RGBA buffer of one band, reused across bands and calls, so memory is
//! bounded by `threads * band_rows * width` rather than the page size. Each
//! band walks the display list in order, skipping items outside its rows,
//! so overlaps composite as on a device. Finished bands are converted to
//! non-premultiplied 8-bit RGBA and handed over in row order.
//!
//! Clipping mirrors ragg (1.5.2 src/AggDevice.h, `clipRect()`): the clip box
//! is set fractionally on AGG's rasteriser, so marks are cut at the box's
//! fractional edges and pixels the edge crosses keep the covered share.

use crate::render::display::{DisplayList, Item, Rect};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

/// How a page is executed.
#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Worker threads; 0 means `default_threads()`.
    pub threads: usize,
    /// Rows per band.
    pub band_rows: usize,
}

impl Default for Options {
    fn default() -> Self {
        Options { threads: 0, band_rows: 64 }
    }
}

impl Options {
    fn threads(&self) -> usize {
        if self.threads == 0 { default_threads() } else { self.threads }
    }
}

/// Available cores, capped at 8 (PHASE2.md, User API). R's
/// `_R_CHECK_LIMIT_CORES_` cap is applied by the R side.
pub fn default_threads() -> usize {
    std::thread::available_parallelism().map_or(1, |n| n.get()).min(8)
}

/// `f` of each of `items`, in order: the first on this thread and the rest
/// on scoped threads. Starting a thread costs tens of microseconds, more
/// than the small batches of a page's axes and grid lines take, so callers
/// pass one item for small inputs and nothing is spawned.
pub fn par_map<I: Send, T: Send>(items: impl IntoIterator<Item = I>, f: impl Fn(I) -> T + Sync) -> Vec<T> {
    let mut items = items.into_iter();
    let Some(first) = items.next() else { return Vec::new() };
    let f = &f;
    std::thread::scope(|scope| {
        let handles: Vec<_> = items.map(|i| scope.spawn(move || f(i))).collect();
        let mut out = vec![f(first)];
        out.extend(handles.into_iter().map(|h| h.join().unwrap()));
        out
    })
}

/// Band buffers kept between calls: fresh multi-megabyte buffers cost more
/// in page faults than drawing into them.
static POOL: Mutex<Vec<Vec<[f32; 4]>>> = Mutex::new(Vec::new());

/// Bytes the executor holds for its band buffers while drawing a page of
/// `width` with `opts`: the memory bound.
pub fn band_memory(width: usize, opts: &Options) -> usize {
    opts.threads() * opts.band_rows * width * (std::mem::size_of::<[f32; 4]>() + std::mem::size_of::<u32>())
}

/// For each band, the indices of an item's marks that reach it, in data
/// order.
pub struct Buckets {
    starts: Vec<usize>,
    index: Vec<u32>,
}

impl Buckets {
    /// Splits marks `0..n` by the `n_bands` bands of `band_rows` rows their
    /// rows `[top, bottom)` reach (`None`: draws nothing); a mark spanning
    /// two bands is in both. Chunks of marks are counted and filled in
    /// parallel, each into its own ranges of the index.
    pub fn new(n: usize, band_rows: usize, n_bands: usize, rows: impl Fn(usize) -> Option<(i64, i64)> + Sync) -> Self {
        let band_rows = band_rows as i64;
        let span = |i: usize| match rows(i) {
            Some((top, bottom)) if bottom > top => {
                let lo = top.div_euclid(band_rows).max(0);
                let hi = (bottom - 1).div_euclid(band_rows).min(n_bands as i64 - 1);
                (lo, hi)
            }
            _ => (0, -1),
        };
        let chunk = n.div_ceil(default_threads()).max(1 << 14);
        let chunks: Vec<(usize, usize)> = (0..n).step_by(chunk.max(1)).map(|a| (a, (a + chunk).min(n))).collect();
        let span = &span;
        let counts: Vec<Vec<usize>> = par_map(chunks.iter(), |&(a, b)| {
            let mut c = vec![0usize; n_bands];
            for i in a..b {
                let (lo, hi) = span(i);
                for band in lo..=hi {
                    c[band as usize] += 1;
                }
            }
            c
        });
        // Each band's run of the index holds its marks chunk by chunk, so
        // data order is kept.
        let mut starts = vec![0usize; n_bands + 1];
        let mut offsets = vec![vec![0usize; n_bands]; chunks.len()];
        let mut at = 0;
        for band in 0..n_bands {
            starts[band] = at;
            for (c, counts) in counts.iter().enumerate() {
                offsets[c][band] = at;
                at += counts[band];
            }
        }
        starts[n_bands] = at;
        let mut index = vec![0u32; at];
        struct Out(*mut u32);
        unsafe impl Sync for Out {}
        let out = Out(index.as_mut_ptr());
        let out = &out;
        par_map(chunks.iter().zip(offsets), |(&(a, b), mut offsets)| {
            for i in a..b {
                let (lo, hi) = span(i);
                for band in lo..=hi {
                    // SAFETY: (chunk, band) ranges are disjoint and within
                    // `index`, by construction above.
                    unsafe { *out.0.add(offsets[band as usize]) = i as u32 };
                    offsets[band as usize] += 1;
                }
            }
        });
        Buckets { starts, index }
    }

    pub fn band(&self, b: usize) -> &[u32] {
        &self.index[self.starts[b]..self.starts[b + 1]]
    }
}

/// Per-item data computed once per page: which marks each band draws.
enum Prepared {
    None,
    Marks(Buckets),
}

struct Page<'a> {
    list: &'a DisplayList,
    prepared: Vec<Prepared>,
    width: usize,
    height: usize,
    band_rows: usize,
}

/// Draws `list` on a `width` x `height` page, calling `sink(top, pixels)`
/// for each band in row order. `pixels` are the band's rows, packed as R's
/// nativeRaster (`R | G << 8 | B << 16 | A << 24`, non-premultiplied).
pub fn execute(list: &DisplayList, width: usize, height: usize, opts: &Options, mut sink: impl FnMut(usize, &[u32])) {
    let threads = opts.threads();
    let band_rows = opts.band_rows.max(1);
    let page = prepare(list, width, height, band_rows);
    let n_bands = height.div_ceil(band_rows);
    // Bands are drawn in waves of `threads`, each into its own output rows,
    // and handed over in order once the wave is done.
    let mut out = vec![0u32; (threads * band_rows * width).min(width * height)];
    let mut first = 0;
    while first < n_bands {
        let last = (first + threads).min(n_bands);
        let rows = (last * band_rows).min(height) - first * band_rows;
        let wave = &mut out[..rows * width];
        draw_bands(&page, first, wave, threads);
        for b in first..last {
            let top = b * band_rows;
            let h = band_rows.min(height - top);
            let off = (top - first * band_rows) * width;
            sink(top, &wave[off..off + h * width]);
        }
        first = last;
    }
}

/// Draws `list` into `out`, which holds `width * height` pixels (see
/// `execute()` for the format).
pub fn render_into(list: &DisplayList, width: usize, height: usize, opts: &Options, out: &mut [u32]) {
    assert_eq!(out.len(), width * height);
    let band_rows = opts.band_rows.max(1);
    let page = prepare(list, width, height, band_rows);
    draw_bands(&page, 0, out, opts.threads());
}

/// `render_into()` a new buffer.
pub fn render(list: &DisplayList, width: usize, height: usize, opts: &Options) -> Vec<u32> {
    let mut out = vec![0u32; width * height];
    render_into(list, width, height, opts, &mut out);
    out
}

fn prepare(list: &DisplayList, width: usize, height: usize, band_rows: usize) -> Page<'_> {
    let n_bands = height.div_ceil(band_rows);
    let prepared = list
        .items
        .iter()
        .map(|item| match item {
            Item::Points(b) => Prepared::Marks(b.bucket(band_rows, n_bands)),
            Item::Rects(b) => Prepared::Marks(b.bucket(band_rows, n_bands)),
            Item::Paths(b) => Prepared::Marks(b.bucket(band_rows, n_bands)),
            _ => Prepared::None,
        })
        .collect();
    Page { list, prepared, width, height, band_rows }
}

/// Draws the bands covering `out`, starting at band `first`, with up to
/// `threads` workers taking bands in turn.
fn draw_bands(page: &Page, first: usize, out: &mut [u32], threads: usize) {
    let width = page.width;
    if width == 0 || out.is_empty() {
        return;
    }
    let bands: Vec<Mutex<(usize, &mut [u32])>> = out
        .chunks_mut(page.band_rows * width)
        .enumerate()
        .map(|(i, rows)| Mutex::new((first + i, rows)))
        .collect();
    let workers = threads.clamp(1, bands.len());
    let mut buffers: Vec<Vec<[f32; 4]>> = {
        let mut pool = POOL.lock().unwrap_or_else(|e| e.into_inner());
        (0..workers).map(|_| pool.pop().unwrap_or_default()).collect()
    };
    let next = AtomicUsize::new(0);
    let work = |buf: &mut Vec<[f32; 4]>| loop {
        let i = next.fetch_add(1, Ordering::Relaxed);
        let Some(band) = bands.get(i) else { break };
        let mut band = band.lock().unwrap();
        let (b, ref mut rows) = *band;
        buf.clear();
        buf.resize(rows.len(), [0.0; 4]);
        draw_band(page, b, buf);
        for (d, &[r, g, b, a]) in rows.iter_mut().zip(buf.iter()) {
            *d = unpremultiply(r, g, b, a);
        }
    };
    par_map(buffers.iter_mut(), work);
    POOL.lock().unwrap_or_else(|e| e.into_inner()).extend(buffers);
}

/// Shares of each pixel column and band row inside the current clip.
pub struct ClipShares {
    /// The clip box in page pixels.
    pub rect: Rect,
    pub cols: Vec<f32>,
    pub rows: Vec<f32>,
    /// Columns and band rows with a non-zero share: `[lo, hi)`.
    pub x: (usize, usize),
    pub y: (usize, usize),
    /// The (at most two) columns and band rows the clip edges cross, with a
    /// share strictly between 0 and 1.
    edge_cols: [usize; 2],
    edge_rows: [usize; 2],
}

impl ClipShares {
    fn new(clip: &Rect, top: usize, width: usize, height: usize) -> Self {
        let cols: Vec<f32> = (0..width).map(|i| clip.x_share(i)).collect();
        let rows: Vec<f32> = (0..height).map(|j| clip.y_share(top + j)).collect();
        let span = |v: &[f32]| match v.iter().position(|&s| s > 0.0) {
            Some(lo) => (lo, v.len() - v.iter().rev().position(|&s| s > 0.0).unwrap()),
            None => (0, 0),
        };
        let edges = |v: &[f32], (lo, hi): (usize, usize)| {
            let partial = |k: usize| k < v.len() && v[k] > 0.0 && v[k] < 1.0;
            let first = if partial(lo) { lo } else { usize::MAX };
            let last = if hi > 0 && partial(hi - 1) { hi - 1 } else { usize::MAX };
            [first, last]
        };
        let (x, y) = (span(&cols), span(&rows));
        ClipShares { rect: *clip, edge_cols: edges(&cols, x), edge_rows: edges(&rows, y), x, y, cols, rows }
    }

    /// Whether band rows `[j0, j1)` or columns `[i0, i1)` include one a clip
    /// edge crosses, where a per-pixel share is not the clipped mark's
    /// coverage.
    pub fn crosses_edge(&self, j0: usize, j1: usize, i0: usize, i1: usize) -> bool {
        self.edge_rows.iter().any(|&k| (j0..j1).contains(&k)) || self.edge_cols.iter().any(|&k| (i0..i1).contains(&k))
    }
}

fn draw_band(page: &Page, b: usize, buf: &mut [[f32; 4]]) {
    let width = page.width;
    let top = b * page.band_rows;
    let h = buf.len() / width;
    let full = Rect { x0: 0.0, y0: 0.0, x1: width as f64, y1: page.height as f64 };
    let mut stack = vec![full];
    let mut shares = ClipShares::new(&full, top, width, h);
    for (item, prep) in page.list.items.iter().zip(&page.prepared) {
        if let Some((y0, y1)) = item.rows() {
            if y1 <= top as i64 || y0 >= (top + h) as i64 {
                continue;
            }
        }
        match (item, prep) {
            (Item::Clear(rgba), _) => {
                let c = premultiply(*rgba);
                buf.fill(c);
            }
            (Item::PushClip(r), _) => {
                let clip = stack.last().unwrap().intersect(r);
                stack.push(clip);
                shares = ClipShares::new(&clip, top, width, h);
            }
            (Item::PopClip, _) => {
                if stack.len() > 1 {
                    stack.pop();
                }
                shares = ClipShares::new(stack.last().unwrap(), top, width, h);
            }
            (Item::Points(batch), Prepared::Marks(buckets)) => {
                batch.draw(buf, top, width, buckets.band(b), &shares);
            }
            (Item::Rects(batch), Prepared::Marks(buckets)) => {
                batch.draw(buf, top, width, buckets.band(b), &shares);
            }
            (Item::Paths(batch), Prepared::Marks(buckets)) => {
                batch.draw(buf, top, width, buckets.band(b), &shares);
            }
            (Item::Image(img), _) => blend_image(img, buf, top, width),
            (Item::Raster(r), _) => r.draw(buf, top, width, &shares.rect),
            _ => {}
        }
    }
}

/// Blends a premultiplied image over a band's rows.
fn blend_image(img: &crate::render::text::Image, buf: &mut [[f32; 4]], top: usize, width: usize) {
    let h = buf.len() / width;
    for j in 0..img.h {
        let y = img.y0 as i64 + j as i64 - top as i64;
        if y < 0 || y >= h as i64 {
            continue;
        }
        for i in 0..img.w {
            let x = img.x0 as i64 + i as i64;
            if x < 0 || x >= width as i64 {
                continue;
            }
            let s = img.px[j * img.w + i];
            if s[3] == 0.0 {
                continue;
            }
            let d = &mut buf[y as usize * width + x as usize];
            for k in 0..4 {
                d[k] = s[k] + d[k] * (1.0 - s[3]);
            }
        }
    }
}

fn premultiply([r, g, b, a]: [u8; 4]) -> [f32; 4] {
    let a = a as f32 / 255.0;
    [r as f32 / 255.0 * a, g as f32 / 255.0 * a, b as f32 / 255.0 * a, a]
}

/// A premultiplied f32 pixel as packed nativeRaster RGBA.
pub fn unpremultiply(r: f32, g: f32, b: f32, a: f32) -> u32 {
    if a <= 0.0 {
        return 0;
    }
    // `(v * 255).round().clamp(0, 255)` without libm's `roundf()` (a call
    // on the baseline x86-64 target): for t >= 0, round half away from zero
    // is floor(t + 0.5), exact in f64; negative and NaN t cast to 0.
    let byte = |v: f32| (((v * 255.0) as f64 + 0.5) as u32).min(255);
    if a == 1.0 {
        // Opaque pixels, most of a page: r / 1 is r.
        return byte(r) | byte(g) << 8 | byte(b) << 16 | 255 << 24;
    }
    byte(r / a) | byte(g / a) << 8 | byte(b / a) << 16 | byte(a) << 24
}

// geom_raster() ---------------------------------------------------------

/// `resolution(x, zero = FALSE)` (ggplot2 R/utilities-resolution.R) of the
/// finite doubles `x[rows]` (all of `x` without `rows`): see `Spread`.
pub fn resolution(x: &[f64], rows: Option<&[usize]>) -> f64 {
    let n = rows.map_or(x.len(), |r| r.len());
    let get = |k: usize| rows.map_or(x[k], |r| x[r[k]]);
    let chunk = n.div_ceil(default_threads()).max(1 << 16);
    let parts = par_map((0..n).step_by(chunk), |a| {
        let mut s = Spread::default();
        for k in a..(a + chunk).min(n) {
            s.add(get(k));
        }
        s
    });
    Spread::merge(parts).resolution()
}

/// What `resolution()` needs of a column, gathered in chunks and merged:
/// the range and the distinct values (-0 as 0, as `vctrs::vec_unique()`
/// finds them).
struct Spread {
    lo: f64,
    hi: f64,
    seen: BitsSet,
    last: u64,
}

impl Default for Spread {
    fn default() -> Self {
        Spread { lo: f64::INFINITY, hi: f64::NEG_INFINITY, seen: BitsSet::default(), last: u64::MAX }
    }
}

impl Spread {
    fn add(&mut self, v: f64) {
        self.lo = self.lo.min(v);
        self.hi = self.hi.max(v);
        let bits = if v == 0.0 { 0 } else { v.to_bits() };
        // Rasters repeat values in runs (a row's y); skip the set for them.
        if bits != self.last {
            self.seen.insert(bits);
            self.last = bits;
        }
    }

    fn merge(parts: Vec<Spread>) -> Spread {
        let mut out = Spread::default();
        for p in parts {
            out.lo = out.lo.min(p.lo);
            out.hi = out.hi.max(p.hi);
            if out.seen.len() < p.seen.len() {
                let small = std::mem::replace(&mut out.seen, p.seen);
                out.seen.extend(small);
            } else {
                out.seen.extend(p.seen);
            }
        }
        out
    }

    /// 1 for no values or a zero range (`scales::zero_range()` of
    /// `range(x)`), otherwise the smallest gap above
    /// `sqrt(.Machine$double.eps)` between distinct sorted values (1 if
    /// there is none).
    fn resolution(&self) -> f64 {
        if self.seen.is_empty() || zero_range(self.lo, self.hi) {
            return 1.0;
        }
        let mut u: Vec<f64> = self.seen.iter().map(|&b| f64::from_bits(b)).collect();
        u.sort_unstable_by(|a, b| a.partial_cmp(b).unwrap());
        let tol = f64::EPSILON.sqrt();
        let min = u.windows(2).map(|w| w[1] - w[0]).filter(|&d| d > tol).fold(f64::INFINITY, f64::min);
        if min.is_finite() { min } else { 1.0 }
    }
}

/// `scales::zero_range(c(lo, hi))` (scales R/bounds.R) for finite values.
fn zero_range(lo: f64, hi: f64) -> bool {
    if lo == hi {
        return true;
    }
    let m = lo.abs().min(hi.abs());
    m != 0.0 && ((lo - hi) / m).abs() < 1000.0 * f64::EPSILON
}

/// A hasher for f64 bits: multiplicative, spread.
#[derive(Default)]
pub struct BitsHash(u64);

impl std::hash::Hasher for BitsHash {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(5) ^ b as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
    }
    fn write_u64(&mut self, v: u64) {
        let h = (v ^ (v >> 29)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        self.0 = h ^ (h >> 32);
    }
}

type BitsSet = std::collections::HashSet<u64, std::hash::BuildHasherDefault<BitsHash>>;

/// The colour matrix of `GeomRaster$draw_panel()` (ggplot2
/// R/geom-raster.R) as `rasterGrob()` hands it to the device: `w` columns
/// by `h` rows, the top row first, packed as nativeRaster ints
/// (`R | G << 8 | B << 16 | A << 24`). Absent cells are 0 (`NA`, which
/// R's `RGBpar3()` reads as transparent white; premultiplied it is 0).
pub struct CellImage {
    pub w: usize,
    pub h: usize,
    pub px: Vec<u32>,
}

/// Buffers of finished `CellImage`s and of their cell indices, kept
/// between calls: as for the band buffers, fresh multi-megabyte buffers
/// cost more in page faults than filling them. At most `KEPT` are kept.
static CELL_POOL: Mutex<Vec<Vec<u32>>> = Mutex::new(Vec::new());
const KEPT: usize = 4;

/// A buffer of `len` zeros, from the pool if it has one; zeroed in
/// parallel.
fn pooled_zeros(len: usize) -> Vec<u32> {
    let mut v = {
        let mut pool = CELL_POOL.lock().unwrap_or_else(|e| e.into_inner());
        match pool.iter().position(|b| b.capacity() >= len) {
            Some(k) => pool.swap_remove(k),
            None => Vec::new(),
        }
    };
    if v.len() > len {
        v.truncate(len);
    } else {
        v.resize(len, 0);
    }
    par_map(v.chunks_mut(len.div_ceil(default_threads()).max(1 << 16)), |c| c.fill(0));
    v
}

fn give_back(v: Vec<u32>) {
    if v.capacity() == 0 {
        return;
    }
    let mut pool = CELL_POOL.lock().unwrap_or_else(|e| e.into_inner());
    if pool.len() >= KEPT {
        // Keep the larger buffers.
        let (k, _) = pool.iter().enumerate().min_by_key(|(_, b)| b.capacity()).unwrap();
        if pool[k].capacity() >= v.capacity() {
            return;
        }
        pool.swap_remove(k);
    }
    pool.push(v);
}

impl Drop for CellImage {
    fn drop(&mut self) {
        give_back(std::mem::take(&mut self.px));
    }
}

/// Cells above this many decline: ggplot2 would allocate a character
/// matrix of them.
const MAX_CELLS: usize = 1 << 27;

impl CellImage {
    /// Mirrors `draw_panel()`'s matrix for the rows `rows` (all without):
    /// `x_pos <- as.integer((x - min(x)) / resolution(x, FALSE))`, the same
    /// for y, then `raster[cbind(nrow - y_pos, x_pos + 1)] <- colour`, so a
    /// later row wins a shared cell. `colour` is each row's packed colour
    /// with alpha 0 or 255 (other alphas are not mirrored). `unit` marks x
    /// or y as integer columns, whose resolution() is 1. `None` for
    /// non-finite positions, other alphas or a matrix over `MAX_CELLS`.
    pub fn from_cells(x: &[f64], y: &[f64], colour: &[u32], rows: Option<&[usize]>, unit: [bool; 2]) -> Option<CellImage> {
        let n = rows.map_or(x.len(), |r| r.len());
        if n == 0 || y.len() != x.len() || colour.len() != x.len() {
            return None;
        }
        let row = |k: usize| rows.map_or(k, |r| r[k]);
        let chunk = n.div_ceil(default_threads()).max(1 << 15);
        // One pass for both columns' ranges and distinct values.
        let parts: Vec<Option<(Spread, Spread)>> = par_map((0..n).step_by(chunk), |a| {
            let (mut sx, mut sy) = (Spread::default(), Spread::default());
            for k in a..(a + chunk).min(n) {
                let i = row(k);
                if !x[i].is_finite() || !y[i].is_finite() || !matches!(colour[i] >> 24, 0 | 255) {
                    return None;
                }
                sx.add(x[i]);
                sy.add(y[i]);
            }
            Some((sx, sy))
        });
        let (px, py): (Vec<Spread>, Vec<Spread>) = parts.into_iter().collect::<Option<Vec<_>>>()?.into_iter().unzip();
        let (sx, sy) = (Spread::merge(px), Spread::merge(py));
        let rx = if unit[0] { 1.0 } else { sx.resolution() };
        let ry = if unit[1] { 1.0 } else { sy.resolution() };
        // as.integer() truncates; positions are >= 0 here, and the largest
        // is the largest value's (the mapping is monotone).
        let pos = |v: f64, min: f64, res: f64| ((v - min) / res).trunc();
        let (wf, hf) = (pos(sx.hi, sx.lo, rx) + 1.0, pos(sy.hi, sy.lo, ry) + 1.0);
        if !(wf * hf <= MAX_CELLS as f64) {
            return None;
        }
        let (w, h) = (wf as usize, hf as usize);
        // Each row's cell, then the rows written in order.
        let mut cell = pooled_zeros(n);
        par_map(cell.chunks_mut(chunk).enumerate(), |(c, dst)| {
            for (k, d) in dst.iter_mut().enumerate() {
                let i = row(c * chunk + k);
                let (cx, cy) = (pos(x[i], sx.lo, rx) as usize, pos(y[i], sy.lo, ry) as usize);
                *d = ((h - 1 - cy) * w + cx) as u32;
            }
        });
        let mut px = pooled_zeros(w * h);
        for (k, &d) in cell.iter().enumerate() {
            let c = colour[row(k)];
            px[d as usize] = if c >> 24 == 0 { 0 } else { c };
        }
        give_back(cell);
        Some(CellImage { w, h, px })
    }
}

/// `agg::trans_affine` (agg_trans_affine.h/.cpp): `x' = x * sx + y * shx +
/// tx`, `y' = x * shy + y * sy + ty`.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Affine {
    sx: f64,
    shy: f64,
    shx: f64,
    sy: f64,
    tx: f64,
    ty: f64,
}

impl Affine {
    fn new(sx: f64, shy: f64, shx: f64, sy: f64, tx: f64, ty: f64) -> Self {
        Affine { sx, shy, shx, sy, tx, ty }
    }

    fn translation(x: f64, y: f64) -> Self {
        Self::new(1.0, 0.0, 0.0, 1.0, x, y)
    }

    /// `trans_affine::multiply()`: `self` then `m`.
    fn then(self, m: Affine) -> Self {
        let t0 = self.sx * m.sx + self.shy * m.shx;
        let t2 = self.shx * m.sx + self.sy * m.shx;
        let t4 = self.tx * m.sx + self.ty * m.shx + m.tx;
        Affine {
            shy: self.sx * m.shy + self.shy * m.sy,
            sy: self.shx * m.shy + self.sy * m.sy,
            ty: self.tx * m.shy + self.ty * m.sy + m.ty,
            sx: t0,
            shx: t2,
            tx: t4,
        }
    }

    /// `trans_affine::invert()`.
    fn invert(self) -> Self {
        let d = 1.0 / (self.sx * self.sy - self.shy * self.shx);
        let t0 = self.sy * d;
        let sy = self.sx * d;
        let shy = -self.shy * d;
        let shx = -self.shx * d;
        let t4 = -self.tx * t0 - self.ty * shx;
        let ty = -self.tx * shy - self.ty * sy;
        Affine { sx: t0, shy, shx, sy, tx: t4, ty }
    }

    fn apply(&self, x: f64, y: f64) -> (f64, f64) {
        (x * self.sx + y * self.shx + self.tx, x * self.shy + y * self.sy + self.ty)
    }
}

/// `agg::dda2_line_interpolator`, forward-adjusted (agg_dda_line.h).
struct Dda2 {
    cnt: i32,
    lft: i32,
    rem: i32,
    m: i32,
    y: i32,
}

impl Dda2 {
    fn new(y1: i32, y2: i32, count: i32) -> Self {
        let cnt = if count <= 0 { 1 } else { count };
        let (mut lft, mut rem) = ((y2 - y1) / cnt, (y2 - y1) % cnt);
        let mut m = rem;
        if m <= 0 {
            m += count;
            rem += count;
            lft -= 1;
        }
        m -= count;
        Dda2 { cnt, lft, rem, m, y: y1 }
    }

    fn step(&mut self) {
        self.m += self.rem;
        self.y += self.lft;
        if self.m > 0 {
            self.m -= self.cnt;
            self.y += 1;
        }
    }
}

/// `agg::iround()`.
fn iround(v: f64) -> i64 {
    (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i64
}

/// An image drawn as ragg's `drawRaster()` draws it with `interpolate =
/// FALSE` and no rotation (ragg 1.5.2 src/AggDevice.h, `render_raster()`
/// in src/rendering.h), given the arguments R's `GERaster()` passes
/// (R src/main/engine.c; grid's `L_raster()` in
/// src/library/grid/src/grid.c): the bottom-left corner (`x`, `y`) and the
/// size in device pixels, `height` negative as grid gives it on a device
/// whose y runs down.
///
/// The image's rectangle, mapped by the image matrix, is rasterised with
/// AGG's exact-area coverage and clipped to the fractional clip box; each
/// row's covered pixels form one span (`scanline_u8` merges the edge cells
/// with the run between them) that `span_image_filter_rgba_nn` fills: the
/// span's start and end pixel centres mapped back into the image in
/// 1/256ths, interpolated across it by `dda2_line_interpolator`, and the
/// image pixel under each sample (edges cloned).
pub struct RasterDraw {
    pub image: std::sync::Arc<CellImage>,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl RasterDraw {
    /// The image-to-device matrix and its inverse, as `drawRaster()` builds
    /// them: reflect, shift down by the height, scale, rotate (by -0
    /// degrees), translate.
    fn matrices(&self) -> (Affine, Affine) {
        let (w, h) = (self.image.w as f64, self.image.h as f64);
        let rot = -0.0f64 * std::f64::consts::PI / 180.0;
        let src = Affine::new(1.0, 0.0, 0.0, -1.0, 0.0, 0.0)
            .then(Affine::translation(0.0, h))
            .then(Affine::new(self.width / w, 0.0, 0.0, self.height / h, 0.0, 0.0))
            .then(Affine::new(rot.cos(), rot.sin(), -rot.sin(), rot.cos(), 0.0, 0.0))
            .then(Affine::translation(self.x, self.y));
        (src, src.invert())
    }

    /// The device rectangle in AGG's 1/256 pixel units (x0, y0, x1, y1):
    /// the image's corners through the matrix, as the rasteriser upscales
    /// them. `None` for a size GERaster() skips or a non-finite one.
    fn subpixel_rect(&self) -> Option<[i64; 4]> {
        if self.width == 0.0 || self.height == 0.0 || self.image.w == 0 || self.image.h == 0 {
            return None;
        }
        let (src, _) = self.matrices();
        let (w, h) = (self.image.w as f64, self.image.h as f64);
        let mut r = [i64::MAX, i64::MAX, i64::MIN, i64::MIN];
        for (u, v) in [(0.0, 0.0), (0.0, h), (w, h), (w, 0.0)] {
            let (x, y) = src.apply(u, v);
            if !x.is_finite() || !y.is_finite() {
                return None;
            }
            let (x, y) = (iround(x * 256.0), iround(y * 256.0));
            r = [r[0].min(x), r[1].min(y), r[2].max(x), r[3].max(y)];
        }
        Some(r)
    }

    /// Pixel rows `[top, bottom)` the image can touch.
    pub fn rows(&self) -> (i64, i64) {
        match self.subpixel_rect() {
            Some(r) => (r[1] >> 8, (r[3] + 255) >> 8),
            None => (0, 0),
        }
    }

    /// Draws the image's pixels in a band's rows (`top`, `width` wide),
    /// clipped to `clip` (the current clip box in page pixels).
    fn draw(&self, buf: &mut [[f32; 4]], top: usize, width: usize, clip: &Rect) {
        let Some(r) = self.subpixel_rect() else { return };
        let up = |v: f64| iround(v * 256.0);
        let (fx0, fy0) = (r[0].max(up(clip.x0)), r[1].max(up(clip.y0)));
        let (fx1, fy1) = (r[2].min(up(clip.x1)), r[3].min(up(clip.y1)));
        if fx0 >= fx1 || fy0 >= fy1 {
            return;
        }
        let h = buf.len() / width;
        let overlap = |i: i64, lo: i64, hi: i64| (hi.min((i + 1) * 256) - lo.max(i * 256)).clamp(0, 256);
        let (i0, i1) = ((fx0 >> 8).max(0), ((fx1 + 255) >> 8).min(width as i64));
        let (j0, j1) = ((fy0 >> 8).max(top as i64), ((fy1 + 255) >> 8).min((top + h) as i64));
        if i0 >= i1 || j0 >= j1 {
            return;
        }
        let ox: Vec<i64> = (i0..i1).map(|i| overlap(i, fx0, fx1)).collect();
        let (_, inv) = self.matrices();
        let img = &*self.image;
        let (iw, ih) = (img.w as i64, img.h as i64);
        let unit: [f32; 256] = std::array::from_fn(|k| k as f32 / 255.0);
        for j in j0..j1 {
            let oy = overlap(j, fy0, fy1);
            // AGG's cell coverage: the area share, at most 255.
            let cover = |i: i64| ((ox[(i - i0) as usize] * oy) >> 8).min(255);
            let Some(s) = (i0..i1).find(|&i| cover(i) > 0) else { continue };
            let e = (s..i1).rev().find(|&i| cover(i) > 0).unwrap() + 1;
            let len = (e - s) as i32;
            let (xa, ya) = inv.apply(s as f64 + 0.5, j as f64 + 0.5);
            let (xb, yb) = inv.apply(s as f64 + 0.5 + len as f64, j as f64 + 0.5);
            let mut dx = Dda2::new(iround(xa * 256.0) as i32, iround(xb * 256.0) as i32, len);
            let mut dy = Dda2::new(iround(ya * 256.0) as i32, iround(yb * 256.0) as i32, len);
            let row = &mut buf[(j as usize - top) * width..][..width];
            for i in s..e {
                let (u, v) = ((dx.y >> 8) as i64, (dy.y >> 8) as i64);
                dx.step();
                dy.step();
                let c = cover(i);
                let p = img.px[(v.clamp(0, ih - 1) * iw + u.clamp(0, iw - 1)) as usize];
                if p >> 24 == 0 || c == 0 {
                    continue;
                }
                let sp = [unit[(p & 255) as usize], unit[(p >> 8 & 255) as usize], unit[(p >> 16 & 255) as usize], 1.0];
                let d = &mut row[i as usize];
                if c == 255 {
                    *d = sp;
                } else {
                    let a = unit[c as usize];
                    for k in 0..4 {
                        d[k] = sp[k] * a + d[k] * (1.0 - a);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::points::{Point, PointBatch};

    fn opts(threads: usize, band_rows: usize) -> Options {
        Options { threads, band_rows }
    }

    fn square(x: f64, y: f64, rgba: [u8; 4]) -> Point {
        Point { x, y, shape: 15, size: 16.0 / (2.0 * 0.375), lwd: 1.0, col: rgba, fill: [0; 4] }
    }

    #[test]
    fn clear_fills_every_pixel_exactly() {
        let mut list = DisplayList::new();
        list.push(Item::PushClip(Rect { x0: 2.0, y0: 2.0, x1: 3.0, y1: 3.0 }));
        list.push(Item::Clear([10, 20, 30, 255]));
        let img = render(&list, 7, 5, &opts(2, 2));
        assert!(img.iter().all(|&p| p == 0xFF_1E_14_0A));
    }

    #[test]
    fn bands_and_threads_do_not_change_pixels() {
        let mut list = DisplayList::new();
        list.push(Item::Clear([255, 255, 255, 255]));
        let pts: Vec<Point> = (0..500)
            .map(|i| square((i * 37 % 200) as f64 + 0.3, (i * 53 % 150) as f64 + 0.6, [(i % 255) as u8, 40, 200, 90]))
            .collect();
        list.push(Item::Points(PointBatch::new(&pts, 0)));
        let reference = render(&list, 200, 150, &opts(1, 1000));
        for (threads, band) in [(1, 1), (3, 7), (8, 64), (16, 5)] {
            assert_eq!(render(&list, 200, 150, &opts(threads, band)), reference);
        }
        let mut streamed = Vec::new();
        let mut tops = Vec::new();
        execute(&list, 200, 150, &opts(4, 16), |top, px| {
            tops.push(top);
            streamed.extend_from_slice(px);
        });
        assert_eq!(streamed, reference);
        assert_eq!(tops, (0..150).step_by(16).collect::<Vec<_>>());
    }

    #[test]
    fn clip_cuts_at_fractional_edges() {
        // A 16 px opaque square centred at (10, 10) covers [2, 18).
        let mut list = DisplayList::new();
        list.push(Item::PushClip(Rect { x0: 5.25, y0: 0.0, x1: 12.5, y1: 20.0 }));
        list.push(Item::Points(PointBatch::new(&[square(10.0, 10.0, [0, 0, 0, 255])], 0)));
        list.push(Item::PopClip);
        list.push(Item::Points(PointBatch::new(&[square(10.0, 30.0, [0, 0, 0, 255])], 0)));
        let img = render(&list, 20, 40, &opts(2, 8));
        let a = |x: usize, y: usize| img[y * 20 + x] >> 24;
        assert_eq!(a(4, 10), 0);
        assert_eq!(a(5, 10), 192); // 0.75 of the pixel is inside (AGG: 0.75 * 256)
        assert_eq!(a(6, 10), 255);
        assert_eq!(a(12, 10), 128); // 0.5
        assert_eq!(a(13, 10), 0);
        // After PopClip, the page clip again.
        assert_eq!(a(3, 30), 255);
        assert_eq!(a(16, 30), 255);
    }

    #[test]
    fn background_plus_points_matches_the_hybrid_composite() {
        // The hybrid renders points on a transparent panel raster that
        // ragg then blends over the white page; the full tier draws both in
        // one list. They agree to rounding: the hybrid's raster is
        // quantised to 8 bits (non-premultiplied, so low alphas lose colour
        // precision) before it is composited.
        let mut seed = 7u64;
        let mut rnd = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 11) as f64 / (1u64 << 53) as f64
        };
        let shapes = [16, 17, 15, 3, 19, 1];
        let pts: Vec<Point> = (0..20_000)
            .map(|_| Point {
                x: rnd() * 300.0,
                y: rnd() * 200.0,
                shape: shapes[(rnd() * 6.0) as usize],
                size: [4.0, 5.5, 7.0][(rnd() * 3.0) as usize],
                lwd: 1.4,
                col: [(rnd() * 255.0) as u8, (rnd() * 255.0) as u8, 50, 76],
                fill: [0; 4],
            })
            .collect();
        let hybrid = crate::render::points::render(300, 200, &pts);
        let mut list = DisplayList::new();
        list.push(Item::Clear([255, 255, 255, 255]));
        list.push(Item::Points(PointBatch::new(&pts, 0)));
        let page = render(&list, 300, 200, &opts(8, 16));
        for (&h, &p) in hybrid.iter().zip(&page) {
            let a = (h >> 24) as f64 / 255.0;
            for c in 0..3 {
                let src = ((h >> (8 * c)) & 255) as f64;
                let over = src * a + 255.0 * (1.0 - a);
                let got = ((p >> (8 * c)) & 255) as f64;
                assert!((over - got).abs() <= 2.0, "{over} vs {got}");
            }
            assert_eq!(p >> 24, 255);
        }
    }

    #[test]
    fn unpremultiply_rounds_as_roundf() {
        let reference = |r: f32, g: f32, b: f32, a: f32| {
            if a <= 0.0 {
                return 0;
            }
            let byte = |v: f32| (v * 255.0).round().clamp(0.0, 255.0) as u32;
            byte(r / a) | byte(g / a) << 8 | byte(b / a) << 16 | byte(a) << 24
        };
        let mut seed = 11u64;
        let mut rnd = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 40) as f32 / (1u64 << 24) as f32
        };
        // Exact halves, the values either side of them, and random pixels.
        let mut vals: Vec<f32> = (0..=510).map(|k| k as f32 / 510.0).collect();
        vals.extend((0..=255).flat_map(|k| {
            let h = (k as f32 + 0.5) / 255.0;
            [h, f32::from_bits(h.to_bits() - 1), f32::from_bits(h.to_bits() + 1)]
        }));
        vals.extend([-0.1, -0.002, 1.0, 1.0001, 1.5, f32::NAN]);
        for &v in &vals {
            for a in [1.0, 0.5, 0.3, 0.0, -1.0, f32::NAN] {
                assert_eq!(unpremultiply(v * a, v, v * 0.7, a), reference(v * a, v, v * 0.7, a), "{v} {a}");
            }
        }
        for _ in 0..100_000 {
            let a = rnd();
            let (r, g, b) = (rnd() * a, rnd() * a, rnd() * a);
            assert_eq!(unpremultiply(r, g, b, a), reference(r, g, b, a));
            assert_eq!(unpremultiply(r, g, b, 1.0), reference(r, g, b, 1.0));
        }
    }

    #[test]
    fn memory_is_bounded_by_bands() {
        // 20 x 20 in at 300 dpi.
        let (w, h) = (6000, 6000);
        let o = opts(8, 64);
        let bound = band_memory(w, &o);
        assert!(bound < 64 << 20, "{bound}");
        let mut list = DisplayList::new();
        list.push(Item::Clear([255, 255, 255, 255]));
        list.push(Item::Points(PointBatch::new(&(0..1000).map(|i| square((i * 6) as f64, (i * 6) as f64, [0, 0, 0, 255])).collect::<Vec<_>>(), 0)));
        let mut rows = 0;
        execute(&list, w, h, &o, |_, px| {
            rows += px.len() / w;
        });
        assert_eq!(rows, h);
        // Other tests share the pool in parallel with narrower pages; count
        // only this page's band buffers.
        let held: usize = POOL.lock().unwrap().iter().filter(|b| b.capacity() >= w * 64).map(|b| b.capacity() * 16).sum();
        assert!(held <= bound, "{held} > {bound}");
    }

    #[test]
    fn resolution_is_the_smallest_gap_as_ggplot2_finds_it() {
        assert_eq!(resolution(&[3.0, 1.0, 2.0, 2.0], None), 1.0);
        assert_eq!(resolution(&[0.0, 1.5, 0.5], None), 0.5);
        // zero_range(): one value, equal values, or a tiny relative range.
        assert_eq!(resolution(&[4.0], None), 1.0);
        assert_eq!(resolution(&[4.0, 4.0], None), 1.0);
        assert_eq!(resolution(&[1e6, 1e6 + 1e-10], None), 1.0);
        // Gaps under sqrt(eps) don't count; with no other gap it's 1.
        assert_eq!(resolution(&[1.0, 1.0 + 1e-10, 3.0], None), 2.0 - 1e-10);
        assert_eq!(resolution(&[1e-9, 2e-9], None), 1.0);
        // -0 and 0 are one value; `rows` picks the values.
        assert_eq!(resolution(&[-0.0, 0.0, 0.25], None), 0.25);
        assert_eq!(resolution(&[0.0, 0.1, 5.0, 7.0], Some(&[2, 3, 0])), 2.0);
        // Chunks merge: more values than one chunk.
        let v: Vec<f64> = (0..300_000).map(|i| (i % 1000) as f64 * 0.75 + (i / 1000) as f64 * 1e-3).collect();
        let mut u = v.clone();
        u.sort_by(|a, b| a.partial_cmp(b).unwrap());
        u.dedup();
        let min = u.windows(2).map(|w| w[1] - w[0]).filter(|&d| d > f64::EPSILON.sqrt()).fold(f64::INFINITY, f64::min);
        assert_eq!(resolution(&v, None), min);
    }

    const RED: u32 = 0xFF00_00FF;
    const BLUE: u32 = 0xFFFF_0000;

    #[test]
    fn cell_images_put_the_top_row_first_and_the_last_row_wins() {
        // A 3 x 2 grid with one cell absent and one written twice.
        let x = [0.0, 2.0, 4.0, 0.0, 4.0, 4.0];
        let y = [10.0, 10.0, 10.0, 11.0, 11.0, 11.0];
        let col = [RED, BLUE, RED, BLUE, RED, 0x00FF_FFFF];
        let img = CellImage::from_cells(&x, &y, &col, None, [false, false]).unwrap();
        assert_eq!((img.w, img.h), (3, 2));
        // Top row is y = 11: (0, 11) blue, (2, 11) absent, (4, 11) written
        // red then transparent.
        assert_eq!(img.px, vec![BLUE, 0, 0, RED, BLUE, RED]);
        // Rows of one panel only, and integer columns' resolution of 1.
        let img = CellImage::from_cells(&x, &y, &col, Some(&[0, 2]), [false, false]).unwrap();
        assert_eq!((img.w, img.h, img.px.clone()), (2, 1, vec![RED, RED]));
        let img = CellImage::from_cells(&x, &y, &col, Some(&[0, 2]), [true, false]).unwrap();
        assert_eq!((img.w, img.px.clone()), (5, vec![RED, 0, 0, 0, RED]));
        // as.integer() truncates uneven positions.
        let img = CellImage::from_cells(&[0.0, 1.0, 2.9], &[0.0; 3], &[RED, BLUE, RED], None, [false, false]).unwrap();
        assert_eq!(img.px, vec![RED, BLUE, RED]);
        // Partial alpha and non-finite positions decline.
        assert!(CellImage::from_cells(&[0.0], &[0.0], &[0x8000_00FF], None, [false, false]).is_none());
        assert!(CellImage::from_cells(&[f64::INFINITY], &[0.0], &[RED], None, [false, false]).is_none());
    }

    #[test]
    fn dda2_spreads_the_remainder_as_agg_does() {
        let walk = |a: i32, b: i32, n: i32| {
            let mut d = Dda2::new(a, b, n);
            (0..n).map(|_| {
                let y = d.y;
                d.step();
                y
            }).collect::<Vec<_>>()
        };
        assert_eq!(walk(0, 1000, 10), (0..10).map(|k| k * 100).collect::<Vec<_>>());
        assert_eq!(walk(0, 10, 4), vec![0, 2, 5, 7]);
        assert_eq!(walk(10, 0, 4), vec![10, 7, 5, 2]);
    }

    fn draw_one(img: CellImage, x: f64, y: f64, w: f64, h: f64, clip: Rect, size: usize) -> Vec<u32> {
        let mut list = DisplayList::new();
        list.push(Item::Clear([255, 255, 255, 255]));
        list.push(Item::PushClip(clip));
        list.push(Item::Raster(RasterDraw { image: std::sync::Arc::new(img), x, y, width: w, height: h }));
        render(&list, size, size, &opts(2, 3))
    }

    fn page(size: usize) -> Rect {
        Rect { x0: 0.0, y0: 0.0, x1: size as f64, y1: size as f64 }
    }

    #[test]
    fn rasters_map_their_rows_top_down_and_sample_nearest() {
        const W: u32 = 0xFFFF_FFFF;
        // 2 x 2: top row red, blue; bottom blue, red; drawn 1:1 at (1, 1)
        // (bottom-left (1, 3)), then stretched to 4 x 4 pixels.
        let img = || CellImage { w: 2, h: 2, px: vec![RED, BLUE, BLUE, RED] };
        let out = draw_one(img(), 1.0, 3.0, 2.0, -2.0, page(4), 4);
        assert_eq!(&out[4..8], &[W, RED, BLUE, W]);
        assert_eq!(&out[8..12], &[W, BLUE, RED, W]);
        let out = draw_one(img(), 0.0, 4.0, 4.0, -4.0, page(4), 4);
        assert_eq!(&out[0..4], &[RED, RED, BLUE, BLUE]);
        assert_eq!(&out[12..16], &[BLUE, BLUE, RED, RED]);
        // Transparent cells leave the page as it was.
        let out = draw_one(CellImage { w: 2, h: 1, px: vec![0, RED] }, 0.0, 1.0, 2.0, -1.0, page(2), 2);
        assert_eq!(&out[0..2], &[W, RED]);
    }

    #[test]
    fn raster_edges_have_partial_coverage_and_clip_cuts_them() {
        let img = || CellImage { w: 1, h: 1, px: vec![RED] };
        // Left edge at 0.5: half coverage there.
        let out = draw_one(img(), 0.5, 2.0, 1.5, -2.0, page(2), 2);
        let ch = |p: u32, k: u32| (p >> (8 * k)) & 255;
        assert_eq!((ch(out[0], 0), ch(out[0], 1)), (255, 127));
        assert_eq!(out[1], RED);
        // A clip at x = 1 removes the right pixel; at 0.75 halves the
        // left pixel's share again.
        let out = draw_one(img(), 0.5, 2.0, 1.5, -2.0, Rect { x0: 0.75, y0: 0.0, x1: 1.0, y1: 2.0 }, 2);
        assert_eq!(out[1], 0xFFFF_FFFF);
        assert_eq!(ch(out[0], 1), 191);
        // Zero size draws nothing; rows() covers the pixels touched.
        let out = draw_one(img(), 0.5, 2.0, 0.0, -2.0, page(2), 2);
        assert!(out.iter().all(|&p| p == 0xFFFF_FFFF));
        let r = RasterDraw { image: std::sync::Arc::new(img()), x: 0.0, y: 5.5, width: 3.0, height: -2.25 };
        assert_eq!(r.rows(), (3, 6));
    }
}
