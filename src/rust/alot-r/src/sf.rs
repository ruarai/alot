//! Reads sf geometry columns (sfc lists) for R/sf.R.
use alot_core::sf::Bbox;
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

/// The sfg types read, in the order of their 1-based codes.
const TYPES: [&str; 6] = ["POINT", "MULTIPOINT", "LINESTRING", "MULTILINESTRING", "POLYGON", "MULTIPOLYGON"];

/// Walks the features of an sfc. Returns `list(bbox = c(xmin, ymin, xmax,
/// ymax), types = <1-based code per feature into TYPES>)`, or NULL unless
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
        let mut walk = Walk::new();
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

struct Walk {
    bbox: Bbox,
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
    unsafe fn new() -> Walk {
        let mut n_protected = 0;
        let mut protect = |s: SEXP| {
            n_protected += 1;
            Rf_protect(s)
        };
        let scratch = protect(Rf_allocVector(REALSXP, 0));
        let plain = protect(Rf_allocVector(REALSXP, 0));
        let classed = TYPES.map(|t| {
            let v = protect(Rf_allocVector(REALSXP, 0));
            let cls = protect(Rf_allocVector(STRSXP, 3));
            for (i, s) in ["XY", t, "sfg"].iter().enumerate() {
                let c = std::ffi::CString::new(*s).unwrap();
                SET_STRING_ELT(cls, i as isize, Rf_mkChar(c.as_ptr()));
            }
            Rf_setAttrib(v, R_ClassSymbol, cls);
            v
        });
        Walk { bbox: Bbox::default(), types: Vec::new(), scratch, plain, classed, n_protected }
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
        let Some(code) = sfg_type(f) else { return false };
        if !self.most_attributes_are(f, self.classed[code]) || has_names(f) {
            return false;
        }
        self.types.push(code as i32 + 1);
        match TYPES[code] {
            "POINT" => TYPEOF(f) == REALSXP && XLENGTH(f) == 2 && is_null(Rf_getAttrib(f, R_DimSymbol)) && self.coords(f),
            "MULTIPOINT" | "LINESTRING" => self.matrix(f),
            "MULTILINESTRING" | "POLYGON" => self.list(f, |w, m| w.ring(m)),
            _ => self.list(f, |w, p| w.most_attributes_are(p, w.plain) && !has_names(p) && w.list(p, |w, m| w.ring(m))),
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
        self.most_attributes_are(m, self.plain) && self.matrix(m)
    }

    /// An `n x 2` double matrix, n >= 1, without names or dimnames.
    unsafe fn matrix(&mut self, m: SEXP) -> bool {
        if TYPEOF(m) != REALSXP || has_names(m) {
            return false;
        }
        let dim = Rf_getAttrib(m, R_DimSymbol);
        if TYPEOF(dim) != INTSXP || XLENGTH(dim) != 2 {
            return false;
        }
        let (nrow, ncol) = (*INTEGER(dim), *INTEGER(dim).add(1));
        nrow >= 1 && ncol == 2 && XLENGTH(m) == 2 * nrow as isize && self.coords(m)
    }

    unsafe fn coords(&mut self, v: SEXP) -> bool {
        let xy = std::slice::from_raw_parts(REAL(v), XLENGTH(v) as usize);
        self.bbox.extend(xy)
    }
}

unsafe fn is_null(x: SEXP) -> bool {
    x == R_NilValue
}

unsafe fn has_names(x: SEXP) -> bool {
    !is_null(Rf_getAttrib(x, R_NamesSymbol)) || !is_null(Rf_getAttrib(x, R_DimNamesSymbol))
}

/// The index into TYPES of an sfg whose class is `c("XY", <type>, "sfg")`.
unsafe fn sfg_type(f: SEXP) -> Option<usize> {
    let cls = Rf_getAttrib(f, R_ClassSymbol);
    if TYPEOF(cls) != STRSXP || XLENGTH(cls) != 3 {
        return None;
    }
    let s = |i| CStr::from_ptr(R_CHAR(STRING_ELT(cls, i))).to_bytes();
    if s(0) != b"XY" || s(2) != b"sfg" {
        return None;
    }
    TYPES.iter().position(|t| t.as_bytes() == s(1))
}

extendr_module! {
    mod sf;
    fn sfc_plain_xy;
}
