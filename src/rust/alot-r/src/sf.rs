//! Reads sf geometry columns (sfc lists) for R/sf.R.
use alot_core::sf::{rescale01, Bbox, Builder, Geometry, Kind};
use extendr_api::prelude::*;
use extendr_api::SEXP;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

#[allow(improper_ctypes, non_upper_case_globals)] // SEXP is opaque, as in extendr-ffi.
extern "C" {
    // R API (Rinternals.h).
    fn TYPEOF(x: SEXP) -> c_int;
    fn XLENGTH(x: SEXP) -> isize;
    fn REAL(x: SEXP) -> *mut f64;
    fn INTEGER(x: SEXP) -> *mut c_int;
    fn VECTOR_ELT(x: SEXP, i: isize) -> SEXP;
    fn STRING_ELT(x: SEXP, i: isize) -> SEXP;
    fn R_CHAR(x: SEXP) -> *const c_char;
    fn Rf_getAttrib(x: SEXP, name: SEXP) -> SEXP;
    fn Rf_setAttrib(x: SEXP, name: SEXP, value: SEXP) -> SEXP;
    fn Rf_allocVector(kind: c_int, n: isize) -> SEXP;
    fn Rf_mkChar(s: *const c_char) -> SEXP;
    fn SET_STRING_ELT(x: SEXP, i: isize, v: SEXP);
    fn Rf_protect(x: SEXP) -> SEXP;
    fn Rf_unprotect(n: c_int);
    // Copies all attributes except names, dim and dimnames.
    fn Rf_copyMostAttrib(from: SEXP, to: SEXP);
    // `identical()`; flags 0 compares attributes as a set.
    fn R_compute_identical(x: SEXP, y: SEXP, flags: c_int) -> c_int;
    static R_NilValue: SEXP;
    static R_ClassSymbol: SEXP;
    static R_DimSymbol: SEXP;
    static R_NamesSymbol: SEXP;
    static R_DimNamesSymbol: SEXP;
}

const INTSXP: c_int = 13;
const REALSXP: c_int = 14;
const STRSXP: c_int = 16;
const VECSXP: c_int = 19;


/// Walks the features of an sfc. Returns `list(bbox = c(xmin, ymin, xmax,
/// ymax), types = <1-based code per feature into Kind::ALL>)`, or NULL unless
/// every feature is a non-empty XY POINT, MULTIPOINT, LINESTRING,
/// MULTILINESTRING, POLYGON or MULTIPOLYGON stored the way
/// `sf:::CPL_transform()` returns it: double coordinates, all finite; a
/// class of exactly `c("XY", <type>, "sfg")` on the feature; `dim`
/// (`n x 2`, n >= 1) on each matrix and no other attribute anywhere.
/// @noRd
#[extendr(r_name = "rs_sfc_plain_xy")]
fn sfc_plain_xy(sfc: Robj) -> Robj {
    // SAFETY: `x` is protected by `sfc`. Every SEXP read below is an
    // element or attribute of `x`, so protected through it; the scratch
    // vectors are protected until the walk ends.
    unsafe {
        let x = sfc.get();
        if TYPEOF(x) != VECSXP || XLENGTH(x) == 0 {
            return ().into();
        }
        let mut walk = Walk::new(false, false);
        let ok = (0..XLENGTH(x)).all(|i| walk.feature(VECTOR_ELT(x, i)));
        let n_protected = walk.n_protected;
        let out = match (ok, walk.bbox.0) {
            (true, Some(b)) => list!(bbox = Doubles::from_values(b), types = Integers::from_values(walk.types)).into(),
            _ => ().into(),
        };
        Rf_unprotect(n_protected);
        out
    }
}

/// The type code of each feature of an sfc that `sfc_geometry()` reads (as
/// `rs_sfc_plain_xy()`'s `types`), or NULL where it declines: the render
/// path's check (R/render-sf.R), which unlike `rs_sfc_plain_xy()` also
/// takes integer coordinates.
/// @noRd
#[extendr(r_name = "rs_sfc_render_types")]
fn sfc_render_types(sfc: Robj) -> Robj {
    // SAFETY: as in sfc_plain_xy().
    unsafe {
        let x = sfc.get();
        if TYPEOF(x) != VECSXP || XLENGTH(x) == 0 {
            return ().into();
        }
        let mut walk = Walk::new(false, true);
        let ok = (0..XLENGTH(x)).all(|i| walk.feature(VECTOR_ELT(x, i)));
        Rf_unprotect(walk.n_protected);
        if ok { Integers::from_values(walk.types).into() } else { ().into() }
    }
}

/// Reads an sfc in one pass, borrowing each coordinate matrix. None (decline)
/// unless every feature is a non-empty XY POINT/MULTIPOINT/LINESTRING/
/// MULTILINESTRING/POLYGON/MULTIPOLYGON stored as the existing
/// `rs_sfc_plain_xy()` walker accepts, except that integer coordinates are
/// read too (GEOMETRYCOLLECTION, empty features, NA, XYZ/XYM/XYZM all
/// decline). An empty sfc (length 0) also gives None. Integers are
/// converted to doubles exactly; `sf_rescale01()` gives an integer sfc the
/// same doubles as its double copy (st_normalize(); sf src/ops.cpp reads
/// the coordinates as doubles), so nothing downstream sees the difference.
pub(crate) fn sfc_geometry(sfc: &Robj) -> Option<Geometry> {
    // SAFETY: as in sfc_plain_xy().
    unsafe {
        let x = sfc.get();
        if TYPEOF(x) != VECSXP || XLENGTH(x) == 0 {
            return None;
        }
        let mut walk = Walk::new(true, true);
        let ok = (0..XLENGTH(x)).all(|i| walk.feature(VECTOR_ELT(x, i)));
        Rf_unprotect(walk.n_protected);
        if !ok {
            return None;
        }
        walk.build.take()?.finish()
    }
}

/// Test hook: the coordinates of `sfc` after `sf_rescale01(sfc, x_range,
/// y_range)` (ggplot2 R/coord-sf.R), as the `n x 2` matrix of the X and Y
/// columns of `sf::st_coordinates()`, or NULL if sfc_geometry() or
/// rescale01() declines.
/// @noRd
#[extendr(r_name = "rs_sf_rescale01")]
fn sf_rescale01(sfc: Robj, x_range: &[f64], y_range: &[f64]) -> Robj {
    let (Ok(xr), Ok(yr)) = (<[f64; 2]>::try_from(x_range), <[f64; 2]>::try_from(y_range)) else {
        return ().into();
    };
    let Some(mut g) = sfc_geometry(&sfc) else { return ().into() };
    if !rescale01(&mut g, xr, yr) {
        return ().into();
    }
    let n = g.coords.len();
    RMatrix::new_matrix(n, 2, |i, j| g.coords[i][j]).into()
}

struct Walk {
    bbox: Bbox,
    // The flat geometry, when sfc_geometry() reads the sfc.
    build: Option<Builder>,
    // Whether integer coordinates are read (as doubles), for the renderer.
    ints: bool,
    types: Vec<i32>,
    // An empty double vector that receives a value's attributes (except
    // names, dim and dimnames) to compare them with `plain` or `classed`;
    // emptied after each comparison that succeeds.
    scratch: SEXP,
    plain: SEXP,
    classed: [SEXP; 6],
    n_protected: c_int,
}

impl Walk {
    unsafe fn new(build: bool, ints: bool) -> Walk {
        let mut n_protected = 0;
        let mut protect = |s: SEXP| {
            n_protected += 1;
            Rf_protect(s)
        };
        let scratch = protect(Rf_allocVector(REALSXP, 0));
        let plain = protect(Rf_allocVector(REALSXP, 0));
        let classed = Kind::ALL.map(|k| {
            let v = protect(Rf_allocVector(REALSXP, 0));
            let cls = protect(Rf_allocVector(STRSXP, 3));
            for (i, s) in ["XY", k.name(), "sfg"].iter().enumerate() {
                let c = std::ffi::CString::new(*s).unwrap();
                SET_STRING_ELT(cls, i as isize, Rf_mkChar(c.as_ptr()));
            }
            Rf_setAttrib(v, R_ClassSymbol, cls);
            v
        });
        let build = build.then(Builder::new);
        Walk { bbox: Bbox::default(), build, ints, types: Vec::new(), scratch, plain, classed, n_protected }
    }

    /// True if the attributes of `x` other than names, dim and dimnames are
    /// exactly those of `like`.
    unsafe fn most_attributes_are(&self, x: SEXP, like: SEXP) -> bool {
        Rf_copyMostAttrib(x, self.scratch);
        let same = R_compute_identical(self.scratch, like, 0) != 0;
        if same {
            Rf_setAttrib(self.scratch, R_ClassSymbol, R_NilValue);
        }
        same
    }

    unsafe fn feature(&mut self, f: SEXP) -> bool {
        let Some(kind) = sfg_type(f) else { return false };
        let code = Kind::ALL.iter().position(|&k| k == kind).unwrap();
        if !self.most_attributes_are(f, self.classed[code]) || has_names(f) {
            return false;
        }
        self.types.push(code as i32 + 1);
        if let Some(b) = &mut self.build {
            b.feature(kind);
        }
        match kind {
            Kind::Point => {
                self.part();
                self.numeric(f) && XLENGTH(f) == 2 && is_null(Rf_getAttrib(f, R_DimSymbol)) && self.coords(f, Add::Ring)
            }
            Kind::MultiPoint => self.matrix(f, Add::Points),
            Kind::LineString => {
                self.part();
                self.matrix(f, Add::Ring)
            }
            Kind::MultiLineString => self.list(f, |w, m| {
                w.part();
                w.ring(m)
            }),
            Kind::Polygon => {
                self.part();
                self.list(f, |w, m| w.ring(m))
            }
            Kind::MultiPolygon => self.list(f, |w, p| {
                w.part();
                w.most_attributes_are(p, w.plain) && !has_names(p) && w.list(p, |w, m| w.ring(m))
            }),
        }
    }

    /// Starts a part of the feature being built.
    fn part(&mut self) {
        if let Some(b) = &mut self.build {
            b.part();
        }
    }

    /// A non-empty list with no names whose elements all pass `each`.
    unsafe fn list(&mut self, x: SEXP, mut each: impl FnMut(&mut Walk, SEXP) -> bool) -> bool {
        TYPEOF(x) == VECSXP
            && XLENGTH(x) > 0
            && is_null(Rf_getAttrib(x, R_DimSymbol))
            && (0..XLENGTH(x)).all(|i| each(self, VECTOR_ELT(x, i)))
    }

    /// A matrix inside a feature: no attributes but dim.
    unsafe fn ring(&mut self, m: SEXP) -> bool {
        self.most_attributes_are(m, self.plain) && self.matrix(m, Add::Ring)
    }

    /// An `n x 2` double matrix, n >= 1, without names or dimnames.
    unsafe fn matrix(&mut self, m: SEXP, add: Add) -> bool {
        if !self.numeric(m) || has_names(m) {
            return false;
        }
        let dim = Rf_getAttrib(m, R_DimSymbol);
        if TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 {
            return false;
        }
        let (nrow, ncol) = (*INTEGER(dim), *INTEGER(dim).add(1));
        nrow >= 1 && ncol == 2 && XLENGTH(m) == 2 * nrow as isize && self.coords(m, add)
    }

    /// A double vector, or an integer one when integers are read.
    unsafe fn numeric(&self, v: SEXP) -> bool {
        TYPEOF(v) == REALSXP || (self.ints && TYPEOF(v) == INTSXP)
    }

    /// Extends the bbox over the coordinates of `v` (borrowed, not copied
    /// out of R, unless integers, which are converted and decline at NA)
    /// and, when building, adds them to the current part.
    unsafe fn coords(&mut self, v: SEXP, add: Add) -> bool {
        let converted: Vec<f64>;
        let xy = if TYPEOF(v) == INTSXP {
            let ints = std::slice::from_raw_parts(INTEGER(v), XLENGTH(v) as usize);
            if ints.contains(&i32::MIN) {
                return false;
            }
            converted = ints.iter().map(|&i| i as f64).collect();
            &converted[..]
        } else {
            std::slice::from_raw_parts(REAL(v), XLENGTH(v) as usize)
        };
        self.bbox.extend(xy)
            && match (&mut self.build, add) {
                (None, _) => true,
                (Some(b), Add::Ring) => b.ring(xy),
                (Some(b), Add::Points) => b.points(xy),
            }
    }
}

/// How a matrix joins the geometry being built: as one ring of the current
/// part, or (a MULTIPOINT) as one part per row.
#[derive(Clone, Copy)]
enum Add {
    Ring,
    Points,
}

unsafe fn is_null(x: SEXP) -> bool {
    x == R_NilValue
}

unsafe fn has_names(x: SEXP) -> bool {
    !is_null(Rf_getAttrib(x, R_NamesSymbol)) || !is_null(Rf_getAttrib(x, R_DimNamesSymbol))
}

/// The kind of an sfg whose class is `c("XY", <type>, "sfg")`.
unsafe fn sfg_type(f: SEXP) -> Option<Kind> {
    let cls = Rf_getAttrib(f, R_ClassSymbol);
    if TYPEOF(cls) != STRSXP || XLENGTH(cls) != 3 {
        return None;
    }
    let s = |i| CStr::from_ptr(R_CHAR(STRING_ELT(cls, i))).to_bytes();
    if s(2) != b"sfg" {
        return None;
    }
    Kind::from_class(s(0), s(1))
}

extendr_module! {
    mod sf;
    fn sfc_plain_xy;
    fn sfc_render_types;
    fn sf_rescale01;
}
