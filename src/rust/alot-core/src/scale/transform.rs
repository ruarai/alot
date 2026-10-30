//! Continuous scale transforms (`ScalesList$transform_df` ->
//! `Scale$transform_df` -> ggplot2's `default_transform`).
//!
//! The transformed values must equal R's bit for bit:
//!
//! - `transform_log10()` calls `log(x, 10)`, which R evaluates with the C
//!   library's `log10`. Like R's `math2()`, NA input (any sign) gives
//!   `NA_real_` and any other NaN gives `R_NaN`.
//! - `transform_sqrt()` is the `sqrt` primitive. Like R's `math1()`, NaN
//!   input is returned unchanged.
//! - `transform_reverse()` is `-x`, which only flips the sign bit, NaN
//!   included.
//!
//! Alongside the values, R needs to know whether to warn: `log()` and
//! `sqrt()` warn "NaNs produced" when a non-NaN input gives NaN, and
//! `check_transformation()` warns when finiteness changes. The kernels
//! report the first row of each so R can replay the warning on that row.
//!
//! These are R's vector code paths. A length-1 input takes the bytecode's
//! scalar path instead, which differs in NaN bits, so R does not call the
//! kernels for it.

/// The bit pattern of R's `NA_real_`: a NaN whose low word is 1954.
pub const NA_REAL: f64 = f64::from_bits(0x7FF0_0000_0000_07A2);

/// The bit pattern of R's `R_NaN`.
pub const R_NAN: f64 = f64::from_bits(0x7FF8_0000_0000_0000);

/// R's `ISNA()`: a NaN whose low word is 1954, whatever its sign.
pub fn is_na(x: f64) -> bool {
    x.is_nan() && (x.to_bits() as u32) == 1954
}

/// The transforms the kernels handle, as in scales 1.4.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Transform {
    /// `transform_log10()`: `log(x, 10)`.
    Log10,
    /// `transform_sqrt()`: `sqrt`.
    Sqrt,
    /// `transform_reverse()`: `-x`.
    Reverse,
}

impl Transform {
    /// One double through the transform.
    pub fn apply(self, x: f64) -> f64 {
        match self {
            Transform::Reverse => -x,
            Transform::Log10 if is_na(x) => NA_REAL,
            Transform::Log10 if x.is_nan() => R_NAN,
            Transform::Log10 => x.log10(),
            Transform::Sqrt if x.is_nan() => x,
            Transform::Sqrt => x.sqrt(),
        }
    }
}

/// First rows (0-based) at which R would warn.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Report {
    /// A non-NaN input gave NaN ("NaNs produced").
    pub nan_produced: Option<usize>,
    /// `is.finite()` of input and output differ (`check_transformation()`).
    pub finite_changed: Option<usize>,
}

/// Transforms `x` into `out`. Integer input is passed as doubles, with
/// `NA_integer_` as `NA_REAL`.
pub fn transform<X>(x: X, t: Transform, out: &mut [f64]) -> Report
where
    X: IntoIterator<Item = f64>,
{
    let mut report = Report::default();
    if t == Transform::Reverse {
        // Negation keeps finiteness and NaN-ness: nothing to report.
        for (o, v) in out.iter_mut().zip(x) {
            *o = -v;
        }
        return report;
    }
    for (i, (o, v)) in out.iter_mut().zip(x).enumerate() {
        let y = t.apply(v);
        *o = y;
        if report.nan_produced.is_none() && y.is_nan() && !v.is_nan() {
            report.nan_produced = Some(i);
        }
        if report.finite_changed.is_none() && y.is_finite() != v.is_finite() {
            report.finite_changed = Some(i);
        }
    }
    report
}

/// `-x` on an integer vector (`None` is NA), which R keeps integer. It
/// cannot overflow, since `NA_integer_` is `i32::MIN`, and it never
/// changes finiteness, so there is nothing to report.
pub fn reverse_integers<X>(x: X, out: &mut [i32])
where
    X: IntoIterator<Item = Option<i32>>,
{
    for (o, v) in out.iter_mut().zip(x) {
        *o = v.map_or(i32::MIN, |v| -v);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const INF: f64 = f64::INFINITY;

    fn bits(x: &[f64]) -> Vec<u64> {
        x.iter().map(|v| v.to_bits()).collect()
    }

    #[test]
    fn nan_input_bits() {
        let neg_na = -NA_REAL;
        let neg_nan = -f64::NAN;
        let log = Transform::Log10;
        assert_eq!(log.apply(NA_REAL).to_bits(), NA_REAL.to_bits());
        assert_eq!(log.apply(neg_na).to_bits(), NA_REAL.to_bits());
        assert_eq!(log.apply(neg_nan).to_bits(), R_NAN.to_bits());
        for x in [NA_REAL, neg_na, neg_nan] {
            assert_eq!(Transform::Sqrt.apply(x).to_bits(), x.to_bits());
        }
        assert_eq!(Transform::Reverse.apply(NA_REAL).to_bits(), neg_na.to_bits());
        assert!(is_na(neg_na) && !is_na(f64::NAN));
    }

    #[test]
    fn values_and_reports() {
        let x = [100.0, 0.0, -0.0, -4.0, INF, -INF, NA_REAL, 4.0];
        let mut out = [0.0; 8];
        let r = transform(x, Transform::Log10, &mut out);
        assert_eq!(&out[..3], &[2.0, -INF, -INF]);
        assert!(out[3].is_nan() && out[5].is_nan() && is_na(out[6]));
        assert_eq!(out[4], INF);
        assert_eq!(r, Report { nan_produced: Some(3), finite_changed: Some(1) });

        let r = transform(x, Transform::Sqrt, &mut out);
        assert_eq!(bits(&out[..3]), bits(&[10.0, 0.0, -0.0]));
        assert_eq!(out[7], 2.0);
        assert_eq!(r, Report { nan_produced: Some(3), finite_changed: Some(3) });

        let r = transform(x, Transform::Reverse, &mut out);
        assert_eq!(bits(&out[..6]), bits(&[-100.0, -0.0, 0.0, 4.0, -INF, INF]));
        assert_eq!(r, Report::default());
    }

    #[test]
    fn reverse_keeps_integers() {
        let mut out = [0; 3];
        reverse_integers([Some(3), None, Some(-i32::MAX)], &mut out);
        assert_eq!(out, [-3, i32::MIN, i32::MAX]);
    }

    #[test]
    fn empty_input() {
        let r = transform(std::iter::empty(), Transform::Log10, &mut []);
        assert_eq!(r, Report::default());
    }
}
