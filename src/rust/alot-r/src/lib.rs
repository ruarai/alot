pub mod convert;
pub mod grouped;
pub mod layout;
pub mod render;
pub mod text;

use alot_core::colour::ramp::{self, Approx, Ramp};
use alot_core::breaks::{extended, fmod};
use alot_core::colour::{hex, lab};
use alot_core::facet;
use alot_core::group::{Columns, Values};
use alot_core::scale::map::{self, Oob, Rescale};
use alot_core::scale::transform::{self, Transform};
use alot_core::scale::{discrete, range};
use convert::{Column, ColumnData, ColumnsBuilder, Frame, IntView};
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
        range::train_continuous_grouped(v.iter().map(|&v| Some(v)), ids.iter().copied(), &existing)
    } else if let Some(v) = x.as_integer_slice() {
        let it = v.iter().map(|&v| (v != i32::MIN).then_some(v as f64));
        range::train_continuous_grouped(it, ids.iter().copied(), &existing)
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

/// Trains one continuous range on double or integer `x`, as
/// `scales::train_continuous()`: `existing` is the current range (a NaN
/// pair for none). Returns the new range, an NA pair for empty `x`.
/// @noRd
#[extendr(r_name = "rs_train_continuous")]
fn train_continuous(x: Robj, existing: &[f64]) -> extendr_api::Result<Doubles> {
    let existing = match existing {
        [l, _] if l.is_nan() => None,
        &[l, h] => Some([l, h]),
        _ => return Err(Error::Other("existing must have length 2".into())),
    };
    let ids = std::iter::repeat(0);
    let out = match Column::new(&x).data {
        ColumnData::Double(v) => range::train_continuous_grouped(v.iter().map(|&v| Some(v)), ids, &[existing]),
        ColumnData::Integer(v) => range::train_continuous_grouped(v.iter().map(|v| v.map(f64::from)), ids, &[existing]),
        _ => return Err(Error::Other("x must be double or integer".into())),
    };
    Ok(match out[0] {
        Some([l, h]) => Doubles::from_values([l, h]),
        None => Doubles::from_values([Rfloat::na(), Rfloat::na()]),
    })
}

/// Rows that train a discrete position scale exactly as its whole slice
/// does (see `alot_core::scale::discrete`): for factor, character and
/// logical `x`, the first row of each distinct value per scale; for double
/// or integer `x` (trained into `range_c`), the rows of the smallest and
/// largest finite value. `scale_id` holds 1-based scale indices. Returns
/// `list(rows, offsets)`: 1-based rows, scale `i`'s are
/// `rows[(offsets[i] + 1):offsets[i + 1]]`. `NULL` (decline) for any other
/// input, or a factor with codes outside its levels.
/// @noRd
#[extendr(r_name = "rs_train_discrete_rows")]
fn train_discrete_rows(x: Robj, scale_id: &[i32], n_scales: i32) -> extendr_api::Result<Robj> {
    let n = n_scales as usize;
    let ids: Vec<usize> = scale_id.iter().map(|&i| (i - 1) as usize).collect();
    if ids.iter().any(|&i| i >= n) {
        return Err(Error::Other("scale_id out of range".into()));
    }

    let rows = match Column::new(&x).data {
        ColumnData::Factor(f) => {
            let k = f.levels.len();
            if f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c as usize > k)) {
                return Ok(().into());
            }
            let keys = f.codes.iter().map(|c| c.map_or(k, |c| c as usize - 1));
            discrete::first_occurrences_dense(keys, k + 1, ids.iter().copied(), n)
        }
        ColumnData::Logical(v) => {
            let keys = v.iter().map(|b| b.map_or(2, usize::from));
            discrete::first_occurrences_dense(keys, 3, ids.iter().copied(), n)
        }
        ColumnData::Character(s) => {
            let keys = convert::str_ptrs(&s).iter().map(|&p| p as usize);
            discrete::first_occurrences(keys, ids.iter().copied(), n)
        }
        ColumnData::Double(v) => discrete::extremes(v.iter().map(|&v| Some(v)), &ids, n),
        ColumnData::Integer(v) => discrete::extremes(v.iter().map(|v| v.map(f64::from)), &ids, n),
        ColumnData::Other => return Ok(().into()),
    };

    let mut offsets = Vec::with_capacity(n + 1);
    offsets.push(Some(0));
    let mut total = 0;
    for r in &rows {
        total += r.len() as i32;
        offsets.push(Some(total));
    }
    let flat = rows.iter().flatten().map(|&i| Some(i as i32 + 1));
    let mut out = ColumnsBuilder::new();
    out.push("rows", convert::integers(flat.collect::<Vec<_>>().into_iter()));
    out.push("offsets", convert::integers(offsets.into_iter()));
    Ok(out.finish()?.into())
}

/// The first row of each distinct value of factor, character or logical
/// `x`, for training a discrete non-position scale on (see
/// `alot_core::scale::discrete`): 1-based and ascending. `NULL` (decline)
/// for any other input, or a factor with codes outside its levels.
/// @noRd
#[extendr(r_name = "rs_discrete_first_rows")]
fn discrete_first_rows(x: Robj) -> extendr_api::Result<Robj> {
    let col = Column::new(&x);
    let one = std::iter::repeat(0).take(col.len());
    let rows = match col.data {
        ColumnData::Factor(f) => {
            let k = f.levels.len();
            if f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c as usize > k)) {
                return Ok(().into());
            }
            let keys = f.codes.iter().map(|c| c.map_or(k, |c| c as usize - 1));
            discrete::first_occurrences_dense(keys, k + 1, one, 1)
        }
        ColumnData::Logical(v) => {
            let keys = v.iter().map(|b| b.map_or(2, usize::from));
            discrete::first_occurrences_dense(keys, 3, one, 1)
        }
        ColumnData::Character(s) => {
            let keys = convert::str_ptrs(&s).iter().map(|&p| p as usize);
            discrete::first_occurrences(keys, one, 1)
        }
        _ => return Ok(().into()),
    };
    Ok(convert::integers(rows[0].iter().map(|&i| Some(i as i32 + 1))))
}

/// `table[k]` for each row key `k`, as a new vector of `table`'s type
/// (character, double, integer or logical, without attributes). Keys as
/// for `rs_map_discrete()`: a factor's codes with NA last (`table` must
/// have its levels plus one elements), a logical's FALSE, TRUE, NA, or the
/// 1-based codes of `rs_factorize_strings()`. `NULL` (decline) for a key
/// outside the table or any other input or table type.
/// @noRd
#[extendr(r_name = "rs_lookup_discrete")]
fn lookup_discrete(x: Robj, table: Robj) -> extendr_api::Result<Robj> {
    let k = table.len();
    let col = Column::new(&x);
    let n = col.len();
    match col.data {
        ColumnData::Factor(f) => {
            if f.levels.len() + 1 != k || f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c as usize >= k)) {
                return Ok(().into());
            }
            gather(f.codes.iter().map(|c| c.map_or(k - 1, |c| c as usize - 1)), n, &table)
        }
        ColumnData::Logical(v) => {
            if k != 3 {
                return Ok(().into());
            }
            gather(v.iter().map(|b| b.map_or(2, usize::from)), n, &table)
        }
        ColumnData::Integer(v) => {
            if v.iter().any(|c| c.map_or(true, |c| c < 1 || c as usize > k)) {
                return Ok(().into());
            }
            gather(v.0.iter().map(|&c| c as usize - 1), n, &table)
        }
        _ => Ok(().into()),
    }
}

/// `n` values of `table` picked by `keys`, which must index it.
fn gather(keys: impl Iterator<Item = usize>, n: usize, table: &Robj) -> extendr_api::Result<Robj> {
    if table.get_attrib("names").is_some() || table.class().is_some() {
        return Ok(().into());
    }
    // R gives empty vectors no slice; see `convert::nonempty`.
    if n == 0 {
        return Ok(match table.rtype() {
            Rtype::Strings => Strings::new(0).into(),
            Rtype::Doubles => Doubles::new(0).into(),
            Rtype::Integers => Integers::new(0).into(),
            Rtype::Logicals => Logicals::new(0).into(),
            _ => ().into(),
        });
    }
    Ok(match table.rtype() {
        Rtype::Strings => convert::gathered_strings(&Strings::try_from(table.clone())?, keys, n),
        Rtype::Doubles => {
            let t = table.as_real_slice().unwrap();
            new_doubles(n, |out| discrete::lookup(keys, t, out))
        }
        Rtype::Integers => {
            let t = table.as_integer_slice().unwrap();
            let mut out: Robj = Integers::new(n).into();
            discrete::lookup(keys, t, out.as_integer_slice_mut().unwrap());
            out
        }
        Rtype::Logicals => {
            let t = table.as_logical_slice().unwrap();
            let mut out = Logicals::new(n);
            discrete::lookup(keys, t, &mut out);
            out.into()
        }
        _ => ().into(),
    })
}

/// 0-based scale per row from 1-based `scale_id`, after checking every id
/// is in `1..=n`.
fn scale_index(scale_id: &[i32], n: usize) -> extendr_api::Result<impl Iterator<Item = usize> + '_> {
    if scale_id.iter().any(|&i| i < 1 || i as usize > n) {
        return Err(Error::Other("scale_id out of range".into()));
    }
    Ok(scale_id.iter().map(|&i| (i - 1) as usize))
}

/// A new double vector of length `n`, filled by `fill`.
fn new_doubles(n: usize, fill: impl FnOnce(&mut [f64])) -> Robj {
    let mut out: Robj = Doubles::new(n).into();
    if n > 0 {
        fill(out.as_real_slice_mut().unwrap());
    }
    out
}

/// Maps double or integer `x` onto continuous position scales (see
/// `alot_core::scale::map`). `limits` holds each scale's limits as a
/// length-2n vector, `oob` is 0 (censor), 1 (squish), 2 (squish_infinite)
/// or 3 (keep), and `na_value` a length-1 double copied bit for bit.
/// @noRd
#[extendr(r_name = "rs_map_continuous")]
fn map_continuous(x: Robj, scale_id: &[i32], limits: &[f64], oob: i32, only_finite: bool, na_value: &[f64]) -> extendr_api::Result<Robj> {
    let limits: Vec<[f64; 2]> = limits.chunks_exact(2).map(|r| [r[0], r[1]]).collect();
    let ids = scale_index(scale_id, limits.len())?;
    let oob = match oob {
        0 => Oob::Censor { only_finite },
        1 => Oob::Squish { only_finite },
        2 => Oob::SquishInfinite,
        3 => Oob::Keep,
        _ => return Err(Error::Other("unknown oob".into())),
    };
    let na = na_value[0];
    let col = Column::new(&x);
    if col.len() != scale_id.len() {
        return Err(Error::Other("x and scale_id differ in length".into()));
    }
    Ok(match col.data {
        ColumnData::Double(v) => new_doubles(v.len(), |out| {
            map::map_continuous(v.iter().map(|&v| Some(v)), ids, &limits, oob, na, out)
        }),
        ColumnData::Integer(v) => new_doubles(v.len(), |out| {
            map::map_continuous(v.iter().map(|v| v.map(f64::from)), ids, &limits, oob, na, out)
        }),
        _ => return Err(Error::Other("x must be double or integer".into())),
    })
}

/// Codes a character vector by CHARSXP pointer in order of first
/// appearance: `list(codes, rows)`, both 1-based, where `rows[k]` is the
/// first row with code `k`. Strings that are equal but differently encoded
/// get separate codes; R's `match()` on `x[rows]` resolves them.
/// @noRd
#[extendr(r_name = "rs_factorize_strings")]
fn factorize_strings(x: Strings) -> extendr_api::Result<List> {
    let (codes, first) = map::factorize(convert::str_ptrs(&x).iter().map(|&p| p as usize));
    let one_based = |v: Vec<usize>| convert::integers(v.into_iter().map(|i| Some(i as i32 + 1)));
    let mut out = ColumnsBuilder::new();
    out.push("codes", one_based(codes));
    out.push("rows", one_based(first));
    out.finish()
}

/// Maps discrete `x` onto position scales through `table`, the column-major
/// `n_keys` x n-scales matrix of mapped values R computed from each scale's
/// limits and palette. Keys: a factor's codes with NA last (`n_keys` must
/// be its levels plus one); for a logical FALSE, TRUE, NA; for an integer
/// vector the 1-based codes of `rs_factorize_strings()`. Returns a double
/// vector, or `NULL` (decline) for a key outside the table.
/// @noRd
#[extendr(r_name = "rs_map_discrete")]
fn map_discrete(x: Robj, scale_id: &[i32], table: &[f64], n_keys: i32) -> extendr_api::Result<Robj> {
    let k = n_keys as usize;
    if k == 0 || table.len() % k != 0 {
        return Err(Error::Other("table must have n_keys rows".into()));
    }
    let ids = scale_index(scale_id, table.len() / k)?;
    let col = Column::new(&x);
    if col.len() != scale_id.len() {
        return Err(Error::Other("x and scale_id differ in length".into()));
    }
    let n = col.len();
    Ok(match col.data {
        ColumnData::Factor(f) => {
            if f.levels.len() + 1 != k || f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c as usize >= k)) {
                return Ok(().into());
            }
            let keys = f.codes.iter().map(|c| c.map_or(k - 1, |c| c as usize - 1));
            new_doubles(n, |out| map::map_discrete(keys, ids, table, k, out))
        }
        ColumnData::Logical(v) => {
            if k != 3 {
                return Ok(().into());
            }
            let keys = v.iter().map(|b| b.map_or(2, usize::from));
            new_doubles(n, |out| map::map_discrete(keys, ids, table, k, out))
        }
        ColumnData::Integer(v) => {
            if v.iter().any(|c| c.map_or(true, |c| c < 1 || c as usize > k)) {
                return Ok(().into());
            }
            let keys = v.0.iter().map(|&c| c as usize - 1);
            new_doubles(n, |out| map::map_discrete(keys, ids, table, k, out))
        }
        _ => return Ok(().into()),
    })
}

/// Transforms double or integer `x` for a continuous scale (see
/// `alot_core::scale::transform`); `code` is 0 (log10), 1 (sqrt) or 2
/// (reverse). Returns `list(x, nan, finite)`: the new vector (integer for
/// reverse on integer input, else double) and the 1-based first rows where
/// R would warn "NaNs produced" and `check_transformation()` would warn, 0
/// for none. `NULL` (decline) for any other input type.
/// @noRd
#[extendr(r_name = "rs_transform")]
fn transform_values(x: Robj, code: i32) -> extendr_api::Result<Robj> {
    let t = match code {
        0 => Transform::Log10,
        1 => Transform::Sqrt,
        2 => Transform::Reverse,
        _ => return Err(Error::Other("unknown transform".into())),
    };
    let col = Column::new(&x);
    let n = col.len();
    let mut report = transform::Report::default();
    let values = match col.data {
        ColumnData::Double(v) => new_doubles(n, |out| report = transform::transform(v.iter().copied(), t, out)),
        ColumnData::Integer(v) if t == Transform::Reverse => {
            let mut out: Robj = Integers::new(n).into();
            if n > 0 {
                transform::reverse_integers(v.iter(), out.as_integer_slice_mut().unwrap());
            }
            out
        }
        ColumnData::Integer(v) => {
            let it = v.iter().map(|v| v.map_or(transform::NA_REAL, f64::from));
            new_doubles(n, |out| report = transform::transform(it, t, out))
        }
        _ => return Ok(().into()),
    };
    let row = |i: Option<usize>| Integers::from_values([i.map_or(0, |i| i as i32 + 1)]);
    let mut out = ColumnsBuilder::new();
    out.push("x", values);
    out.push("nan", row(report.nan_produced));
    out.push("finite", row(report.finite_changed));
    Ok(out.finish()?.into())
}

/// An `approxfun()`'s knots from `list(x, y, yleft, yright)`.
fn approx_from(knots: &Robj) -> extendr_api::Result<Approx> {
    let bad = || Error::Other("knots must be list(x, y, yleft, yright) of doubles".into());
    let list = List::try_from(knots.clone()).map_err(|_| bad())?;
    let get = |name: &str| -> extendr_api::Result<Vec<f64>> {
        let v = list.dollar(name).map_err(|_| bad())?;
        if v.len() == 0 {
            return Ok(Vec::new());
        }
        v.as_real_slice().map(<[f64]>::to_vec).ok_or_else(bad)
    };
    let (x, y, yleft, yright) = (get("x")?, get("y")?, get("yleft")?, get("yright")?);
    if x.len() != y.len() || yleft.len() != 1 || yright.len() != 1 {
        return Err(bad());
    }
    Ok(Approx { x, y, yleft: yleft[0], yright: yright[0] })
}

/// Maps double or integer `x` onto colours through a continuous scale with
/// a `pal_gradient_n()` palette (see `alot_core::colour::ramp`). `oob` and
/// `only_finite` as for `rs_map_continuous()`, `limits` the scale's limits;
/// `rescale` is 0 (`rescale()`, `par` unused), 1 (`rescale_mid()`, `par`
/// = `c(mid, extent)`) or 2 (`zero_range(limits)`). `ramp` is
/// `list(values, l, a, b, alpha)` of knot lists (`values` and `alpha` may
/// be `NULL`), and `na_value` a length-1 character vector for NA results.
/// @noRd
#[extendr(r_name = "rs_map_colour")]
#[allow(clippy::too_many_arguments)]
fn map_colour(x: Robj, limits: &[f64], oob: i32, only_finite: bool, rescale: i32, par: &[f64], ramp: List, na_value: Strings) -> extendr_api::Result<Robj> {
    let limits: [f64; 2] = limits.try_into().map_err(|_| Error::Other("limits must have length 2".into()))?;
    let oob = match oob {
        0 => Oob::Censor { only_finite },
        1 => Oob::Squish { only_finite },
        2 => Oob::SquishInfinite,
        3 => Oob::Keep,
        _ => return Err(Error::Other("unknown oob".into())),
    };
    let rescale = match (rescale, par) {
        (0, _) => Rescale::Linear { from: limits },
        (1, &[mid, extent]) => Rescale::Mid { mid, extent },
        (2, _) => Rescale::Zero,
        _ => return Err(Error::Other("unknown rescale".into())),
    };
    let part = |name: &str| ramp.dollar(name).map_err(|_| Error::Other(format!("ramp has no {name}")));
    let optional = |name: &str| -> extendr_api::Result<Option<Approx>> {
        let k = part(name)?;
        if k.is_null() { Ok(None) } else { approx_from(&k).map(Some) }
    };
    let ramp = Ramp {
        values: optional("values")?,
        lab: [approx_from(&part("l")?)?, approx_from(&part("a")?)?, approx_from(&part("b")?)?],
        alpha: optional("alpha")?,
    };
    if na_value.len() != 1 {
        return Err(Error::Other("na_value must have length 1".into()));
    }
    let na = na_value.elt(0);
    let out = match Column::new(&x).data {
        ColumnData::Double(v) => ramp::map_colour(v.iter().copied(), limits, oob, rescale, &ramp),
        ColumnData::Integer(v) => ramp::map_colour(v.iter().map(|v| v.map_or(f64::NAN, f64::from)), limits, oob, rescale, &ramp),
        _ => return Err(Error::Other("x must be double or integer".into())),
    };
    fn hex(h: &Option<hex::Hex>) -> Option<&str> {
        h.as_ref().map(hex::Hex::as_str)
    }
    Ok(match out {
        ramp::Mapped::Coded { codes, colours } => convert::coded_ascii_strings(&codes, colours.iter().map(hex), &na),
        ramp::Mapped::Rows(colours) => convert::ascii_strings(colours.iter().map(hex), &na),
    })
}

/// The rows of the column-major n x 3 matrix `m`, `None` if `m` does not
/// have 3 columns.
fn rows3(m: &[f64]) -> Option<impl Iterator<Item = [f64; 3]> + '_> {
    let n = m.len() / 3;
    (m.len() % 3 == 0).then(|| (0..n).map(move |i| [m[i], m[n + i], m[2 * n + i]]))
}

/// The white reference `white` (length 3) as an array.
fn white3(white: &[f64]) -> extendr_api::Result<lab::White> {
    white.try_into().map_err(|_| Error::Other("white must have length 3".into()))
}

/// `farver::encode_colour(lab, alpha, from = "lab", white)` (see
/// `alot_core::colour::hex`): `lab` a double n x 3 matrix, `alpha` `NULL`
/// or a double vector on the 0..1 scale, `white` the XYZ tristimulus of
/// `farver::as_white_ref()`. For tests.
/// @noRd
#[extendr(r_name = "rs_encode_lab")]
fn encode_lab(lab: &[f64], alpha: Robj, white: &[f64]) -> extendr_api::Result<Strings> {
    let white = white3(white)?;
    let rows = rows3(lab).ok_or_else(|| Error::Other("lab must have 3 columns".into()))?;
    let alpha = if alpha.is_null() {
        None
    } else {
        Some(alpha.as_real_slice().ok_or_else(|| Error::Other("alpha must be double".into()))?)
    };
    let alpha = hex::Alpha::new(alpha);
    Ok(rows
        .enumerate()
        .map(|(i, v)| hex::encode_lab(v, &alpha, i, &white).map_or_else(Rstr::na, |h| Rstr::from(h.as_str())))
        .collect())
}

/// `farver::convert_colour(rgb, "rgb", "lab", white)` (`cap = TRUE`) or the
/// Lab of `farver::decode_colour(to = "lab")` (`cap = FALSE`, for RGB the
/// hex codes give): `rgb` a double n x 3 matrix. Returns the n x 3 Lab
/// values as a column-major double vector, NA rows for invalid input. For
/// tests.
/// @noRd
#[extendr(r_name = "rs_rgb_to_lab")]
fn rgb_to_lab(rgb: &[f64], white: &[f64], cap: bool) -> extendr_api::Result<Robj> {
    let white = white3(white)?;
    let rows = rows3(rgb).ok_or_else(|| Error::Other("rgb must have 3 columns".into()))?;
    let n = rgb.len() / 3;
    Ok(new_doubles(rgb.len(), |out| {
        for (i, v) in rows.enumerate() {
            // `Rgb::Cap()` before converting (only for valid, i.e. finite,
            // input), then `Lab::Cap()` after.
            let v = if cap && v.iter().all(|c| c.is_finite()) { v.map(|c| c.clamp(0.0, 255.0)) } else { v };
            let lab = lab::rgb_to_lab(v, &white).map(|l| if cap { lab::cap_lab(l) } else { l });
            for k in 0..3 {
                out[k * n + i] = lab.map_or(transform::NA_REAL, |l| l[k]);
            }
        }
    }))
}

/// `labeling::extended(dmin[i], dmax[i], m[i])` for each `i` (see
/// `alot_core::breaks::extended`). Returns a list with a double vector of
/// breaks per range, `NULL` where R would raise an error or warning.
/// @noRd
#[extendr(r_name = "rs_extended_breaks")]
fn extended_breaks(dmin: &[f64], dmax: &[f64], m: &[f64]) -> extendr_api::Result<List> {
    if dmax.len() != dmin.len() || m.len() != dmin.len() {
        return Err(Error::Other("dmin, dmax and m must have the same length".into()));
    }
    let ranges: Vec<(f64, f64, f64)> = (0..dmin.len()).map(|i| (dmin[i], dmax[i], m[i])).collect();
    let out = extended::extended_batch(&ranges)
        .into_iter()
        .map(|b| b.map_or_else(|| ().into(), |b| Robj::from(Doubles::from_values(b))));
    Ok(List::from_values(out))
}

/// R's `x %% y` (`alot_core::breaks::fmod::r_mod`) elementwise, for tests;
/// `NA` where R would warn. `y` must be positive.
/// @noRd
#[extendr(r_name = "rs_r_mod")]
fn r_mod(x: &[f64], y: &[f64]) -> Doubles {
    Doubles::from_values(x.iter().zip(y).map(|(&x, &y)| fmod::r_mod(x, y).map_or(Rfloat::na(), Rfloat::from)))
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

/// Rows of the first occurrence of each distinct combination of the columns
/// of `df` (`n` rows), comparing factor codes, logicals, integers, double
/// bits and string pointers (see `alot_core::facet::distinct`): 1-based and
/// ascending. `NULL` (decline) for any other column type, a column not of
/// length `n`, or a factor with codes outside its levels.
/// @noRd
#[extendr(r_name = "rs_facet_distinct_rows")]
fn facet_distinct_rows(df: List, n: i32) -> extendr_api::Result<Robj> {
    enum Key<'a> {
        Codes(IntView<'a>, u64),
        Lgl(convert::LglView<'a>),
        Int(IntView<'a>),
        Dbl(&'a [f64]),
        Ptr(&'a [extendr_api::SEXP]),
    }
    let n = n as usize;
    let robjs: Vec<Robj> = df.values().collect();
    let strings: Vec<Option<Strings>> = robjs
        .iter()
        .map(|x| match Column::new(x).data {
            ColumnData::Character(s) => Some(s),
            _ => None,
        })
        .collect();
    let mut keys = Vec::with_capacity(robjs.len());
    let mut cards = Vec::with_capacity(robjs.len());
    for (x, s) in robjs.iter().zip(&strings) {
        if x.len() != n {
            return Ok(().into());
        }
        let (key, card) = match Column::new(x).data {
            ColumnData::Factor(f) => {
                let k = f.levels.len();
                if f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c as usize > k)) {
                    return Ok(().into());
                }
                (Key::Codes(f.codes, k as u64), Some(k + 1))
            }
            ColumnData::Logical(v) => (Key::Lgl(v), Some(3)),
            ColumnData::Integer(v) => (Key::Int(v), None),
            ColumnData::Double(v) => (Key::Dbl(v), None),
            ColumnData::Character(_) => (Key::Ptr(convert::str_ptrs(s.as_ref().unwrap())), None),
            ColumnData::Other => return Ok(().into()),
        };
        keys.push(key);
        cards.push(card);
    }

    let rows = facet::distinct::first_rows(n, &cards, |c, i| match &keys[c] {
        // NA codes take the slot after the levels.
        Key::Codes(v, k) => v.get(i).map_or(*k, |c| c as u64 - 1),
        Key::Lgl(v) => v.get(i).map_or(2, u64::from),
        Key::Int(v) => v.0[i] as u32 as u64,
        Key::Dbl(v) => v[i].to_bits(),
        Key::Ptr(v) => v[i] as usize as u64,
    });
    Ok(convert::integers(rows.into_iter().map(|i| Some(i as i32 + 1))))
}

/// Panel codes for `map_facet_data`'s join (see `alot_core::facet::join`).
/// `data` holds one factor per facet variable, whose `NA` codes take the
/// 1-based code `na`; `cards` gives each variable's number of codes.
/// `layout` holds one integer vector of 1-based codes per variable (`NA`
/// for none) and `panel` the layout's `PANEL` codes. Returns `panel` at
/// each row's first matching layout row (`NA` for none), or `NULL`
/// (decline) for a non-factor column, codes outside the levels, or an
/// overflowing key space.
/// @noRd
#[extendr(r_name = "rs_facet_panels")]
fn facet_panels(data: List, na: &[i32], cards: &[i32], layout: List, panel: &[i32]) -> extendr_api::Result<Robj> {
    let n_vars = data.len();
    if na.len() != n_vars || cards.len() != n_vars || layout.len() != n_vars {
        return Err(Error::Other("data, na, cards and layout must have one entry per variable".into()));
    }
    let n_layout = panel.len();
    let data_robjs: Vec<Robj> = data.values().collect();
    let layout_robjs: Vec<Robj> = layout.values().collect();
    let mut factors = Vec::with_capacity(n_vars);
    for x in &data_robjs {
        let ColumnData::Factor(f) = Column::new(x).data else { return Ok(().into()) };
        let k = f.levels.len() as i32;
        if f.codes.iter().any(|c| c.is_some_and(|c| c < 1 || c > k)) {
            return Ok(().into());
        }
        factors.push(f.codes);
    }
    let mut codes = Vec::with_capacity(n_vars);
    for x in &layout_robjs {
        let ColumnData::Integer(v) = Column::new(x).data else {
            return Err(Error::Other("layout codes must be integer".into()));
        };
        if v.len() != n_layout {
            return Err(Error::Other("layout codes must have one value per layout row".into()));
        }
        codes.push(v);
    }
    let n = factors.first().map_or(0, |f| f.len());
    if factors.iter().any(|f| f.len() != n) {
        return Err(Error::Other("data factors must have the same length".into()));
    }
    if na.iter().chain(cards).any(|&c| c < 1) {
        return Err(Error::Other("na and cards must be positive".into()));
    }

    // Codes below 1 become `usize::MAX`, out of every range, so they never match.
    let zero_based = |c: Option<i32>| c.map(|c| if c >= 1 { c as usize - 1 } else { usize::MAX });
    let cards: Vec<usize> = cards.iter().map(|&c| c as usize).collect();
    let na: Vec<usize> = na.iter().map(|&c| c as usize - 1).collect();
    let layout_codes = codes.iter().map(|v| v.iter().map(zero_based)).collect();
    let Some(join) = facet::join::Join::new(layout_codes, &cards, n_layout, n) else { return Ok(().into()) };
    let panel = IntView(panel);
    let rows = (0..n).map(|i| {
        let row = factors.iter().zip(&na).map(|(f, &na)| Some(f.get(i).map_or(na, |c| c as usize - 1)));
        join.find(row).and_then(|j| panel.get(j))
    });
    Ok(convert::integers(rows))
}

/// The cargo profile this library was built with: "debug" or "release".
/// The benchmark suites refuse to time a debug build.
/// @noRd
#[extendr(r_name = "rs_build_profile")]
fn build_profile() -> &'static str {
    if cfg!(debug_assertions) { "debug" } else { "release" }
}

extendr_module! {
    mod alot;
    use layout;
    use render;
    use text;
    fn build_profile;
    fn facet_panels;
    fn facet_distinct_rows;
    fn extended_breaks;
    fn r_mod;
    fn train_continuous_grouped;
    fn train_continuous;
    fn train_discrete_rows;
    fn map_continuous;
    fn factorize_strings;
    fn map_discrete;
    fn discrete_first_rows;
    fn lookup_discrete;
    fn map_colour;
    fn transform_values;
    fn encode_lab;
    fn rgb_to_lab;
    fn convert_roundtrip;
    fn convert_inspect;
    fn group_index;
    fn grouped_test_stat;
    fn grouped_test_position;
}
