//! Glue for the Phase 2 point renderer (`alot_core::render::points`).

use crate::convert::{self, Column, ColumnData};
use alot_core::colour::hex;
use alot_core::colour::parse::{parse_colour, Colour};
use alot_core::render::points::{self, Point};
use alot_core::render::agg::{Cap, Join, Rule};
use alot_core::render::paths::{PathBatch, PathSpec, Stroke};
use alot_core::render::png::{Encoder, PngOptions};
use alot_core::render::display::{DisplayList, Item, Rect};
use alot_core::render::rects::{RectBatch, RectSpec, RectStyle};
use alot_core::render::raster;
use extendr_api::prelude::*;
use std::collections::HashMap;

#[allow(improper_ctypes)] // SEXP is opaque, as in extendr-ffi.
extern "C" {
    // R API (Rinternals.h).
    static R_NaString: extendr_api::SEXP;
    fn STRING_PTR_RO(x: extendr_api::SEXP) -> *const extendr_api::SEXP;
}

/// A double or integer column recycled to any length: `None` for other
/// types, lengths other than 1 or `n`, or any NA.
fn recycled(x: &Robj, n: usize) -> Option<Vec<f64>> {
    let v: Vec<f64> = match Column::new(x).data {
        ColumnData::Double(v) => v.to_vec(),
        ColumnData::Integer(v) => v.iter().map(|v| v.map_or(f64::NAN, f64::from)).collect(),
        _ => return None,
    };
    let ok = (v.len() == 1 || v.len() == n) && !v.iter().any(|v| v.is_nan());
    ok.then_some(v)
}

fn at(v: &[f64], i: usize) -> f64 {
    if v.len() == 1 { v[0] } else { v[i] }
}

/// Colours of a layer as `scales::alpha(colour, alpha)` would give them,
/// packed as nativeRaster ints (`R | G << 8 | B << 16 | A << 24`), equal to
/// `col2rgb(alpha(colour, alpha), alpha = TRUE)`. Colour strings are
/// decoded as farver does (`alot_core::colour::parse`: hex, R's colour
/// names, "transparent"). `alpha` is double (length 1 or `n`) or all-NA
/// logical (keep the colour's alpha); an NA among doubles also keeps it. An
/// NA colour (or "NA") stays NA in `alpha()`, which `col2rgb()` reads as
/// transparent white. `NULL` (decline) if a colour is a numeric palette
/// index or something farver rejects, or for other `alpha` types.
/// @noRd
#[extendr(r_name = "rs_point_colours")]
fn point_colours(colour: Strings, alpha: Robj) -> Robj {
    let n = colour.len();
    const NO_ALPHA: [f64; 1] = [f64::NAN];
    let alpha_col = Column::new(&alpha);
    let alpha: &[f64] = match alpha_col.data {
        ColumnData::Double(v) if v.len() == 1 || v.len() == n => v,
        ColumnData::Logical(v) if (v.len() == 1 || v.len() == n) && v.iter().all(|v| v.is_none()) => &NO_ALPHA,
        _ => return Robj::from(()),
    };
    // R caches CHARSXPs, so each distinct pointer is parsed once: the
    // distinct ones are found in parallel, parsed here (reading R's
    // strings), and the rows mapped in parallel. Pointers travel as usize.
    let ptrs = convert::str_ptrs(&colour);
    let ptrs: &[usize] = unsafe { std::slice::from_raw_parts(ptrs.as_ptr() as *const usize, ptrs.len()) };
    let chunk = n.div_ceil(raster::default_threads()).max(1 << 15);
    let found: Vec<PtrMap<usize>> = raster::par_map((0..n).step_by(chunk), |a| {
        let mut seen = PtrMap::default();
        let mut last = None;
        for (i, &p) in ptrs[a..(a + chunk).min(n)].iter().enumerate() {
            if last != Some(p) {
                seen.entry(p).or_insert(a + i);
                last = Some(p);
            }
        }
        seen
    });
    let na = unsafe { R_NaString } as usize;
    // Each distinct colour's RGBA, None for NA.
    let mut parsed: PtrMap<Option<[u8; 4]>> = PtrMap::default();
    for (p, i) in found.into_iter().flatten() {
        if parsed.contains_key(&p) {
            continue;
        }
        let rgba = match if p == na { Some(Colour::Na) } else { parse_colour(colour.elt(i).as_bytes()) } {
            Some(Colour::Rgba(v)) => Some(v),
            Some(Colour::Na) => None,
            None => return Robj::from(()),
        };
        parsed.insert(p, rgba);
    }
    // col2rgb(NA): transparent white.
    const NA: i32 = 0x00FF_FFFF;
    let mut out = Integers::new(n);
    struct Dst(*mut i32);
    unsafe impl Sync for Dst {}
    let dst = Dst(out.as_mut_ptr() as *mut i32);
    let (dst, parsed) = (&dst, &parsed);
    raster::par_map((0..n).step_by(chunk), |a| {
        // Runs of one colour skip the map.
        let mut last = (usize::MAX, None);
        for i in a..(a + chunk).min(n) {
            let p = ptrs[i];
            if p != last.0 {
                last = (p, parsed[&p]);
            }
            let v = match last.1 {
                Some([r, g, b, mut a]) => {
                    let al = at(alpha, i);
                    if !al.is_nan() {
                        a = hex::double2int(al * 255.0).clamp(0, 255) as u8;
                    }
                    (r as u32 | (g as u32) << 8 | (b as u32) << 16 | (a as u32) << 24) as i32
                }
                None => NA,
            };
            // SAFETY: chunks write disjoint rows of `out`, which has `n`.
            unsafe { dst.0.add(i).write(v) };
        }
    });
    out.into()
}

/// A hasher for pointers (CHARSXPs as usize): their bits, spread.
#[derive(Default)]
struct PtrHash(u64);

impl std::hash::Hasher for PtrHash {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(5) ^ b as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
    }
    fn write_usize(&mut self, p: usize) {
        self.0 = ((p as u64) >> 3).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
}

type PtrMap<V> = HashMap<usize, V, std::hash::BuildHasherDefault<PtrHash>>;

/// Whether every shape is one the renderer draws (double or integer
/// codes, no NA).
/// @noRd
#[extendr(r_name = "rs_point_shapes_supported")]
fn point_shapes_supported(shape: Robj) -> bool {
    // Scanned in place and in parallel: a 1e6-row layer's shapes are
    // checked in the IR.
    if let Some(v) = shape.as_integer_slice() {
        return par_all(v.len(), 0, |lo, hi| v[lo..hi].iter().all(|&s| s != i32::MIN && points::supported_shape(s)));
    }
    match shape.as_real_slice() {
        Some(v) => par_all(v.len(), 0, |lo, hi| v[lo..hi].iter().all(|&s| (s as i32) as f64 == s && points::supported_shape(s as i32))),
        None => false,
    }
}

/// Whether `f(lo, hi)` holds for every chunk of `0..n`, chunks checked on up
/// to `threads` threads (0: the default).
fn par_all(n: usize, threads: i32, f: impl Fn(usize, usize) -> bool + Sync) -> bool {
    let threads = if threads > 0 { threads as usize } else { raster::default_threads() };
    let chunk = n.div_ceil(threads).max(1 << 16);
    if n <= chunk {
        return f(0, n);
    }
    std::thread::scope(|s| {
        let f = &f;
        let handles: Vec<_> = (0..n.div_ceil(chunk)).map(|k| s.spawn(move || f(k * chunk, ((k + 1) * chunk).min(n)))).collect();
        handles.into_iter().all(|h| h.join().unwrap_or(false))
    })
}

/// Whether no column of `cols` (a list of atomic vectors) has an NA (or
/// NaN), scanned in parallel on up to `threads` threads (0: the default).
/// `FALSE` for any other column type. The per-row NA checks of a layer's
/// support (`Geom$handle_na()`'s fast path, `points_decline()`) use it.
/// @noRd
#[extendr(r_name = "rs_columns_complete")]
fn columns_complete(cols: List, threads: i32) -> bool {
    let na_str = unsafe { R_NaString } as usize;
    enum Col<'a> {
        Real(&'a [f64]),
        Int(&'a [i32]),
        Str(&'a [usize]),
    }
    let robjs: Vec<Robj> = cols.values().collect();
    let mut parts = Vec::new();
    for c in &robjs {
        if let Some(v) = c.as_real_slice() {
            parts.push(Col::Real(v));
        } else if let Some(v) = c.as_integer_slice() {
            parts.push(Col::Int(v));
        } else if let Some(v) = c.as_logical_slice() {
            parts.push(Col::Int(unsafe { std::slice::from_raw_parts(v.as_ptr() as *const i32, v.len()) }));
        } else if c.is_string() && c.len() == 0 {
            // A zero-length vector's data pointer isn't aligned; nothing to scan.
        } else if c.is_string() {
            // STRSXP elements are CHARSXP pointers; NA is R_NaString.
            let v = unsafe { std::slice::from_raw_parts(STRING_PTR_RO(c.get()) as *const usize, c.len()) };
            parts.push(Col::Str(v));
        } else {
            return false;
        }
    }
    let n = parts.iter().map(|c| match c { Col::Real(v) => v.len(), Col::Int(v) => v.len(), Col::Str(v) => v.len() }).max().unwrap_or(0);
    let ok = |c: &Col, lo: usize, hi: usize| match c {
        Col::Real(v) => v[lo.min(v.len())..hi.min(v.len())].iter().all(|x| !x.is_nan()),
        Col::Int(v) => v[lo.min(v.len())..hi.min(v.len())].iter().all(|&x| x != i32::MIN),
        Col::Str(v) => v[lo.min(v.len())..hi.min(v.len())].iter().all(|&x| x != na_str),
    };
    par_all(n, threads, |lo, hi| parts.iter().all(|c| ok(c, lo, hi)))
}


/// A group column as bit patterns: doubles and integers compare by value
/// (`-0` and `0` equal), `None` if it has an NA or is another type.
fn group_keys(group: &Robj) -> Option<Vec<u64>> {
    if let Some(v) = group.as_real_slice() {
        v.iter().map(|&x| (!x.is_nan()).then(|| if x == 0.0 { 0.0f64.to_bits() } else { x.to_bits() })).collect()
    } else if let Some(v) = group.as_integer_slice() {
        v.iter().map(|&x| (x != i32::MIN).then(|| (x as f64).to_bits())).collect()
    } else {
        None
    }
}

/// Whether every row of each column in `cols` equals the first row of its
/// group (`group`: integer or double, no NA), as
/// `vctrs::vec_equal(v, v[first[g]], na_equal = TRUE)` checks in
/// `paths_decline()`. Strings compare by CHARSXP, which R caches, so equal
/// strings in different encodings count as different (the layer then
/// declines, which is safe). `NULL` (decline to R's check) for other
/// types.
/// @noRd
#[extendr(r_name = "rs_constant_by_group")]
fn constant_by_group(group: Robj, cols: List) -> Robj {
    let Some(keys) = group_keys(&group) else { return Robj::from(()) };
    let n = keys.len();
    // The first row of each row's group.
    let mut first = vec![0u32; n];
    let mut seen: HashMap<u64, u32> = HashMap::new();
    let mut last: Option<(u64, u32)> = None;
    for (i, &k) in keys.iter().enumerate() {
        first[i] = match last {
            Some((lk, lf)) if lk == k => lf,
            _ => *seen.entry(k).or_insert(i as u32),
        };
        last = Some((k, first[i]));
    }
    let robjs: Vec<Robj> = cols.values().collect();
    for c in &robjs {
        let ok = if let Some(v) = c.as_real_slice() {
            v.len() == n && v.iter().zip(&first).all(|(&x, &f)| {
                let y = v[f as usize];
                x == y || (x.is_nan() && y.is_nan())
            })
        } else if let Some(v) = c.as_integer_slice() {
            v.len() == n && v.iter().zip(&first).all(|(&x, &f)| x == v[f as usize])
        } else if let Some(v) = c.as_logical_slice() {
            let v = unsafe { std::slice::from_raw_parts(v.as_ptr() as *const i32, v.len()) };
            v.len() == n && v.iter().zip(&first).all(|(&x, &f)| x == v[f as usize])
        } else if c.is_string() && c.len() == n && n > 0 {
            let v = unsafe { std::slice::from_raw_parts(STRING_PTR_RO(c.get()) as *const usize, n) };
            v.iter().zip(&first).all(|(&x, &f)| x == v[f as usize])
        } else {
            return Robj::from(());
        };
        if !ok {
            return Robj::from(false);
        }
    }
    Robj::from(true)
}

/// A path layer's drawing order and paths, as `panel_group_order()` and
/// `full_paths()` (R/render-full.R) compute them: the rows ordered by
/// panel then group (stable), those of groups with at least two rows
/// kept. Returns `order` (1-based rows), `first` (1-based first row of each
/// kept group) and `path` (0-based index into `first` of each kept row).
/// `NULL` (decline) for an NA group or panel.
/// @noRd
#[extendr(r_name = "rs_path_groups")]
fn path_groups(panel: &[i32], group: Robj) -> Robj {
    let Some(keys) = group_keys(&group) else { return Robj::from(()) };
    let n = keys.len();
    if panel.len() != n || panel.iter().any(|&p| p == i32::MIN) {
        return Robj::from(());
    }
    // Group values order numerically, not by bit pattern.
    let value = |i: usize| f64::from_bits(keys[i]);
    let cmp = |&a: &u32, &b: &u32| {
        let (a, b) = (a as usize, b as usize);
        panel[a].cmp(&panel[b]).then(value(a).partial_cmp(&value(b)).unwrap())
    };
    let mut order: Vec<u32> = (0..n as u32).collect();
    if !order.windows(2).all(|w| cmp(&w[0], &w[1]) != std::cmp::Ordering::Greater) {
        order.sort_by(cmp);
    }
    let (mut kept, mut first, mut path) = (Vec::with_capacity(n), Vec::new(), Vec::with_capacity(n));
    let mut k = 0;
    while k < n {
        let mut e = k + 1;
        while e < n && cmp(&order[k], &order[e]) == std::cmp::Ordering::Equal {
            e += 1;
        }
        if e - k >= 2 {
            first.push(order[k] as i32 + 1);
            kept.extend(order[k..e].iter().map(|&i| i as i32 + 1));
            path.extend(std::iter::repeat((first.len() - 1) as i32).take(e - k));
        }
        k = e;
    }
    list!(order = kept, first = first, path = path).into()
}

/// Whether `x` is a logical vector of NAs only (an NA colour column),
/// without allocating as `all(is.na(x))` does.
/// @noRd
#[extendr(r_name = "rs_all_na_logical")]
fn all_na_logical(x: Robj) -> bool {
    x.as_logical_slice().is_some_and(|v| v.iter().all(|l| l.is_na()))
}

/// Renders rows `rows` (1-based) of a point layer, one panel's, to a nativeRaster
/// of `dims` (width, height) pixels. `rect` is the panel's (left, top,
/// width, height) in canvas pixels, which also clips each point; positions are rescaled from
/// `x_range`/`y_range` to it, with infinite values squished to the edges
/// as `CoordCartesian$transform()` does. `size` and `stroke` follow
/// `gg_par()`: symbol size (size * pt + stroke * stroke_scale / 2) pt, line
/// width stroke * stroke_scale / 2 lwd, converted at `res` pixels per inch.
/// `colour` and `fill` come from `rs_point_colours()`. `threads` is the band
/// executor's worker count (0: available cores, capped at 8). `NULL`
/// (decline) for unsupported inputs.
/// @noRd
#[extendr(r_name = "rs_render_points")]
#[allow(clippy::too_many_arguments)]
fn render_points(
    x: &[f64],
    y: &[f64],
    rows: &[i32],
    x_range: &[f64],
    y_range: &[f64],
    rect: &[f64],
    dims: &[i32],
    shape: Robj,
    size: Robj,
    stroke: Robj,
    colour: &[i32],
    fill: &[i32],
    consts: &[f64],
    threads: i32,
) -> Robj {
    let n = x.len();
    let (Some(shape), Some(size), Some(stroke)) = (recycled(&shape, n), recycled(&size, n), recycled(&stroke, n)) else {
        return Robj::from(());
    };
    let [pt, stroke_scale, res] = consts else { return Robj::from(()) };
    let [left, top, pw, ph] = rect else { return Robj::from(()) };
    let &[w, h] = dims else { return Robj::from(()) };
    let rows_ok = rows.iter().all(|&r| r >= 1 && r as usize <= n);
    if y.len() != n || colour.len() != n || fill.len() != n || x_range.len() != 2 || y_range.len() != 2 || !rows_ok {
        return Robj::from(());
    }
    let npc = |v: f64, r: &[f64]| {
        if v == f64::INFINITY {
            1.0
        } else if v == f64::NEG_INFINITY {
            0.0
        } else {
            (v - r[0]) / (r[1] - r[0])
        }
    };
    let bytes = |c: i32| {
        let c = c as u32;
        [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8]
    };
    let (shape, size, stroke) = (&shape, &size, &stroke);
    let point = |k: usize| {
        let i = rows[k] as usize - 1;
        let st = at(stroke, i);
        Some(Point {
            x: left + npc(x[i], x_range) * pw,
            y: top + (1.0 - npc(y[i], y_range)) * ph,
            shape: at(shape, i) as i32,
            size: (at(size, i) * pt + st * stroke_scale / 2.0) * res / 72.0,
            lwd: st * stroke_scale / 2.0 * res / 96.0,
            col: bytes(colour[i]),
            fill: bytes(fill[i]),
        })
    };
    let (w, h) = (w as usize, h as usize);
    let mut out: Robj = Integers::new(w * h).into();
    let ints = out.as_integer_slice_mut().unwrap();
    // nativeRaster ints are the packed pixels bit for bit.
    let pixels = unsafe { std::slice::from_raw_parts_mut(ints.as_mut_ptr() as *mut u32, ints.len()) };
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    // Each point is clipped to the panel here, as ragg clips each mark, so
    // the raster is drawn unclipped.
    let clip = Rect { x0: *left, y0: *top, x1: left + pw, y1: top + ph };
    let batch = points::PointBatch::from_fn(rows.len(), opts.threads, point);
    points::render_batch(w, h, batch, &opts, Some(clip), pixels);
    let (w, h) = (w as i32, h as i32);
    out.set_attrib("dim", Integers::from_values([h, w])).unwrap();
    out.set_attrib("class", "nativeRaster").unwrap();
    out.set_attrib("channels", 4).unwrap();
    out
}

/// A nativeRaster of `w` x `h` pixels and its pixels as packed `u32`s.
pub(crate) fn native_raster(w: usize, h: usize) -> (Robj, *mut u32) {
    let mut out: Robj = Integers::new(w * h).into();
    let ints = out.as_integer_slice_mut().unwrap();
    let ptr = ints.as_mut_ptr() as *mut u32;
    out.set_attrib("dim", Integers::from_values([h as i32, w as i32])).unwrap();
    out.set_attrib("class", "nativeRaster").unwrap();
    out.set_attrib("channels", 4).unwrap();
    (out, ptr)
}

/// Renders rows `rows` (1-based) of a rect layer, one panel's, to a
/// nativeRaster of `dims` (width, height) pixels, as `GeomRect$draw_panel`'s
/// rectGrob draws them on ragg. `rect` is the panel's (left, top, width,
/// height) in canvas pixels: positions are rescaled from `x_range` /
/// `y_range` to it, infinite values squished to its edges, and each rect is
/// clipped to it. `colour` and `fill` come from `rs_point_colours()`; `lwd`
/// is grid's lwd (linewidth * .pt, 0 for blank line types), converted at
/// `res` pixels per inch. `join` is 0 (mitre), 1 (round) or 2 (bevel), with
/// grid's mitre limit of 10. `NULL` (decline) for unsupported inputs.
/// @noRd
#[extendr(r_name = "rs_render_rects")]
#[allow(clippy::too_many_arguments)]
fn render_rects(
    xmin: &[f64],
    xmax: &[f64],
    ymin: &[f64],
    ymax: &[f64],
    rows: &[i32],
    x_range: &[f64],
    y_range: &[f64],
    rect: &[f64],
    dims: &[i32],
    colour: &[i32],
    fill: &[i32],
    lwd: &[f64],
    join: i32,
    res: f64,
    threads: i32,
) -> Robj {
    let n = xmin.len();
    let [left, top, pw, ph] = rect else { return Robj::from(()) };
    let &[w, h] = dims else { return Robj::from(()) };
    let lens_ok = [xmax.len(), ymin.len(), ymax.len(), colour.len(), fill.len(), lwd.len()].iter().all(|&l| l == n);
    let rows_ok = rows.iter().all(|&r| r >= 1 && r as usize <= n);
    let join = match join {
        0 => Join::Miter,
        1 => Join::Round,
        2 => Join::Bevel,
        _ => return Robj::from(()),
    };
    if !lens_ok || !rows_ok || x_range.len() != 2 || y_range.len() != 2 {
        return Robj::from(());
    }
    let npc = |v: f64, r: &[f64]| {
        if v == f64::INFINITY {
            1.0
        } else if v == f64::NEG_INFINITY {
            0.0
        } else {
            (v - r[0]) / (r[1] - r[0])
        }
    };
    let bytes = |c: i32| {
        let c = c as u32;
        [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8]
    };
    let spec = |r: i32| {
        let i = r as usize - 1;
        RectSpec {
            x0: left + npc(xmin[i], x_range) * pw,
            y0: top + (1.0 - npc(ymin[i], y_range)) * ph,
            x1: left + npc(xmax[i], x_range) * pw,
            y1: top + (1.0 - npc(ymax[i], y_range)) * ph,
            fill: bytes(fill[i]),
            col: bytes(colour[i]),
            lwd: lwd[i] * res / 96.0,
        }
    };
    // Built in parallel chunks: a 1000 x 1000 tile layer has 1e6 rects.
    let chunk = rows.len().div_ceil(raster::default_threads()).max(1 << 15);
    let spec = &spec;
    let blank = RectSpec { x0: f64::NAN, y0: 0.0, x1: 0.0, y1: 0.0, fill: [0; 4], col: [0; 4], lwd: 0.0 };
    let mut specs = vec![blank; rows.len()];
    raster::par_map(rows.chunks(chunk.max(1)).zip(specs.chunks_mut(chunk.max(1))), |(src, dst)| {
        for (&r, d) in src.iter().zip(dst.iter_mut()) {
            *d = spec(r);
        }
    });
    let (w, h) = (w as usize, h as usize);
    let (out, ptr) = native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let mut list = DisplayList::new();
    list.push(Item::PushClip(Rect { x0: *left, y0: *top, x1: left + pw, y1: top + ph }));
    list.push(Item::Rects(RectBatch::new(specs, RectStyle { join, mitre: 10.0, snap: true })));
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&list, w, h, &opts, pixels);
    out
}

/// Renders one panel of a path or polygon layer to a nativeRaster of `dims`
/// (width, height) pixels, as grid's polylineGrob, polygonGrob and pathGrob
/// draw on ragg. `rows` (1-based) are the panel's rows in drawing order;
/// `path` gives each row's path (0-based, into the per-path `colour`,
/// `fill`, `lwd` and `lty`) and `ring` its ring within the path. Open
/// paths (`closed` false) are polylines, split at non-finite points into
/// separately drawn runs as grid does; closed ones are polygons filled with
/// `rule` (0 non-zero, 1 even-odd). `lwd` is grid's lwd, converted at `res`
/// pixels per inch; `lty` is R's packed line type (0 solid; dashes scaled by
/// the width). `cap` is 0 round, 1 butt, 2 square; `join` 0 round, 1 mitre,
/// 2 bevel. `rect` is the panel's (left, top, width, height) in canvas
/// pixels, positions are rescaled from `x_range`/`y_range` with infinite
/// values squished to its edges, and each path is clipped to it. `NULL`
/// (decline) for unsupported inputs.
/// @noRd
#[extendr(r_name = "rs_render_paths")]
#[allow(clippy::too_many_arguments)]
fn render_paths(
    x: &[f64],
    y: &[f64],
    rows: &[i32],
    path: &[i32],
    ring: &[i32],
    colour: &[i32],
    fill: &[i32],
    lwd: &[f64],
    lty: &[f64],
    style: &[i32],
    mitre: f64,
    x_range: &[f64],
    y_range: &[f64],
    rect: &[f64],
    dims: &[i32],
    res: f64,
    threads: i32,
) -> Robj {
    let n = x.len();
    let np = colour.len();
    let [left, top, pw, ph] = rect else { return Robj::from(()) };
    let &[w, h] = dims else { return Robj::from(()) };
    let &[closed, rule, cap, join] = style else { return Robj::from(()) };
    let lens_ok = y.len() == n && path.len() == rows.len() && ring.len() == rows.len() && [fill.len(), lwd.len(), lty.len()].iter().all(|&l| l == np);
    let idx_ok = rows.iter().all(|&r| r >= 1 && r as usize <= n) && path.iter().all(|&p| p >= 0 && (p as usize) < np);
    let lty_ok = lty.iter().all(|&l| l >= 0.0 && l <= u32::MAX as f64 && l.fract() == 0.0);
    let (rule, cap, join) = match (rule, cap, join) {
        (r @ 0..=1, c @ 0..=2, j @ 0..=2) => (
            if r == 0 { Rule::NonZero } else { Rule::EvenOdd },
            [Cap::Round, Cap::Butt, Cap::Square][c as usize],
            [Join::Round, Join::Miter, Join::Bevel][j as usize],
        ),
        _ => return Robj::from(()),
    };
    if !lens_ok || !idx_ok || !lty_ok || x_range.len() != 2 || y_range.len() != 2 {
        return Robj::from(());
    }
    let npc = |v: f64, r: &[f64]| {
        if v == f64::INFINITY {
            1.0
        } else if v == f64::NEG_INFINITY {
            0.0
        } else {
            (v - r[0]) / (r[1] - r[0])
        }
    };
    let bytes = |c: i32| {
        let c = c as u32;
        [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8]
    };
    let spec = |p: usize, rings: Vec<Vec<[f64; 2]>>| PathSpec {
        rings,
        closed: closed != 0,
        fill: bytes(fill[p]),
        rule,
        col: bytes(colour[p]),
        stroke: Stroke { lwd: lwd[p] * res / 96.0, lty: lty[p] as u32, cap, join, mitre },
    };
    let mut specs = Vec::new();
    let mut k = 0;
    while k < rows.len() {
        // One path: consecutive rows with the same `path`.
        let p = path[k] as usize;
        let mut rings: Vec<Vec<[f64; 2]>> = Vec::new();
        let mut last_ring = None;
        while k < rows.len() && path[k] as usize == p {
            let i = rows[k] as usize - 1;
            let pt = [left + npc(x[i], x_range) * pw, top + (1.0 - npc(y[i], y_range)) * ph];
            let new_ring = last_ring != Some(ring[k]);
            // Polylines break at NA, as grid draws each run separately.
            let broken = closed == 0 && !(pt[0].is_finite() && pt[1].is_finite());
            if broken {
                rings.push(Vec::new());
            } else {
                if new_ring || rings.is_empty() {
                    rings.push(Vec::new());
                }
                rings.last_mut().unwrap().push(pt);
            }
            last_ring = Some(ring[k]);
            k += 1;
        }
        rings.retain(|r| !r.is_empty());
        if closed != 0 {
            specs.push(spec(p, rings));
        } else {
            specs.extend(rings.into_iter().map(|r| spec(p, vec![r])));
        }
    }
    let (w, h) = (w as usize, h as usize);
    let (out, ptr) = native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let mut list = DisplayList::new();
    list.push(Item::PushClip(Rect { x0: *left, y0: *top, x1: left + pw, y1: top + ph }));
    list.push(Item::Paths(PathBatch::new(&specs)));
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&list, w, h, &opts, pixels);
    out
}

/// Writes a nativeRaster (`dim` = height, width) to `path` as PNG with the
/// metadata ragg's `agg_png()` writes for device background `bg` (R, G, B,
/// A, 0-255): RGBA unless `bg` is opaque, `bKGD`, and `pHYs` if `dpi` is
/// positive.
/// @noRd
#[extendr(r_name = "rs_write_png")]
fn write_png(raster: Robj, path: &str, bg: &[i32], dpi: f64) -> extendr_api::Result<()> {
    let dim = raster.get_attrib("dim").and_then(|d| d.as_integer_vector()).unwrap_or_default();
    let (Some(px), &[h, w], &[r, g, b, a]) = (raster.as_integer_slice(), &dim[..], bg) else {
        return Err(Error::Other("expected a nativeRaster and an RGBA background".into()));
    };
    let px = unsafe { std::slice::from_raw_parts(px.as_ptr() as *const u32, px.len()) };
    let byte = |v: i32| v.clamp(0, 255) as u8;
    let opts = PngOptions::for_background([byte(r), byte(g), byte(b), byte(a)], (dpi > 0.0).then_some(dpi));
    let file = std::fs::File::create(path).map_err(|e| Error::Other(e.to_string()))?;
    let mut enc = Encoder::new(std::io::BufWriter::new(file), w as u32, h as u32, &opts).map_err(|e| Error::Other(e.to_string()))?;
    // Rows go to the encoder in bands, as the executor hands them over.
    enc.write_rows(px).map_err(|e| Error::Other(e.to_string()))?;
    enc.finish().map_err(|e| Error::Other(e.to_string()))
}

extendr_module! {
    mod render;
    fn write_png;
    fn point_colours;
    fn point_shapes_supported;
    fn all_na_logical;
    fn columns_complete;
    fn constant_by_group;
    fn path_groups;
    fn render_points;
    fn render_rects;
    fn render_paths;
}
