//! `geom_sf()` polygons (task S3.2; SPATIAL.md, Architecture "sf
//! geometry"). Mirrors what `GeomSf$draw_panel` (ggplot2 4.0.3
//! R/geom-sf.R) draws for POLYGON and MULTIPOLYGON features:
//! `sf::st_as_grob()` gives one `pathGrob(rule = "evenodd")` per POLYGON
//! (`scalar_grobs()`), and for an `sfc_MULTIPOLYGON` (or a mix of POLYGON
//! and MULTIPOLYGON, which `st_cast_sfc_default()` casts to one) a single
//! pathGrob with one path per polygon, its gpar repeated per polygon
//! (`st_as_grob.sfc_MULTIPOLYGON()`, `expand_gp()`; sf 1.1). grid draws
//! each path in turn, and ragg's `drawPath()` (ragg 1.5.2 src/AggDevice.h)
//! fills it then strokes it. So each polygon, every part of a MULTIPOLYGON
//! on its own, is one path of its rings, filled even-odd then stroked, in
//! data order.

use crate::render::agg::{Cap, Join, Rule};
use crate::render::paths::{PathSpec, Stroke};
use crate::sf::{Geometry, Kind};

/// The gpar of one feature: `fill` (`fill_alpha(fill, alpha)`), `col`
/// (`colour`, keeping its own alpha) as RGBA, `lwd` in device pixels and
/// `lty` as R's packed line type (0 solid).
#[derive(Clone, Copy, Debug)]
pub struct FeatureStyle {
    pub fill: [u8; 4],
    pub col: [u8; 4],
    pub lwd: f64,
    pub lty: u32,
}

/// Whether every feature is a POLYGON or MULTIPOLYGON.
pub fn all_polygons(g: &Geometry) -> bool {
    g.kind.iter().all(|k| matches!(k, Kind::Polygon | Kind::MultiPolygon))
}

/// The paths of polygon features already in device pixels, in drawing
/// order: one per polygon (part), with the rings of that part. `style` has
/// one entry per feature.
pub fn polygon_paths(g: &Geometry, style: &[FeatureStyle], cap: Cap, join: Join, mitre: f64) -> Vec<PathSpec> {
    assert_eq!(style.len(), g.n_features());
    let mut out = Vec::with_capacity(g.part_off.len().saturating_sub(1));
    for (i, s) in style.iter().enumerate() {
        for p in g.feature_parts(i) {
            out.push(PathSpec {
                rings: g.part_rings(p).map(|r| g.ring(r).to_vec()).collect(),
                closed: true,
                fill: s.fill,
                rule: Rule::EvenOdd,
                col: s.col,
                stroke: Stroke { lwd: s.lwd, lty: s.lty, cap, join, mitre },
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::display::{DisplayList, Item};
    use crate::render::paths::PathBatch;
    use crate::render::raster::{render, Options};
    use crate::sf::Builder;

    fn square(x: f64, y: f64, s: f64) -> Vec<[f64; 2]> {
        vec![[x, y], [x + s, y], [x + s, y + s], [x, y + s], [x, y]]
    }

    /// A geometry from features of parts of rings.
    fn geometry(features: Vec<(Kind, Vec<Vec<Vec<[f64; 2]>>>)>) -> Geometry {
        let mut b = Builder::new();
        for (k, parts) in features {
            b.feature(k);
            for rings in parts {
                b.part();
                for r in rings {
                    // Column-major, as sf stores a ring matrix.
                    let xy: Vec<f64> = r.iter().map(|p| p[0]).chain(r.iter().map(|p| p[1])).collect();
                    assert!(b.ring(&xy));
                }
            }
        }
        b.finish().unwrap()
    }

    fn style(fill: [u8; 4]) -> FeatureStyle {
        FeatureStyle { fill, col: [0; 4], lwd: 0.0, lty: 0 }
    }

    fn draw(g: &Geometry, s: &[FeatureStyle]) -> Vec<u32> {
        let mut list = DisplayList::new();
        list.push(Item::Paths(PathBatch::new(&polygon_paths(g, s, Cap::Butt, Join::Round, 10.0))));
        render(&list, 30, 20, &Options { threads: 2, band_rows: 4 })
    }

    #[test]
    fn holes_are_even_odd() {
        let g = geometry(vec![(Kind::Polygon, vec![vec![square(2.0, 2.0, 14.0), square(6.0, 6.0, 4.0)]])]);
        let img = draw(&g, &[style([0, 0, 255, 255])]);
        assert_eq!(img[8 * 30 + 8] >> 24, 0, "hole");
        assert_eq!(img[3 * 30 + 3] >> 24, 255);
    }

    #[test]
    fn multipolygon_parts_are_separate_paths() {
        // Two overlapping parts of one feature: each is filled on its own,
        // so the overlap is blended twice (not an even-odd hole).
        let g = geometry(vec![(Kind::MultiPolygon, vec![vec![square(2.0, 2.0, 10.0)], vec![square(6.0, 6.0, 10.0)]])]);
        let paths = polygon_paths(&g, &[style([255, 0, 0, 128])], Cap::Butt, Join::Round, 10.0);
        assert_eq!(paths.len(), 2);
        let img = draw(&g, &[style([255, 0, 0, 128])]);
        let a = |x: usize, y: usize| img[y * 30 + x] >> 24;
        assert!(a(8, 8) > a(3, 3), "overlap {} vs single {}", a(8, 8), a(3, 3));
    }

    #[test]
    fn features_draw_in_data_order() {
        let g = geometry(vec![
            (Kind::Polygon, vec![vec![square(2.0, 2.0, 10.0)]]),
            (Kind::Polygon, vec![vec![square(6.0, 6.0, 10.0)]]),
        ]);
        let img = draw(&g, &[style([255, 0, 0, 255]), style([0, 0, 255, 255])]);
        assert_eq!(img[8 * 30 + 8], 0xFF_FF_00_00, "second feature on top");
    }

    #[test]
    fn only_polygons_pass() {
        let mut g = geometry(vec![(Kind::Polygon, vec![vec![square(0.0, 0.0, 1.0)]])]);
        assert!(all_polygons(&g));
        g.kind[0] = Kind::LineString;
        assert!(!all_polygons(&g));
    }
}
