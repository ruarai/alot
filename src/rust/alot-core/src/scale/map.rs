//! Position mapping (`Layout$map_position` -> `Scale$map`).
//!
//! - Continuous: `ScaleContinuousPosition$map` applies the scale's `oob`
//!   function against its limits, then replaces every NA or NaN with
//!   `na.value` (`vec_assign(scaled, is.na(scaled), na.value)`).
//! - Discrete: `ScaleDiscretePosition$map` looks each value up in the
//!   limits and takes the palette value at that position. R does the string
//!   matching on the distinct values (`match()` translates encodings) and
//!   passes a table of per-scale results; Rust only indexes it per row.
//!
//! `scale_id` iterators give each row's 0-based scale.

use std::collections::HashMap;
use std::hash::BuildHasherDefault;

use super::discrete::MixHasher;

/// The `oob` functions the continuous kernel handles, as in scales 1.4.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Oob {
    /// `censor()` / `oob_censor()`; `only_finite = FALSE` is
    /// `oob_censor_any()`.
    Censor { only_finite: bool },
    /// `squish()` / `oob_squish()`; `only_finite = FALSE` is
    /// `oob_squish_any()`.
    Squish { only_finite: bool },
    /// `squish_infinite()` / `oob_squish_infinite()`.
    SquishInfinite,
    /// `oob_keep()`.
    Keep,
}

impl Oob {
    /// One value through the oob function; `None` is NA. Mirrors the R
    /// code step by step: comparisons with NaN are NA, which `[<-` skips,
    /// and the second assignment sees the result of the first.
    pub fn apply(self, x: Option<f64>, [lo, hi]: [f64; 2]) -> Option<f64> {
        let Some(mut v) = x else { return None };
        match self {
            Oob::Censor { only_finite } => {
                let check = !only_finite || v.is_finite();
                if check && (v < lo || v > hi) {
                    return None;
                }
            }
            Oob::Squish { only_finite } => {
                let check = !only_finite || v.is_finite();
                if check && v < lo {
                    v = lo;
                }
                if check && v > hi {
                    v = hi;
                }
            }
            Oob::SquishInfinite => {
                if v == f64::NEG_INFINITY {
                    v = lo;
                }
                if v == f64::INFINITY {
                    v = hi;
                }
            }
            Oob::Keep => {}
        }
        Some(v)
    }
}

/// The rescalers of continuous non-position scales, onto `to = c(0, 1)`.
/// NaN is NA.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Rescale {
    /// `scales::rescale.numeric(x, from = from)`, where `zero_range(from)`
    /// is FALSE: `(x - from[1]) / diff(from) * diff(to) + to[1]`.
    Linear { from: [f64; 2] },
    /// `scales::rescale_mid.numeric(x, from = from, mid = mid)`, where
    /// `zero_range(from)` is FALSE and `extent` is R's
    /// `2 * max(abs(from - mid))`: `(x - mid) / extent * diff(to) +
    /// mean(to)`.
    Mid { mid: f64, extent: f64 },
    /// Either rescaler when `zero_range(from)` is TRUE:
    /// `ifelse(is.na(x), NA, mean(to))`.
    Zero,
}

impl Rescale {
    pub fn apply(self, x: f64) -> f64 {
        match self {
            Rescale::Linear { from } => (x - from[0]) / (from[1] - from[0]) * 1.0 + 0.0,
            Rescale::Mid { mid, extent } => (x - mid) / extent * 1.0 + 0.5,
            Rescale::Zero => {
                if x.is_nan() {
                    f64::NAN
                } else {
                    0.5
                }
            }
        }
    }
}

/// Maps `x` onto continuous position scales into `out`: `oob` against
/// `limits[scale]`, then NA and NaN become `na_value`. `na_value` is
/// written bit for bit, so R's `NA_real_` stays NA rather than NaN.
pub fn map_continuous<X, S>(x: X, scale_id: S, limits: &[[f64; 2]], oob: Oob, na_value: f64, out: &mut [f64])
where
    X: IntoIterator<Item = Option<f64>>,
    S: IntoIterator<Item = usize>,
{
    for ((o, v), s) in out.iter_mut().zip(x).zip(scale_id) {
        *o = match oob.apply(v, limits[s]) {
            Some(v) if !v.is_nan() => v,
            _ => na_value,
        };
    }
}

/// Maps discrete keys onto positions into `out`: `table[s * n_keys + k]`
/// for a row with key `k` on scale `s`. Keys must be below `n_keys`.
pub fn map_discrete<K, S>(keys: K, scale_id: S, table: &[f64], n_keys: usize, out: &mut [f64])
where
    K: IntoIterator<Item = usize>,
    S: IntoIterator<Item = usize>,
{
    for ((o, k), s) in out.iter_mut().zip(keys).zip(scale_id) {
        *o = table[s * n_keys + k];
    }
}

/// Dense 0-based codes for arbitrary keys (e.g. string pointers), in order
/// of first appearance, plus the first row of each code.
pub fn factorize<I, K>(keys: I) -> (Vec<usize>, Vec<usize>)
where
    I: IntoIterator<Item = K>,
    K: std::hash::Hash + Eq + Copy,
{
    let mut seen: HashMap<K, usize, BuildHasherDefault<MixHasher>> = HashMap::default();
    let mut codes = Vec::new();
    let mut first = Vec::new();
    let mut last: Option<(K, usize)> = None;
    for (i, k) in keys.into_iter().enumerate() {
        // Runs of equal values are common in layer data; skip the lookup.
        if let Some((lk, code)) = last {
            if lk == k {
                codes.push(code);
                continue;
            }
        }
        let code = *seen.entry(k).or_insert_with(|| {
            first.push(i);
            first.len() - 1
        });
        last = Some((k, code));
        codes.push(code);
    }
    (codes, first)
}

#[cfg(test)]
mod tests {
    use super::*;

    const INF: f64 = f64::INFINITY;

    fn oob_all(oob: Oob, x: &[Option<f64>], lim: [f64; 2]) -> Vec<Option<f64>> {
        x.iter().map(|&v| oob.apply(v, lim)).collect()
    }

    #[test]
    fn censor_drops_finite_out_of_range_values() {
        let x = [Some(-1.0), Some(0.0), Some(5.0), Some(11.0), Some(-INF), Some(INF), None];
        let fin = oob_all(Oob::Censor { only_finite: true }, &x, [0.0, 10.0]);
        assert_eq!(fin, vec![None, Some(0.0), Some(5.0), None, Some(-INF), Some(INF), None]);
        let any = oob_all(Oob::Censor { only_finite: false }, &x, [0.0, 10.0]);
        assert_eq!(any, vec![None, Some(0.0), Some(5.0), None, None, None, None]);
    }

    #[test]
    fn squish_clamps_in_assignment_order() {
        let x = [Some(-1.0), Some(5.0), Some(11.0), Some(-INF), Some(INF)];
        let fin = oob_all(Oob::Squish { only_finite: true }, &x, [0.0, 10.0]);
        assert_eq!(fin, vec![Some(0.0), Some(5.0), Some(10.0), Some(-INF), Some(INF)]);
        let any = oob_all(Oob::Squish { only_finite: false }, &x, [0.0, 10.0]);
        assert_eq!(any, vec![Some(0.0), Some(5.0), Some(10.0), Some(0.0), Some(10.0)]);
        // Reversed limits: the low clamp's result is then compared to hi.
        let rev = oob_all(Oob::Squish { only_finite: true }, &[Some(-1.0), Some(5.0)], [10.0, 0.0]);
        assert_eq!(rev, vec![Some(0.0), Some(0.0)]);
    }

    #[test]
    fn squish_infinite_and_keep() {
        let x = [Some(-INF), Some(INF), Some(-50.0), None];
        let si = oob_all(Oob::SquishInfinite, &x, [0.0, 10.0]);
        assert_eq!(si, vec![Some(0.0), Some(10.0), Some(-50.0), None]);
        assert_eq!(oob_all(Oob::Keep, &x, [0.0, 10.0]), x.to_vec());
    }

    #[test]
    fn nan_is_left_alone_then_replaced() {
        let nan = Some(f64::NAN);
        for oob in [Oob::Censor { only_finite: false }, Oob::Squish { only_finite: false }, Oob::SquishInfinite] {
            assert!(oob.apply(nan, [0.0, 1.0]).unwrap().is_nan());
        }
        let mut out = [0.0; 3];
        map_continuous([nan, None, Some(2.0)], [0, 0, 0], &[[0.0, 1.0]], Oob::Keep, -7.0, &mut out);
        assert_eq!(out, [-7.0, -7.0, 2.0]);
    }

    #[test]
    fn rescalers() {
        let lin = Rescale::Linear { from: [2.0, 6.0] };
        assert_eq!([0.0, 2.0, 5.0, 6.0, INF].map(|v| lin.apply(v)), [-0.5, 0.0, 0.75, 1.0, INF]);
        let mid = Rescale::Mid { mid: 0.0, extent: 8.0 };
        assert_eq!([-4.0, 0.0, 2.0].map(|v| mid.apply(v)), [0.0, 0.5, 0.75]);
        assert_eq!(Rescale::Zero.apply(-INF), 0.5);
        assert!(Rescale::Zero.apply(f64::NAN).is_nan());
        assert!(lin.apply(f64::NAN).is_nan());
    }

    #[test]
    fn continuous_uses_each_rows_scale() {
        let mut out = [0.0; 4];
        let lim = [[0.0, 1.0], [0.0, 10.0]];
        let x = [Some(5.0), Some(5.0), Some(0.5), Some(20.0)];
        map_continuous(x, [0, 1, 0, 1], &lim, Oob::Squish { only_finite: true }, f64::NAN, &mut out);
        assert_eq!(out, [1.0, 5.0, 0.5, 10.0]);
    }

    #[test]
    fn discrete_indexes_the_per_scale_table() {
        // Two keys, two scales: table is column-major per scale.
        let table = [1.0, 2.0, 2.0, f64::NAN];
        let mut out = [0.0; 4];
        map_discrete([0, 1, 0, 1], [0, 0, 1, 1], &table, 2, &mut out);
        assert_eq!(&out[..3], &[1.0, 2.0, 2.0]);
        assert!(out[3].is_nan());
    }

    #[test]
    fn factorize_codes_by_first_appearance() {
        let (codes, first) = factorize(["b", "b", "a", "b", "c", "a"]);
        assert_eq!(codes, vec![0, 0, 1, 0, 2, 1]);
        assert_eq!(first, vec![0, 2, 4]);
        let (codes, first) = factorize(std::iter::empty::<u8>());
        assert!(codes.is_empty() && first.is_empty());
    }
}
