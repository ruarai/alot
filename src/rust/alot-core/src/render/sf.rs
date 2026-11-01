//! `geom_sf()` features (tasks S3.2, S3.3; SPATIAL.md, Architecture "sf
//! geometry"). Mirrors what `GeomSf$draw_panel` (ggplot2 4.0.3
//! R/geom-sf.R) draws: `sf::st_as_grob()` of the panel's sfc (sf 1.1),
//! with GeomSf's per-feature gpar.
//!
//! - POLYGON and MULTIPOLYGON: one `pathGrob(rule = "evenodd")` per
//!   POLYGON (`scalar_grobs()`), and for an `sfc_MULTIPOLYGON` (or a mix of
//!   POLYGON and MULTIPOLYGON, which `st_cast_sfc_default()` casts to one)
//!   a single pathGrob with one path per polygon, its gpar repeated per
//!   polygon (`st_as_grob.sfc_MULTIPOLYGON()`, `expand_gp()`). grid draws
//!   each path in turn, and ragg's `drawPath()` (ragg 1.5.2
//!   src/AggDevice.h) fills it then strokes it. So each polygon, every part
//!   of a MULTIPOLYGON on its own, is one path of its rings, filled
//!   even-odd then stroked.
//! - LINESTRING and MULTILINESTRING: `polylineGrob()` with one id per
//!   linestring (`st_as_grob.sfc_LINESTRING()`,
//!   `st_as_grob.sfc_MULTILINESTRING()` with `expand_gp()`; `linesGrob()`
//!   or `polylineGrob()` per feature in a mixed sfc), each drawn by ragg's
//!   `drawPolyline()`: one open stroked path per linestring.
//! - POINT and MULTIPOINT: `pointsGrob()` (`st_as_grob.sfc_POINT()`,
//!   `st_as_grob.sfc_MULTIPOINT()`, `st_as_grob.POINT()`), one symbol per
//!   point through the point sprites, with the layer's lineend, linejoin
//!   and linemitre, which the gpar also gives the symbols' lines.
//!
//! Every way sf groups features (one grob per type, or one per feature in
//! a mixed sfc) draws them in data order, so the features are drawn in
//! data order, each feature's parts in order: one display item per run of
//! consecutive point features or of consecutive path (line and polygon)
//! features.

use crate::render::agg::{Cap, Join, Rule};
use crate::render::display::Item;
use crate::render::paths::{PathBatch, PathSpec, Stroke};
use crate::render::points::{Point, PointBatch, SymbolStyle};
use crate::sf::{Geometry, Kind};

/// The gpar of one feature: `fill` (`fill_alpha(fill, alpha)`) and `col`
/// (`alpha(colour, alpha)` for points and lines; `colour`, keeping its own
/// alpha, for polygons) as RGBA, `lwd` in device pixels (linewidth * .pt,
/// or the stroke for points) and `lty` as R's packed line type (0 solid).
/// For points, `shape` is the pch and `size` the symbol size in device
/// pixels (grid's fontsize, size * .pt + stroke, at res / 72); both are
/// unused for other features.
#[derive(Clone, Copy, Debug)]
pub struct FeatureStyle {
    pub fill: [u8; 4],
    pub col: [u8; 4],
    pub lwd: f64,
    pub lty: u32,
    pub shape: i32,
    pub size: f64,
}

/// Whether a feature draws as points.
pub fn is_point(k: Kind) -> bool {
    matches!(k, Kind::Point | Kind::MultiPoint)
}

/// Whether every feature is a POLYGON or MULTIPOLYGON.
pub fn all_polygons(g: &Geometry) -> bool {
    g.kind.iter().all(|k| matches!(k, Kind::Polygon | Kind::MultiPolygon))
}

/// The paths of the line and polygon features among `features`, already
/// in device pixels, in drawing order: one per part, a polygon's with the
/// rings of that part, a linestring's open. `style` has one entry per
/// feature of `g`.
pub fn feature_paths(g: &Geometry, features: std::ops::Range<usize>, style: &[FeatureStyle], cap: Cap, join: Join, mitre: f64) -> Vec<PathSpec> {
    assert_eq!(style.len(), g.n_features());
    let mut out = Vec::new();
    for i in features {
        let s = &style[i];
        let closed = match g.kind[i] {
            Kind::Polygon | Kind::MultiPolygon => true,
            Kind::LineString | Kind::MultiLineString => false,
            Kind::Point | Kind::MultiPoint => continue,
        };
        for p in g.feature_parts(i) {
            out.push(PathSpec {
                rings: g.part_rings(p).map(|r| g.ring(r).to_vec()).collect(),
                closed,
                // drawPolyline() only strokes.
                fill: if closed { s.fill } else { [0; 4] },
                rule: Rule::EvenOdd,
                col: s.col,
                stroke: Stroke { lwd: s.lwd, lty: s.lty, cap, join, mitre },
            });
        }
    }
    out
}

/// The paths of polygon features (see `feature_paths()`).
pub fn polygon_paths(g: &Geometry, style: &[FeatureStyle], cap: Cap, join: Join, mitre: f64) -> Vec<PathSpec> {
    feature_paths(g, 0..g.n_features(), style, cap, join, mitre)
}

/// The points of the point features among `features`, one per point (each
/// a part of one one-vertex ring), in data order.
pub fn feature_points(g: &Geometry, features: std::ops::Range<usize>, style: &[FeatureStyle]) -> Vec<Point> {
    assert_eq!(style.len(), g.n_features());
    let mut out = Vec::new();
    for i in features.filter(|&i| is_point(g.kind[i])) {
        let s = &style[i];
        for p in g.feature_parts(i) {
            let [x, y] = g.ring(g.part_rings(p).start)[0];
            out.push(Point { x, y, shape: s.shape, size: s.size, lwd: s.lwd, col: s.col, fill: s.fill });
        }
    }
    out
}

/// The display items of every feature, in drawing order: a point batch
/// per run of point features and a path batch per run of line and polygon
/// features. `cap`, `join` and `mitre` are the layer's lineend, linejoin
/// and linemitre, for lines, polygon outlines and symbols alike.
pub fn items(g: &Geometry, style: &[FeatureStyle], cap: Cap, join: Join, mitre: f64, threads: usize) -> Vec<Item> {
    assert_eq!(style.len(), g.n_features());
    let symbols = SymbolStyle { cap, join, mitre };
    let mut out = Vec::new();
    let n = g.n_features();
    let mut start = 0;
    while start < n {
        let points = is_point(g.kind[start]);
        let end = (start..n).find(|&i| is_point(g.kind[i]) != points).unwrap_or(n);
        if points {
            let pts = feature_points(g, start..end, style);
            out.push(Item::Points(PointBatch::from_fn_styled(pts.len(), threads, symbols, |k| Some(pts[k]))));
        } else {
            out.push(Item::Paths(PathBatch::new(&feature_paths(g, start..end, style, cap, join, mitre))));
        }
        start = end;
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
        FeatureStyle { fill, col: [0; 4], lwd: 0.0, lty: 0, shape: 19, size: 0.0 }
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

    fn line_style(col: [u8; 4], lwd: f64) -> FeatureStyle {
        FeatureStyle { fill: [0, 255, 0, 255], col, lwd, lty: 0, shape: 19, size: 0.0 }
    }

    fn point_style(col: [u8; 4], shape: i32) -> FeatureStyle {
        FeatureStyle { fill: [0, 255, 0, 255], col, lwd: 1.5, lty: 0, shape, size: 12.0 }
    }

    fn draw_items(g: &Geometry, s: &[FeatureStyle], cap: Cap) -> Vec<u32> {
        let mut list = DisplayList::new();
        for item in items(g, s, cap, Join::Round, 10.0, 2) {
            list.push(item);
        }
        render(&list, 30, 20, &Options { threads: 2, band_rows: 4 })
    }

    #[test]
    fn linestrings_are_open_and_unfilled() {
        // A closed ring as a LINESTRING: stroked along its length, never
        // filled (drawPolyline()), with the edge from the last vertex back
        // to the first drawn as a segment like any other.
        let g = geometry(vec![(Kind::LineString, vec![vec![square(2.0, 2.0, 14.0)]])]);
        let paths = feature_paths(&g, 0..1, &[line_style([0, 0, 0, 255], 2.0)], Cap::Butt, Join::Round, 10.0);
        assert_eq!(paths.len(), 1);
        assert!(!paths[0].closed);
        let img = draw_items(&g, &[line_style([0, 0, 0, 255], 2.0)], Cap::Butt);
        assert_eq!(img[9 * 30 + 9] >> 24, 0, "no fill");
        assert_eq!(img[2 * 30 + 9] >> 24, 255, "stroked");
    }

    #[test]
    fn multilinestring_parts_are_separate_polylines() {
        // Two crossing parts of one feature: each is stroked on its own, so
        // the crossing is blended twice.
        let g = geometry(vec![(
            Kind::MultiLineString,
            vec![vec![vec![[2.0, 10.0], [28.0, 10.0]]], vec![vec![[15.0, 2.0], [15.0, 18.0]]]],
        )]);
        let s = [line_style([255, 0, 0, 128], 3.0)];
        assert_eq!(feature_paths(&g, 0..1, &s, Cap::Butt, Join::Round, 10.0).len(), 2);
        let img = draw_items(&g, &s, Cap::Butt);
        let a = |x: usize, y: usize| img[y * 30 + x] >> 24;
        assert!(a(15, 10) > a(5, 10), "crossing {} vs single {}", a(15, 10), a(5, 10));
        // The same as two LINESTRING features.
        let two = geometry(vec![
            (Kind::LineString, vec![vec![vec![[2.0, 10.0], [28.0, 10.0]]]]),
            (Kind::LineString, vec![vec![vec![[15.0, 2.0], [15.0, 18.0]]]]),
        ]);
        assert_eq!(img, draw_items(&two, &[s[0], s[0]], Cap::Butt));
    }

    #[test]
    fn points_draw_as_point_sprites_in_the_layer_style() {
        let g = geometry(vec![
            (Kind::Point, vec![vec![vec![[6.3, 7.1]]]]),
            (Kind::MultiPoint, vec![vec![vec![[14.6, 9.9]]], vec![vec![[22.2, 12.5]]]]),
        ]);
        let s = [point_style([0, 0, 255, 200], 3), point_style([255, 0, 0, 200], 21)];
        let pts = feature_points(&g, 0..2, &s);
        assert_eq!(pts.len(), 3);
        assert_eq!((pts[2].x, pts[2].y, pts[2].shape), (22.2, 12.5, 21));
        let opts = Options { threads: 2, band_rows: 4 };
        for cap in [Cap::Butt, Cap::Round] {
            let mut list = DisplayList::new();
            let style = SymbolStyle { cap, join: Join::Round, mitre: 10.0 };
            list.push(Item::Points(PointBatch::from_fn_styled(pts.len(), 2, style, |k| Some(pts[k]))));
            assert_eq!(draw_items(&g, &s, cap), render(&list, 30, 20, &opts));
        }
        // geom_sf()'s default butt ends are visible on pch 3.
        assert_ne!(draw_items(&g, &s, Cap::Butt), draw_items(&g, &s, Cap::Round));
    }

    #[test]
    fn mixed_features_draw_in_data_order_by_runs() {
        let g = geometry(vec![
            (Kind::Point, vec![vec![vec![[10.0, 10.0]]]]),
            (Kind::Point, vec![vec![vec![[20.0, 10.0]]]]),
            (Kind::LineString, vec![vec![vec![[2.0, 10.0], [28.0, 10.0]]]]),
            (Kind::Polygon, vec![vec![square(16.0, 4.0, 6.0)]]),
            (Kind::MultiPoint, vec![vec![vec![[26.0, 5.0]]]]),
        ]);
        let s = [
            point_style([255, 0, 0, 255], 16),
            point_style([255, 0, 0, 255], 16),
            line_style([0, 0, 255, 255], 2.0),
            FeatureStyle { fill: [0, 255, 0, 255], col: [0; 4], lwd: 0.0, lty: 0, shape: 19, size: 0.0 },
            point_style([0, 0, 0, 255], 16),
        ];
        let list = items(&g, &s, Cap::Butt, Join::Round, 10.0, 2);
        let kinds: Vec<&str> = list.iter().map(|i| if matches!(i, Item::Points(_)) { "points" } else { "paths" }).collect();
        assert_eq!(kinds, ["points", "paths", "points"]);
        let img = draw_items(&g, &s, Cap::Butt);
        assert_eq!(img[10 * 30 + 10], 0xFF_FF_00_00, "line over the first point");
        assert_eq!(img[7 * 30 + 19], 0xFF_00_FF_00, "polygon over the second point");
        assert_eq!(img[5 * 30 + 26], 0xFF_00_00_00, "last point");
    }
}
