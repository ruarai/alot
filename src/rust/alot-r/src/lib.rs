pub mod convert;
pub mod grouped;

use alot_core::group::{Columns, Values};
use alot_core::scale::range;
use convert::{ColumnData, ColumnsBuilder, Frame};
use extendr_api::prelude::*;

/// Train continuous ranges for `n` scales. `x` is a double or integer
/// vector, `scale_id` 1-based scale indices, `existing` a length-2n double
/// vector of current ranges (NaN pair for untrained). Returns a length-2n
/// double vector of new ranges, NA pairs for scales that saw no values.
/// @noRd
#[extendr(r_name = "rs_train_continuous_grouped")]
fn train_continuous_grouped(x: Robj, scale_id: &[i32], existing: &[f64]) -> extendr_api::Result<Doubles> {
    let n = existing.len() / 2;
    let ids: Vec<usize> = scale_id.iter().map(|&i| (i - 1) as usize).collect();
    if ids.iter().any(|&i| i >= n) {
        return Err(Error::Other("scale_id out of range".into()));
    }
    let existing: Vec<Option<[f64; 2]>> = existing
        .chunks_exact(2)
        .map(|r| if r[0].is_nan() { None } else { Some([r[0], r[1]]) })
        .collect();

    let out = if let Some(v) = x.as_real_slice() {
        range::train_continuous_grouped(v.iter().map(|&v| Some(v)), &ids, &existing)
    } else if let Some(v) = x.as_integer_slice() {
        let it = v.iter().map(|&v| (v != i32::MIN).then_some(v as f64));
        range::train_continuous_grouped(it, &ids, &existing)
    } else {
        return Err(Error::Other("x must be double or integer".into()));
    };

    Ok(out
        .into_iter()
        .flat_map(|r| match r {
            Some([l, h]) => [Rfloat::from(l), Rfloat::from(h)],
            None => [Rfloat::na(), Rfloat::na()],
        })
        .collect())
}

/// Round-trips the columns of `df` through the interchange layer, for
/// tests and benchmarks. With `copy = FALSE` every column passes through;
/// with `copy = TRUE` each atomic column is rebuilt from its view and given
/// the original's attributes. Returns a named list for `rebuild_frame()`.
/// @noRd
#[extendr(r_name = "rs_convert_roundtrip")]
fn convert_roundtrip(df: List, copy: bool) -> extendr_api::Result<List> {
    let frame = Frame::new(&df);
    let mut out = ColumnsBuilder::new();
    for (name, col) in frame.columns() {
        if !copy {
            out.push_column(name, &col);
            continue;
        }
        let rebuilt = match &col.data {
            ColumnData::Double(v) => convert::doubles(v.iter().map(|&x| Some(x))),
            ColumnData::Integer(v) => convert::integers(v.iter()),
            ColumnData::Logical(v) => convert::logicals(v.iter()),
            ColumnData::Factor(f) => convert::factor(f.codes.iter(), f.levels.clone())?,
            ColumnData::Character(s) => Strings::from_values(convert::str_iter(s)).into(),
            ColumnData::Other => {
                out.push_column(name, &col);
                continue;
            }
        };
        out.push(name, convert::with_attributes_of(rebuilt, col.robj));
    }
    out.finish()
}

/// Describes how the interchange layer reads each column of `df`: its kind
/// and the number of values its view reports as missing.
/// @noRd
#[extendr(r_name = "rs_convert_inspect")]
fn convert_inspect(df: List) -> extendr_api::Result<List> {
    let frame = Frame::new(&df);
    let mut kind = Vec::new();
    let mut n_na = Vec::new();
    for (_, col) in frame.columns() {
        kind.push(col.kind());
        n_na.push(match &col.data {
            ColumnData::Double(v) => v.iter().filter(|x| x.is_nan()).count(),
            ColumnData::Integer(v) => v.iter().filter(Option::is_none).count(),
            ColumnData::Logical(v) => v.iter().filter(Option::is_none).count(),
            ColumnData::Factor(f) => f.codes.iter().filter(Option::is_none).count(),
            ColumnData::Character(s) => convert::str_iter(s).filter(|x| x.is_na()).count(),
            ColumnData::Other => 0,
        } as i32);
    }
    let mut out = ColumnsBuilder::new();
    out.push("kind", Strings::from_values(kind));
    out.push("n_na", Integers::from_values(n_na));
    out.finish()
}

/// The group index of layer data `df` over `PANEL` x `group` (`PANEL`
/// only unless `by_group`), for tests: `list(order, offsets, panel)`, all
/// 1-based, or `NULL` where the driver would decline.
/// @noRd
#[extendr(r_name = "rs_group_index")]
fn group_index(df: List, by_group: bool) -> extendr_api::Result<Robj> {
    let Some(ix) = grouped::group_index(&Frame::new(&df), by_group) else { return Ok(().into()) };
    let one_based = |v: &[usize]| convert::integers(v.iter().map(|&i| Some(i as i32 + 1)));
    let mut out = ColumnsBuilder::new();
    out.push("order", one_based(&ix.order));
    out.push("offsets", convert::integers(ix.offsets.iter().map(|&i| Some(i as i32))));
    out.push("panel", one_based(&ix.panel));
    Ok(out.finish()?.into())
}

/// Identity-style stat kernel for testing the driver: per group, the double
/// columns `cols` unchanged plus `n`, the group size. `NULL` (decline) if a
/// column is missing or not double.
/// @noRd
#[extendr(r_name = "rs_grouped_test_stat")]
fn grouped_test_stat(df: List, cols: Strings) -> extendr_api::Result<Robj> {
    let frame = Frame::new(&df);
    let mut xs = Vec::new();
    for name in convert::str_iter(&cols) {
        match frame.get(name.as_ref()).map(|c| c.data) {
            Some(ColumnData::Double(v)) => xs.push((name.to_string(), v)),
            _ => return Ok(().into()),
        }
    }
    grouped::run_stat(&frame, |g| {
        let mut out = Columns::new();
        for (name, v) in &xs {
            out.push(name, Values::Double(g.rows.iter().map(|&r| Some(v[r])).collect()));
        }
        out.push("n", Values::Integer(vec![Some(g.rows.len() as i32); g.rows.len()]));
        out
    })
}

/// Position kernel for testing the driver: adds the panel's row count to
/// the double column `col`. `NULL` (decline) if `col` is not double.
/// @noRd
#[extendr(r_name = "rs_grouped_test_position")]
fn grouped_test_position(df: List, col: &str) -> extendr_api::Result<Robj> {
    let frame = Frame::new(&df);
    let Some(ColumnData::Double(v)) = frame.get(col).map(|c| c.data) else { return Ok(().into()) };
    grouped::run_position(&frame, |g| {
        let n = g.rows.len() as f64;
        let mut out = Columns::new();
        out.push(col, Values::Double(g.rows.iter().map(|&r| Some(v[r] + n)).collect()));
        out
    })
}

extendr_module! {
    mod alot;
    fn train_continuous_grouped;
    fn convert_roundtrip;
    fn convert_inspect;
    fn group_index;
    fn grouped_test_stat;
    fn grouped_test_position;
}
