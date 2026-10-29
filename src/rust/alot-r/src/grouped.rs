//! extendr glue for the grouped-kernel driver (`alot_core::group`). Builds
//! the group index from a layer's `PANEL` and `group` columns, runs a kernel
//! through `run_grouped()`, and returns the list that `R/grouped.R`
//! assembles into layer data.
use crate::convert::{self, ColumnData, ColumnsBuilder, Frame};
use alot_core::group::{self, Carry, Columns, Dbl, Exact, Group, GroupIndex, GroupedError, RowEq, Undecidable, Values};
use extendr_api::prelude::*;
use extendr_api::{Result, SEXP};

#[allow(improper_ctypes)] // SEXP is opaque, as in extendr-ffi.
extern "C" {
    // R API (Rinternals.h).
    fn STRING_PTR_RO(x: SEXP) -> *const SEXP;
    fn Rf_getCharCE(x: SEXP) -> i32;
    fn Rf_charIsASCII(x: SEXP) -> i32;
    static R_NaString: SEXP;
}

/// Group index over `PANEL` (and `group` when `by_group`), or `None` if
/// `PANEL` is not a factor, `group` is not an integer vector, or either
/// has missing values.
pub fn group_index(frame: &Frame, by_group: bool) -> Option<GroupIndex> {
    let panel = match frame.get("PANEL")?.data {
        ColumnData::Factor(f) => f.codes,
        _ => return None,
    };
    if !by_group {
        return GroupIndex::panels(panel.iter());
    }
    match frame.get("group")?.data {
        ColumnData::Integer(g) => GroupIndex::new(panel.iter(), Some(g.iter())),
        _ => None,
    }
}

/// Character equality as vctrs sees it. R caches CHARSXPs, so the same
/// bytes in the same encoding share a pointer. Different pointers are
/// unequal unless the two differ in encoding and are both non-ASCII; vctrs
/// would translate those, so they are undecidable.
struct StrEq<'a>(&'a [SEXP]);

impl RowEq for StrEq<'_> {
    fn row_eq(&self, i: usize, j: usize) -> Option<bool> {
        let (a, b) = (self.0[i], self.0[j]);
        unsafe {
            if a == b {
                Some(true)
            } else if a == R_NaString
                || b == R_NaString
                || Rf_getCharCE(a) == Rf_getCharCE(b)
                || Rf_charIsASCII(a) != 0
                || Rf_charIsASCII(b) != 0
            {
                Some(false)
            } else {
                None
            }
        }
    }
}

fn row_eq<'b>(data: &'b ColumnData<'_>) -> Box<dyn RowEq + 'b> {
    match data {
        ColumnData::Double(v) => Box::new(Dbl(v)),
        ColumnData::Integer(v) => Box::new(Exact(v.0)),
        ColumnData::Logical(v) => Box::new(Exact(v.0)),
        ColumnData::Factor(f) => Box::new(Exact(f.codes.0)),
        // The slice borrows R's memory for as long as `data` holds the vector.
        ColumnData::Character(s) if s.len() > 0 => {
            Box::new(StrEq(unsafe { std::slice::from_raw_parts(STRING_PTR_RO(s.get()), s.len()) }))
        }
        ColumnData::Character(_) => Box::new(StrEq(&[])),
        ColumnData::Other => Box::new(Undecidable),
    }
}

/// Converts kernel output to an R vector (no attributes).
pub fn values_robj(values: Values) -> Robj {
    match values {
        Values::Double(v) => convert::doubles(v.into_iter()),
        Values::Integer(v) => convert::integers(v.into_iter()),
        Values::Logical(v) => convert::logicals(v.into_iter()),
    }
}

fn columns_list(columns: Columns) -> Result<List> {
    let mut out = ColumnsBuilder::new();
    for (name, values) in columns.names.iter().zip(columns.values) {
        out.push(name, values_robj(values));
    }
    out.finish()
}

fn index_r(rows: impl ExactSizeIterator<Item = usize>) -> Robj {
    convert::integers(rows.map(|r| Some(r as i32 + 1)))
}

/// Runs a stat kernel once per `PANEL` × `group`, carrying every column of
/// `frame` as `Stat$compute_panel` does. Returns `NULL` to decline (no
/// usable index, or a carry column that cannot be compared), else
/// `list(new, carry, panel_rows, panel_groups, non_constant)` for
/// `stat_compute_grouped()`: the concatenated kernel output; per output row,
/// the 1-based input row whose carried values it takes; output rows and
/// groups with output per panel; and, per panel and then per input column,
/// whether that column is dropped in the panel.
pub fn run_stat<F>(frame: &Frame, kernel: F) -> Result<Robj>
where
    F: FnMut(Group) -> Columns,
{
    let Some(index) = group_index(frame, true) else { return Ok(().into()) };
    let cols: Vec<_> = frame.columns().collect();
    let eqs: Vec<_> = cols.iter().map(|(_, c)| row_eq(&c.data)).collect();
    let carry: Vec<Carry> = cols.iter().zip(&eqs).map(|((name, _), eq)| Carry { name, eq: eq.as_ref() }).collect();

    let out = match group::run_grouped(&index, &carry, kernel) {
        Ok(out) => out,
        Err(GroupedError::Undecidable(_)) => return Ok(().into()),
        Err(GroupedError::Mismatch(msg)) => return Err(Error::Other(msg)),
    };

    let panel_rows = out.panels.iter().map(|p| Some(p.n_rows as i32));
    let panel_groups = out.panels.iter().map(|p| Some(p.n_groups as i32));
    let non_constant = out.panels.iter().flat_map(|p| p.non_constant.iter().map(|&b| Some(b)));
    let mut res = ColumnsBuilder::new();
    res.push("new", columns_list(out.columns)?);
    res.push("carry", index_r(out.carry_rows.into_iter()));
    res.push("panel_rows", convert::integers(panel_rows.collect::<Vec<_>>().into_iter()));
    res.push("panel_groups", convert::integers(panel_groups.collect::<Vec<_>>().into_iter()));
    res.push("non_constant", convert::logicals(non_constant.collect::<Vec<_>>().into_iter()));
    Ok(res.finish()?.into())
}

/// Runs a position kernel once per panel, as `Position$compute_layer`
/// does. The kernel must return one row per input row of the panel, in
/// the panel's row order. Returns `NULL` to decline, else
/// `list(new, rows, panel_rows)` for `position_compute_grouped()`: the
/// kernel output, the 1-based input row of each output row, and the rows
/// per panel.
pub fn run_position<F>(frame: &Frame, kernel: F) -> Result<Robj>
where
    F: FnMut(Group) -> Columns,
{
    let Some(index) = group_index(frame, false) else { return Ok(().into()) };
    let mut sizes_ok = true;
    let mut kernel = kernel;
    let out = group::run_grouped(&index, &[], |g| {
        let n = g.rows.len();
        let out = kernel(g);
        sizes_ok &= out.n_rows() == n;
        out
    })
    .map_err(|e| Error::Other(format!("{e:?}")))?;
    if !sizes_ok {
        return Err(Error::Other("position kernel must return one row per input row".into()));
    }

    let mut res = ColumnsBuilder::new();
    res.push("new", columns_list(out.columns)?);
    res.push("rows", index_r(index.order.into_iter()));
    res.push("panel_rows", convert::integers(out.panels.iter().map(|p| Some(p.n_rows as i32))));
    Ok(res.finish()?.into())
}
