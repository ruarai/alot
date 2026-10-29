//! Data interchange between R layer data and Rust kernels.
//!
//! Columns are read as borrowed views over R's memory, so numeric input is
//! never copied (ALTREP vectors are materialised in place, once, by R).
//! Kernels hand results back through `ColumnsBuilder`, a named list that
//! `rebuild_frame()` (R/convert.R) turns into a data frame.
use extendr_api::prelude::*;
use extendr_api::{Result, SEXP};

#[allow(improper_ctypes)] // SEXP is opaque, as in extendr-ffi.
extern "C" {
    // R API (Rinternals.h): copies all attributes except names, dim and
    // dimnames.
    fn Rf_copyMostAttrib(from: SEXP, to: SEXP);
    // R API (Rinternals.h): copies all attributes.
    fn SHALLOW_DUPLICATE_ATTRIB(to: SEXP, from: SEXP);
}

/// Integer view; `NA_integer_` reads as `None`.
#[derive(Clone, Copy)]
pub struct IntView<'a>(pub &'a [i32]);

impl IntView<'_> {
    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn get(&self, i: usize) -> Option<i32> {
        let v = self.0[i];
        (v != i32::MIN).then_some(v)
    }

    pub fn iter(&self) -> impl ExactSizeIterator<Item = Option<i32>> + '_ {
        self.0.iter().map(|&v| (v != i32::MIN).then_some(v))
    }
}

/// Logical view; `NA` reads as `None`.
#[derive(Clone, Copy)]
pub struct LglView<'a>(pub &'a [Rbool]);

impl LglView<'_> {
    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn get(&self, i: usize) -> Option<bool> {
        self.0[i].into()
    }

    pub fn iter(&self) -> impl ExactSizeIterator<Item = Option<bool>> + '_ {
        self.0.iter().map(|&v| v.into())
    }
}

/// A factor: 1-based codes plus its levels (iterate them with `str_iter`).
#[derive(Clone)]
pub struct Factor<'a> {
    pub codes: IntView<'a>,
    pub levels: Strings,
}

/// The data of one column. Anything that is not an atomic type a kernel
/// reads (list columns, complex, raw) is `Other` and only passes through.
#[derive(Clone)]
pub enum ColumnData<'a> {
    Double(&'a [f64]),
    Integer(IntView<'a>),
    Logical(LglView<'a>),
    Factor(Factor<'a>),
    /// Iterate with `str_iter`.
    Character(Strings),
    Other,
}

/// A column view plus the R object it borrows from. Classes such as `Date`,
/// `POSIXct` and `mapped_discrete` stay on `robj`; the view only sees the
/// underlying storage.
#[derive(Clone)]
pub struct Column<'a> {
    pub robj: &'a Robj,
    pub data: ColumnData<'a>,
}

// R gives empty vectors a dummy data pointer that `slice::from_raw_parts`
// rejects, so empty vectors get an empty slice instead.
fn nonempty<'a, T>(robj: &Robj, slice: Option<&'a [T]>) -> Option<&'a [T]> {
    if robj.len() == 0 {
        Some(&[])
    } else {
        slice
    }
}

/// Iterates a character vector element by element. Use this rather than
/// `Strings::iter()`, which takes a slice and so fails on empty vectors.
pub fn str_iter(s: &Strings) -> impl ExactSizeIterator<Item = Rstr> + '_ {
    (0..s.len()).map(|i| s.elt(i))
}

impl<'a> Column<'a> {
    pub fn new(robj: &'a Robj) -> Self {
        let data = if robj.inherits("factor") {
            match (nonempty(robj, robj.as_integer_slice()), robj.get_attrib("levels").map(Strings::try_from)) {
                (Some(codes), Some(Ok(levels))) => ColumnData::Factor(Factor { codes: IntView(codes), levels }),
                _ => ColumnData::Other,
            }
        } else {
            match robj.rtype() {
                Rtype::Doubles => ColumnData::Double(nonempty(robj, robj.as_real_slice()).unwrap()),
                Rtype::Integers => ColumnData::Integer(IntView(nonempty(robj, robj.as_integer_slice()).unwrap())),
                Rtype::Logicals => ColumnData::Logical(LglView(nonempty(robj, robj.as_logical_slice()).unwrap())),
                Rtype::Strings => ColumnData::Character(Strings::try_from(robj.clone()).unwrap()),
                _ => ColumnData::Other,
            }
        };
        Column { robj, data }
    }

    pub fn len(&self) -> usize {
        self.robj.len()
    }

    pub fn kind(&self) -> &'static str {
        match self.data {
            ColumnData::Double(_) => "double",
            ColumnData::Integer(_) => "integer",
            ColumnData::Logical(_) => "logical",
            ColumnData::Factor(_) => "factor",
            ColumnData::Character(_) => "character",
            ColumnData::Other => "other",
        }
    }
}

/// The columns of a data frame (or any named list of vectors).
pub struct Frame {
    names: Vec<String>,
    cols: Vec<Robj>,
}

impl Frame {
    pub fn new(df: &List) -> Self {
        let names = match df.names() {
            Some(n) => n.map(String::from).collect(),
            None => vec![String::new(); df.len()],
        };
        Frame { names, cols: df.values().collect() }
    }

    pub fn names(&self) -> &[String] {
        &self.names
    }

    pub fn column(&self, i: usize) -> Column<'_> {
        Column::new(&self.cols[i])
    }

    pub fn get(&self, name: &str) -> Option<Column<'_>> {
        self.names.iter().position(|n| n == name).map(|i| self.column(i))
    }

    pub fn columns(&self) -> impl Iterator<Item = (&str, Column<'_>)> {
        self.names.iter().map(String::as_str).zip(self.cols.iter().map(Column::new))
    }
}

/// New double vector; `None` becomes `NA_real_`.
pub fn doubles(values: impl ExactSizeIterator<Item = Option<f64>>) -> Robj {
    let mut out = Doubles::new(values.len());
    for (d, v) in out.iter_mut().zip(values) {
        *d = v.map_or(Rfloat::na(), Rfloat::from);
    }
    out.into()
}

/// New integer vector; `None` becomes `NA_integer_`.
pub fn integers(values: impl ExactSizeIterator<Item = Option<i32>>) -> Robj {
    let mut out = Integers::new(values.len());
    for (d, v) in out.iter_mut().zip(values) {
        *d = Rint::from(v);
    }
    out.into()
}

/// New logical vector; `None` becomes `NA`.
pub fn logicals(values: impl ExactSizeIterator<Item = Option<bool>>) -> Robj {
    let mut out = Logicals::new(values.len());
    for (d, v) in out.iter_mut().zip(values) {
        *d = Rbool::from(v);
    }
    out.into()
}

/// New unordered factor from 1-based codes and levels.
pub fn factor(codes: impl ExactSizeIterator<Item = Option<i32>>, levels: Strings) -> Result<Robj> {
    let mut out = integers(codes);
    out.set_attrib("levels", levels)?;
    out.set_class(["factor"])?;
    Ok(out)
}

/// Copies the attributes of `like` (class, levels, tzone, ...) onto `x`.
/// When the lengths agree that is every attribute, so 1-d arrays (ggplot2's
/// `tapply()` results) and names survive; otherwise all but names, dim and
/// dimnames, as R's `copyMostAttrib()`. The caller must make sure the
/// storage types agree.
pub fn with_attributes_of(mut x: Robj, like: &Robj) -> Robj {
    unsafe {
        if x.len() == like.len() {
            SHALLOW_DUPLICATE_ATTRIB(x.get_mut(), like.get());
        } else {
            Rf_copyMostAttrib(like.get(), x.get_mut());
        }
    }
    x
}

/// Collects named output columns. `finish()` returns the named list that
/// `rebuild_frame()` expects.
#[derive(Default)]
pub struct ColumnsBuilder {
    names: Vec<String>,
    values: Vec<Robj>,
}

impl ColumnsBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, name: &str, value: impl Into<Robj>) -> &mut Self {
        self.names.push(name.to_string());
        self.values.push(value.into());
        self
    }

    /// Passes an input column through untouched (no copy).
    pub fn push_column(&mut self, name: &str, col: &Column) -> &mut Self {
        self.push(name, col.robj.clone())
    }

    pub fn finish(self) -> Result<List> {
        List::from_names_and_values(self.names, self.values)
    }
}
