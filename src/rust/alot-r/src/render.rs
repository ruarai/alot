//! Glue for the Phase 2 point renderer (`alot_core::render::points`).

use crate::convert::{self, Column, ColumnData};
use alot_core::colour::hex;
use alot_core::render::points::{self, Point};
use alot_core::render::raster;
use extendr_api::prelude::*;
use std::collections::HashMap;

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

/// Colours of a point layer as `scales::alpha(colour, alpha)` would give
/// them, packed as nativeRaster ints (`R | G << 8 | B << 16 | A << 24`).
/// `alpha` is double (length 1 or `n`) or all-NA logical (keep the
/// colour's alpha); an NA among doubles also keeps it. `NULL` (decline) if any
/// colour is not `#RRGGBB(AA)` hex, or for other `alpha` types.
/// @noRd
#[extendr(r_name = "rs_point_colours")]
fn point_colours(colour: Strings, alpha: Robj) -> Robj {
    let n = colour.len();
    let alpha: Vec<f64> = match Column::new(&alpha).data {
        ColumnData::Double(v) if v.len() == 1 || v.len() == n => v.to_vec(),
        ColumnData::Logical(v) if (v.len() == 1 || v.len() == n) && v.iter().all(|v| v.is_none()) => vec![f64::NAN],
        _ => return Robj::from(()),
    };
    // R caches CHARSXPs, so parse each distinct pointer once.
    let mut cache: HashMap<extendr_api::SEXP, Option<[u8; 4]>> = HashMap::new();
    let mut out = Vec::with_capacity(n);
    for (i, &p) in convert::str_ptrs(&colour).iter().enumerate() {
        let rgba = *cache.entry(p).or_insert_with(|| {
            let s = colour.elt(i);
            if s.is_na() { None } else { hex::parse_hex(s.as_bytes()) }
        });
        let Some([r, g, b, mut a]) = rgba else { return Robj::from(()) };
        let al = at(&alpha, i);
        if !al.is_nan() {
            a = hex::double2int(al * 255.0).clamp(0, 255) as u8;
        }
        out.push((r as u32 | (g as u32) << 8 | (b as u32) << 16 | (a as u32) << 24) as i32);
    }
    Integers::from_values(out).into()
}

/// Whether every shape is one the renderer draws (double or integer
/// codes, no NA).
/// @noRd
#[extendr(r_name = "rs_point_shapes_supported")]
fn point_shapes_supported(shape: Robj) -> bool {
    match recycled(&shape, shape.len()) {
        Some(v) => v.iter().all(|&s| s.fract() == 0.0 && points::supported_shape(s as i32)),
        None => false,
    }
}

/// Renders the rows of a point layer in panel `panel_id` to a nativeRaster
/// of `dims` (width, height) pixels. `rect` is the panel's (left, top,
/// width, height) in canvas pixels; positions are rescaled from
/// `x_range`/`y_range` to it, with infinite values squished to the edges
/// as `CoordCartesian$transform()` does. `size` and `stroke` follow
/// `gg_par()`: symbol size (size * pt + stroke * stroke_scale / 2) pt, line
/// width stroke * stroke_scale / 2 lwd, converted at `res` pixels per inch.
/// `colour` comes from `rs_point_colours()`. `threads` is the band
/// executor's worker count (0: available cores, capped at 8). `NULL`
/// (decline) for unsupported inputs.
/// @noRd
#[extendr(r_name = "rs_render_points")]
#[allow(clippy::too_many_arguments)]
fn render_points(
    x: &[f64],
    y: &[f64],
    panel: &[i32],
    panel_id: i32,
    x_range: &[f64],
    y_range: &[f64],
    rect: &[f64],
    dims: &[i32],
    shape: Robj,
    size: Robj,
    stroke: Robj,
    colour: &[i32],
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
    if y.len() != n || panel.len() != n || colour.len() != n || x_range.len() != 2 || y_range.len() != 2 {
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
    let pts = (0..n).filter(|&i| panel[i] == panel_id).map(|i| {
        let st = at(&stroke, i);
        let c = colour[i] as u32;
        Point {
            x: left + npc(x[i], x_range) * pw,
            y: top + (1.0 - npc(y[i], y_range)) * ph,
            shape: at(&shape, i) as i32,
            size: (at(&size, i) * pt + st * stroke_scale / 2.0) * res / 72.0,
            lwd: st * stroke_scale / 2.0 * res / 96.0,
            rgba: [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8],
        }
    });
    let (w, h) = (w as usize, h as usize);
    let mut out: Robj = Integers::new(w * h).into();
    let ints = out.as_integer_slice_mut().unwrap();
    // nativeRaster ints are the packed pixels bit for bit.
    let pixels = unsafe { std::slice::from_raw_parts_mut(ints.as_mut_ptr() as *mut u32, ints.len()) };
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    points::render_into(w, h, pts, &opts, pixels);
    let (w, h) = (w as i32, h as i32);
    out.set_attrib("dim", Integers::from_values([h, w])).unwrap();
    out.set_attrib("class", "nativeRaster").unwrap();
    out.set_attrib("channels", 4).unwrap();
    out
}

/// Writes a nativeRaster (`dim` = height, width) to `path` as PNG: RGBA if
/// `alpha`, else RGB; with a `pHYs` chunk if `dpi` is positive.
/// @noRd
#[extendr(r_name = "rs_write_png")]
fn write_png(raster: Robj, path: &str, alpha: bool, dpi: f64) -> extendr_api::Result<()> {
    let dim = raster.get_attrib("dim").and_then(|d| d.as_integer_vector()).unwrap_or_default();
    let (Some(px), &[h, w]) = (raster.as_integer_slice(), &dim[..]) else {
        return Err(Error::Other("expected a nativeRaster".into()));
    };
    let px = unsafe { std::slice::from_raw_parts(px.as_ptr() as *const u32, px.len()) };
    let bytes = alot_core::render::png::encode(w as u32, h as u32, px, alpha, (dpi > 0.0).then_some(dpi)).map_err(|e| Error::Other(e.to_string()))?;
    std::fs::write(path, bytes).map_err(|e| Error::Other(e.to_string()))
}

extendr_module! {
    mod render;
    fn write_png;
    fn point_colours;
    fn point_shapes_supported;
    fn render_points;
}
