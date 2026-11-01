//! A flat sfc (an sf geometry column) and the steps that place it in a
//! panel: `CoordSf$transform()` -> `sf_rescale01()` (ggplot2 R/coord-sf.R)
//! and the npc -> device-pixel step of the renderer.
use crate::render::display::Rect;

/// The sfg types read. Everything else (GEOMETRYCOLLECTION, CURVEPOLYGON,
/// ...) declines.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Point,
    MultiPoint,
    LineString,
    MultiLineString,
    Polygon,
    MultiPolygon,
}

impl Kind {
    pub const ALL: [Kind; 6] =
        [Kind::Point, Kind::MultiPoint, Kind::LineString, Kind::MultiLineString, Kind::Polygon, Kind::MultiPolygon];

    /// sf's name for the type, the second element of an sfg's class.
    pub fn name(self) -> &'static str {
        match self {
            Kind::Point => "POINT",
            Kind::MultiPoint => "MULTIPOINT",
            Kind::LineString => "LINESTRING",
            Kind::MultiLineString => "MULTILINESTRING",
            Kind::Polygon => "POLYGON",
            Kind::MultiPolygon => "MULTIPOLYGON",
        }
    }

    /// The kind of an sfg whose class is `c(dim, type, "sfg")`. Only `"XY"`
    /// geometries are read: XYZ, XYM and XYZM decline (None), as does any
    /// type outside `Kind::ALL`.
    pub fn from_class(dim: &[u8], type_name: &[u8]) -> Option<Kind> {
        if dim != b"XY" {
            return None;
        }
        Kind::ALL.into_iter().find(|k| k.name().as_bytes() == type_name)
    }
}

/// A flat sfc. The hierarchy is uniform: feature -> parts -> rings -> vertices.
///   POINT            1 part, 1 ring of 1 vertex
///   MULTIPOINT       one part per point, each 1 ring of 1 vertex
///   LINESTRING       1 part, 1 ring
///   MULTILINESTRING  one part per linestring, each 1 ring
///   POLYGON          1 part, one ring per sfg matrix (exterior first)
///   MULTIPOLYGON     one part per polygon, one ring per matrix
/// Vertices are in data order. Ring matrices are kept as sf stores them
/// (closing vertex included; nothing dropped or reordered).
#[derive(Debug, Clone, PartialEq)]
pub struct Geometry {
    /// One per feature.
    pub kind: Vec<Kind>,
    /// Every vertex, `[x, y]`.
    pub coords: Vec<[f64; 2]>,
    /// n_rings + 1 offsets into `coords`.
    pub ring_off: Vec<usize>,
    /// n_parts + 1 offsets into rings.
    pub part_off: Vec<usize>,
    /// n_features + 1 offsets into parts.
    pub feature_off: Vec<usize>,
}

impl Geometry {
    pub fn n_features(&self) -> usize {
        self.kind.len()
    }

    /// Rings (indices into ring_off) of feature `i`, across all its parts.
    pub fn feature_rings(&self, i: usize) -> std::ops::Range<usize> {
        let parts = self.feature_parts(i);
        self.part_off[parts.start]..self.part_off[parts.end]
    }

    /// Parts (indices into part_off) of feature `i`.
    pub fn feature_parts(&self, i: usize) -> std::ops::Range<usize> {
        self.feature_off[i]..self.feature_off[i + 1]
    }

    /// Rings of part `p`.
    pub fn part_rings(&self, p: usize) -> std::ops::Range<usize> {
        self.part_off[p]..self.part_off[p + 1]
    }

    /// The vertices of ring `r`.
    pub fn ring(&self, r: usize) -> &[[f64; 2]] {
        &self.coords[self.ring_off[r]..self.ring_off[r + 1]]
    }

    /// True if every feature has the shape its kind requires (see the
    /// struct docs), with at least one part, ring and vertex everywhere.
    fn is_well_formed(&self) -> bool {
        let n = self.n_features();
        if n == 0 || self.feature_off.len() != n + 1 {
            return false;
        }
        (0..n).all(|i| {
            let parts = self.feature_parts(i);
            let single = |p: usize| self.part_rings(p).len() == 1;
            let point = |p: usize| single(p) && self.ring(self.part_rings(p).start).len() == 1;
            !parts.is_empty()
                && parts.clone().all(|p| !self.part_rings(p).is_empty() && self.part_rings(p).all(|r| !self.ring(r).is_empty()))
                && match self.kind[i] {
                    Kind::Point => parts.len() == 1 && point(parts.start),
                    Kind::MultiPoint => parts.clone().all(point),
                    Kind::LineString => parts.len() == 1 && single(parts.start),
                    Kind::MultiLineString => parts.clone().all(single),
                    Kind::Polygon => parts.len() == 1,
                    Kind::MultiPolygon => true,
                }
        })
    }
}

/// Builds a `Geometry` feature by feature, from coordinate matrices as sf
/// stores them (column-major `n x 2`; a POINT's `c(x, y)` is a 1-row
/// matrix). `finish()` declines (None) unless every feature is non-empty
/// and shaped as its kind requires, and every coordinate is finite.
#[derive(Debug, Default)]
pub struct Builder {
    g: Option<Geometry>,
    ok: bool,
}

impl Builder {
    pub fn new() -> Builder {
        let g = Geometry { kind: Vec::new(), coords: Vec::new(), ring_off: vec![0], part_off: vec![0], feature_off: vec![0] };
        Builder { g: Some(g), ok: true }
    }

    fn g(&mut self) -> &mut Geometry {
        self.g.as_mut().expect("Builder used after finish")
    }

    /// Starts a feature.
    pub fn feature(&mut self, kind: Kind) {
        let g = self.g();
        g.kind.push(kind);
        let n = g.part_off.len() - 1;
        g.feature_off.push(n);
    }

    /// Starts a part of the current feature.
    pub fn part(&mut self) {
        let g = self.g();
        let n = g.ring_off.len() - 1;
        g.part_off.push(n);
        *g.feature_off.last_mut().unwrap() += 1;
    }

    /// Adds `xy`, a column-major `n x 2` matrix, as one ring of the
    /// current part. False (and `finish()` declines) if `xy` is empty, has
    /// an odd length or holds a non-finite value.
    pub fn ring(&mut self, xy: &[f64]) -> bool {
        if !self.push_coords(xy) {
            return false;
        }
        let g = self.g();
        g.ring_off.push(g.coords.len());
        *g.part_off.last_mut().unwrap() += 1;
        true
    }

    /// Adds each row of `xy` (a MULTIPOINT matrix) as a part with one ring
    /// of one vertex. False as for `ring()`.
    pub fn points(&mut self, xy: &[f64]) -> bool {
        let start = self.g().coords.len();
        if !self.push_coords(xy) {
            return false;
        }
        let g = self.g();
        for k in start..g.coords.len() {
            g.part_off.push(g.ring_off.len());
            g.ring_off.push(k + 1);
        }
        *g.feature_off.last_mut().unwrap() += g.coords.len() - start;
        true
    }

    fn push_coords(&mut self, xy: &[f64]) -> bool {
        if xy.is_empty() || xy.len() % 2 != 0 || !xy.iter().all(|v| v.is_finite()) {
            self.ok = false;
            return false;
        }
        let (xs, ys) = xy.split_at(xy.len() / 2);
        self.g().coords.extend(xs.iter().zip(ys).map(|(&x, &y)| [x, y]));
        true
    }

    /// The geometry, or None if anything added was declined, there are no
    /// features, or a feature is empty or misshapen for its kind.
    pub fn finish(mut self) -> Option<Geometry> {
        let g = self.g.take()?;
        (self.ok && g.is_well_formed()).then_some(g)
    }
}

/// Mirrors CoordSf$transform -> sf_rescale01() (ggplot2 R/coord-sf.R),
/// in place: st_normalize() to c(x_range[1], y_range[1], x_range[2],
/// y_range[2]) with the same floating-point arithmetic as sf, and the
/// `x * mult + pmax(-mult, 0)` flip for a reversed range. `x_range` and
/// `y_range` are passed AFTER CoordSf$transform's `reverse` handling,
/// i.e. exactly what sf_rescale01() receives.
///
/// st_normalize.sfc (sf R/normalize.R) errors unless both ranges are
/// positive and finite ("domain must have a positive range"); this
/// returns false for those, and for non-finite limits, leaving `g`
/// unchanged, so the caller falls back.
pub fn rescale01(g: &mut Geometry, x_range: [f64; 2], y_range: [f64; 2]) -> bool {
    // `if (isTRUE(x_range[1] > x_range[2])) { x_range <- sort(x_range);
    // mult[1] <- -1 }`, and the same for y.
    let sorted = |r: [f64; 2]| if r[0] > r[1] { ([r[1], r[0]], true) } else { (r, false) };
    let ((xr, flip_x), (yr, flip_y)) = (sorted(x_range), sorted(y_range));
    if !(xr.iter().chain(&yr).all(|v| v.is_finite())) {
        return false;
    }
    // st_normalize.sfc: `min <- -domain[c(1, 2)]`, `range <- 1 /
    // c(domain[3] - domain[1], domain[4] - domain[2])`, then sf's C++
    // normalize_sfc() (sf src/ops.cpp) adds `min` and multiplies by
    // `range` in two passes: `(v + min) * range`.
    let min = [-xr[0], -yr[0]];
    let range = [1.0 / (xr[1] - xr[0]), 1.0 / (yr[1] - yr[0])];
    if range.iter().any(|r| r.is_infinite() || *r < 0.0 || r.is_nan()) {
        return false;
    }
    // The flip, `x * mult + pmax(-mult, 0)`, goes through Ops.sfg (sf
    // R/arith.R): `x %*% diag(mult)` then `+ c(1, 0)`-style offsets. For
    // finite v, `v * -1 + 0 * w` is exactly `-v`, and `-v + 1` is `1 - v`.
    for c in g.coords.iter_mut() {
        let mut x = (c[0] + min[0]) * range[0];
        let mut y = (c[1] + min[1]) * range[1];
        if flip_x {
            x = -x + 1.0;
        }
        if flip_y {
            y = -y + 1.0;
        }
        *c = [x, y];
    }
    true
}

/// npc -> device pixels inside panel cell `cell`, in place, the way
/// render/layers.rs places marks: x = cell.x0 + x * (cell.x1 - cell.x0),
/// y = cell.y0 + (1 - y) * (cell.y1 - cell.y0).
pub fn to_device(g: &mut Geometry, cell: &Rect) {
    let (pw, ph) = (cell.x1 - cell.x0, cell.y1 - cell.y0);
    for c in g.coords.iter_mut() {
        *c = [cell.x0 + c[0] * pw, cell.y0 + (1.0 - c[1]) * ph];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Column-major `n x 2` from rows.
    fn mat(rows: &[[f64; 2]]) -> Vec<f64> {
        rows.iter().map(|r| r[0]).chain(rows.iter().map(|r| r[1])).collect()
    }

    fn square(x0: f64, y0: f64, d: f64) -> Vec<f64> {
        mat(&[[x0, y0], [x0 + d, y0], [x0 + d, y0 + d], [x0, y0 + d], [x0, y0]])
    }

    /// One feature of every kind, in the order of Kind::ALL.
    fn every_kind() -> Geometry {
        let mut b = Builder::new();
        b.feature(Kind::Point);
        b.part();
        assert!(b.ring(&[1.0, 2.0]));
        b.feature(Kind::MultiPoint);
        assert!(b.points(&mat(&[[3.0, 4.0], [5.0, 6.0], [7.0, 8.0]])));
        b.feature(Kind::LineString);
        b.part();
        assert!(b.ring(&mat(&[[0.0, 0.0], [1.0, 1.0]])));
        b.feature(Kind::MultiLineString);
        b.part();
        assert!(b.ring(&mat(&[[0.0, 1.0], [2.0, 3.0]])));
        b.part();
        assert!(b.ring(&mat(&[[4.0, 5.0], [6.0, 7.0], [8.0, 9.0]])));
        b.feature(Kind::Polygon);
        b.part();
        assert!(b.ring(&square(0.0, 0.0, 4.0)));
        assert!(b.ring(&square(1.0, 1.0, 1.0)));
        b.feature(Kind::MultiPolygon);
        b.part();
        assert!(b.ring(&square(10.0, 10.0, 1.0)));
        b.part();
        assert!(b.ring(&square(20.0, 20.0, 3.0)));
        assert!(b.ring(&square(21.0, 21.0, 1.0)));
        b.finish().expect("well formed")
    }

    #[test]
    fn kinds_from_class() {
        for k in Kind::ALL {
            assert_eq!(Kind::from_class(b"XY", k.name().as_bytes()), Some(k));
        }
        for dim in [&b"XYZ"[..], b"XYM", b"XYZM"] {
            assert_eq!(Kind::from_class(dim, b"POLYGON"), None);
        }
        for t in [&b"GEOMETRYCOLLECTION"[..], b"GEOMETRY", b"CURVEPOLYGON", b"TRIANGLE", b"polygon"] {
            assert_eq!(Kind::from_class(b"XY", t), None);
        }
    }

    #[test]
    fn layout_of_each_kind() {
        let g = every_kind();
        assert_eq!(g.kind, Kind::ALL.to_vec());
        assert_eq!(g.n_features(), 6);
        // Parts per feature: 1, 3, 1, 2, 1, 2.
        assert_eq!(g.feature_off, vec![0, 1, 4, 5, 7, 8, 10]);
        // Rings per part: 1 each, then the polygon's 2, then 1 and 2.
        assert_eq!(g.part_off, vec![0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 12]);
        assert_eq!(g.ring_off, vec![0, 1, 2, 3, 4, 6, 8, 11, 16, 21, 26, 31, 36]);
        assert_eq!(g.coords.len(), 36);

        assert_eq!(g.ring(0), &[[1.0, 2.0]]);
        let mp: Vec<_> = g.feature_rings(1).map(|r| g.ring(r)[0]).collect();
        assert_eq!(mp, vec![[3.0, 4.0], [5.0, 6.0], [7.0, 8.0]]);
        assert_eq!(g.feature_parts(1), 1..4);
        assert_eq!(g.ring(g.feature_rings(2).start), &[[0.0, 0.0], [1.0, 1.0]]);
        assert_eq!(g.feature_rings(3), 5..7);
        assert_eq!(g.ring(6), &[[4.0, 5.0], [6.0, 7.0], [8.0, 9.0]]);
        // Polygon: one part, exterior then hole, closing vertex kept.
        assert_eq!(g.feature_parts(4), 7..8);
        assert_eq!(g.part_rings(7), 7..9);
        assert_eq!(g.ring(7), &[[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0], [0.0, 0.0]]);
        assert_eq!(g.ring(8)[0], [1.0, 1.0]);
        // MultiPolygon: two parts, the second with a hole.
        assert_eq!(g.feature_parts(5), 8..10);
        assert_eq!(g.part_rings(8), 9..10);
        assert_eq!(g.part_rings(9), 10..12);
        assert_eq!(g.feature_rings(5), 9..12);
        assert_eq!(g.ring(11)[4], [21.0, 21.0]);
    }

    #[test]
    fn declines() {
        // No features.
        assert_eq!(Builder::new().finish(), None);
        // Empty feature, part or ring.
        let mut b = Builder::new();
        b.feature(Kind::Polygon);
        assert_eq!(b.finish(), None);
        let mut b = Builder::new();
        b.feature(Kind::Polygon);
        b.part();
        assert_eq!(b.finish(), None);
        let mut b = Builder::new();
        b.feature(Kind::LineString);
        b.part();
        assert!(!b.ring(&[]));
        assert_eq!(b.finish(), None);
        let mut b = Builder::new();
        b.feature(Kind::MultiPoint);
        assert!(!b.points(&[]));
        assert_eq!(b.finish(), None);
        // Non-finite or odd-length coordinates.
        for bad in [vec![f64::NAN, 1.0], vec![1.0, f64::INFINITY], vec![f64::NEG_INFINITY, 0.0], vec![1.0, 2.0, 3.0]] {
            let mut b = Builder::new();
            b.feature(Kind::LineString);
            b.part();
            assert!(!b.ring(&bad));
            assert_eq!(b.finish(), None);
        }
        // A later bad feature declines the whole sfc.
        let mut b = Builder::new();
        b.feature(Kind::Point);
        b.part();
        assert!(b.ring(&[0.0, 0.0]));
        b.feature(Kind::Point);
        b.part();
        assert!(!b.ring(&[f64::NAN, 0.0]));
        assert_eq!(b.finish(), None);
        // Misshapen for the kind.
        let misshapen: [(Kind, &dyn Fn(&mut Builder)); 4] = [
            (Kind::Point, &|b| {
                b.part();
                b.ring(&mat(&[[0.0, 0.0], [1.0, 1.0]]));
            }),
            (Kind::LineString, &|b| {
                b.part();
                b.ring(&[0.0, 0.0]);
                b.ring(&[1.0, 1.0]);
            }),
            (Kind::Polygon, &|b| {
                b.part();
                b.ring(&square(0.0, 0.0, 1.0));
                b.part();
                b.ring(&square(0.0, 0.0, 1.0));
            }),
            (Kind::MultiPoint, &|b| {
                b.part();
                b.ring(&mat(&[[0.0, 0.0], [1.0, 1.0]]));
            }),
        ];
        for (k, add) in misshapen {
            let mut b = Builder::new();
            b.feature(k);
            add(&mut b);
            assert_eq!(b.finish(), None, "{k:?}");
        }
    }

    #[test]
    fn rescale_matches_sf_arithmetic() {
        let mut g = every_kind();
        let orig = g.clone();
        let (xr, yr) = ([-0.3, 24.7], [0.1, 24.2]);
        assert!(rescale01(&mut g, xr, yr));
        for (c, o) in g.coords.iter().zip(&orig.coords) {
            assert_eq!(c[0], (o[0] + -xr[0]) * (1.0 / (xr[1] - xr[0])));
            assert_eq!(c[1], (o[1] + -yr[0]) * (1.0 / (yr[1] - yr[0])));
        }
        // Offsets are untouched.
        assert_eq!((g.ring_off, g.part_off, g.feature_off, g.kind), (orig.ring_off, orig.part_off, orig.feature_off, orig.kind));
    }

    #[test]
    fn rescale_reversed_ranges() {
        let orig = every_kind();
        let (xr, yr) = ([-0.3, 24.7], [0.1, 24.2]);
        let mut fwd = orig.clone();
        assert!(rescale01(&mut fwd, xr, yr));
        for (rx, ry) in [(true, false), (false, true), (true, true)] {
            let mut g = orig.clone();
            let x = if rx { [xr[1], xr[0]] } else { xr };
            let y = if ry { [yr[1], yr[0]] } else { yr };
            assert!(rescale01(&mut g, x, y));
            for (c, f) in g.coords.iter().zip(&fwd.coords) {
                assert_eq!(c[0], if rx { 1.0 - f[0] } else { f[0] });
                assert_eq!(c[1], if ry { 1.0 - f[1] } else { f[1] });
            }
        }
    }

    #[test]
    fn rescale_declines_where_sf_errors() {
        let orig = every_kind();
        for (x, y) in [
            ([1.0, 1.0], [0.0, 1.0]),
            ([0.0, 1.0], [2.0, 2.0]),
            ([f64::NAN, 1.0], [0.0, 1.0]),
            ([0.0, 1.0], [0.0, f64::INFINITY]),
            ([f64::NEG_INFINITY, 1.0], [0.0, 1.0]),
        ] {
            let mut g = orig.clone();
            assert!(!rescale01(&mut g, x, y), "{x:?} {y:?}");
            assert_eq!(g, orig);
        }
    }

    #[test]
    fn device_placement() {
        let mut g = every_kind();
        assert!(rescale01(&mut g, [0.0, 25.0], [0.0, 25.0]));
        let npc = g.clone();
        let cell = Rect { x0: 10.5, y0: 20.0, x1: 410.5, y1: 220.0 };
        to_device(&mut g, &cell);
        for (d, n) in g.coords.iter().zip(&npc.coords) {
            assert_eq!(d[0], cell.x0 + n[0] * (cell.x1 - cell.x0));
            assert_eq!(d[1], cell.y0 + (1.0 - n[1]) * (cell.y1 - cell.y0));
        }
        // npc (0, 0) is the cell's bottom-left corner; (1, 1) its top-right.
        assert_eq!(g.ring(g.feature_rings(4).start)[0], [10.5, 220.0]);
        let mut corner = Builder::new();
        corner.feature(Kind::Point);
        corner.part();
        corner.ring(&[1.0, 1.0]);
        let mut corner = corner.finish().unwrap();
        to_device(&mut corner, &cell);
        assert_eq!(corner.coords, vec![[410.5, 20.0]]);
    }
}
