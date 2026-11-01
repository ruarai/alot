//! Glue for the `geom_sf()` polygon drawer (`alot_core::render::sf`, task
//! S3.2), drawn as a lazy grob in the hybrid tier (R/render-sf.R).

use alot_core::render::agg::{Cap, Join};
use alot_core::render::display::{DisplayList, Item, Rect};
use alot_core::render::paths::PathBatch;
use alot_core::render::raster;
use alot_core::render::sf::{all_polygons, polygon_paths, FeatureStyle};
use crate::sf::sfc_geometry;
use alot_core::sf::{rescale01, to_device};
use extendr_api::prelude::*;

/// Renders one panel of a `geom_sf()` layer of POLYGON and MULTIPOLYGON
/// features to a nativeRaster of `dims` (width, height) pixels, as
/// `GeomSf$draw_panel` draws them on ragg. `geometry` holds the panel's
/// features in data order (an sfc, or the list of its sfgs); `colour`,
/// `fill` (from `rs_point_colours()`), `lwd` (grid's lwd, converted at
/// `res` pixels per inch) and `lty` (R's packed line type, 0 solid) have
/// one entry per feature. `style` is (lineend, linejoin): lineend 0 round,
/// 1 butt, 2 square; linejoin 0 round, 1 mitre, 2 bevel. The geometry is
/// rescaled as `sf_rescale01()` rescales it from `x_range` / `y_range`
/// (CoordSf$transform's ranges after its `reverse` handling) and placed in
/// `rect`, the panel's (left, top, width, height) in canvas pixels, and
/// each path is clipped to it. `NULL` (decline) unless every feature is a
/// polygon the sfc reader reads, or for other unsupported inputs.
/// @noRd
#[extendr(r_name = "rs_render_sf_polygons")]
#[allow(clippy::too_many_arguments)]
fn render_sf_polygons(
    geometry: Robj,
    x_range: &[f64],
    y_range: &[f64],
    rect: &[f64],
    dims: &[i32],
    colour: &[i32],
    fill: &[i32],
    lwd: &[f64],
    lty: &[f64],
    style: &[i32],
    mitre: f64,
    res: f64,
    threads: i32,
) -> Robj {
    let (&[x0, x1], &[y0, y1], &[left, top, pw, ph], &[w, h], &[cap, join]) = (x_range, y_range, rect, dims, style) else {
        return Robj::from(());
    };
    let (cap, join) = match (cap, join) {
        (c @ 0..=2, j @ 0..=2) => ([Cap::Round, Cap::Butt, Cap::Square][c as usize], [Join::Round, Join::Miter, Join::Bevel][j as usize]),
        _ => return Robj::from(()),
    };
    let Some(mut g) = sfc_geometry(&geometry) else { return Robj::from(()) };
    let n = g.n_features();
    let lens_ok = [colour.len(), fill.len(), lwd.len(), lty.len()].iter().all(|&l| l == n);
    let lty_ok = lty.iter().all(|&l| l >= 0.0 && l <= u32::MAX as f64 && l.fract() == 0.0);
    let ranges_ok = [x0, x1, y0, y1].iter().all(|v| v.is_finite()) && x0 != x1 && y0 != y1;
    if !lens_ok || !lty_ok || !ranges_ok || !all_polygons(&g) || w < 0 || h < 0 {
        return Robj::from(());
    }
    let cell = Rect { x0: left, y0: top, x1: left + pw, y1: top + ph };
    // st_normalize() errors on these ranges; ggplot2 draws (and errors).
    if !rescale01(&mut g, [x0, x1], [y0, y1]) {
        return Robj::from(());
    }
    to_device(&mut g, &cell);
    if !g.coords.iter().all(|p| p[0].is_finite() && p[1].is_finite()) {
        return Robj::from(());
    }
    let bytes = |c: i32| {
        let c = c as u32;
        [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8]
    };
    let styles: Vec<FeatureStyle> = (0..n)
        .map(|i| FeatureStyle { fill: bytes(fill[i]), col: bytes(colour[i]), lwd: lwd[i] * res / 96.0, lty: lty[i] as u32 })
        .collect();
    let specs = polygon_paths(&g, &styles, cap, join, mitre);
    let (w, h) = (w as usize, h as usize);
    let (out, ptr) = crate::render::native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let mut list = DisplayList::new();
    list.push(Item::PushClip(cell));
    list.push(Item::Paths(PathBatch::new(&specs)));
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&list, w, h, &opts, pixels);
    out
}

extendr_module! {
    mod render_sf;
    fn render_sf_polygons;
}
