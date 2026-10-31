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
}
