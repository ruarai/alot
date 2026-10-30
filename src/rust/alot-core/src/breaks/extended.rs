//! `labeling::extended()` (labeling 0.4.3), the break algorithm behind
//! `scales::extended_breaks()`, with its defaults `Q = c(1, 5, 2, 2.5, 4,
//! 3)`, `only.loose = FALSE` and `w = c(0.25, 0.2, 0.5, 0.05)`.
//!
//! The port keeps R's floating-point operations and their order, so the
//! breaks equal R's bit for bit: `log(x, base = 10)` is the C library's
//! `log10`, `10^z` its `pow` (R's `R_pow()`), `x^2` is `x * x`, and `%%` is
//! R's extended-precision `myfmod()` ([`r_mod`]). The final `seq()` calls
//! mirror `seq.default()`.
//!
//! Where R would raise an error or warning (NA or infinite input, a NaN
//! score, no candidate found, a lossy `%%`), the result is `None` and the
//! caller runs `labeling::extended()` itself. So does `m < 1`, where the
//! density bound grows with `k` and R never returns.

use super::fmod::{r_mod, r_mod_warns};

const Q: [f64; 6] = [1.0, 5.0, 2.0, 2.5, 4.0, 3.0];
const W: [f64; 4] = [0.25, 0.2, 0.5, 0.05];
const EPS: f64 = f64::EPSILON * 100.0;

/// R's `if (a < b)`: an error (`None`) if either is NaN.
fn lt(a: f64, b: f64) -> Option<bool> {
    if a.is_nan() || b.is_nan() { None } else { Some(a < b) }
}

/// R's `max(a, b)` and `min(a, b)`, which propagate NaN.
fn rmax(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() { f64::NAN } else if a >= b { a } else { b }
}
fn rmin(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() { f64::NAN } else if a <= b { a } else { b }
}

// `.simplicity()`, with `i` the 1-based position of `q` in `Q`.
fn simplicity(i: usize, j: f64, lmin: f64, lmax: f64, lstep: f64) -> Option<f64> {
    let n = Q.len();
    // `(lmin %% lstep < eps || lstep - (lmin %% lstep) < eps) && lmin <= 0 &&
    // lmax >= 0`. `%%` only matters when the labels span 0, but R runs it
    // first, so its warning counts either way.
    let v = if lmin <= 0.0 && lmax >= 0.0 {
        let r = r_mod(lmin, lstep)?;
        if r < EPS || lstep - r < EPS { 1.0 } else { 0.0 }
    } else if r_mod_warns(lmin, lstep) {
        return None;
    } else {
        0.0
    };
    Some(1.0 - (i - 1) as f64 / (n - 1) as f64 - j + v)
}

fn simplicity_max(i: usize, j: f64) -> f64 {
    let n = Q.len();
    let v = 1.0;
    1.0 - (i - 1) as f64 / (n - 1) as f64 - j + v
}

fn coverage(dmin: f64, dmax: f64, lmin: f64, lmax: f64) -> f64 {
    let range = dmax - dmin;
    let a = dmax - lmax;
    let b = dmin - lmin;
    let c = 0.1 * range;
    1.0 - 0.5 * (a * a + b * b) / (c * c)
}

fn coverage_max(dmin: f64, dmax: f64, span: f64) -> Option<f64> {
    let range = dmax - dmin;
    if lt(range, span)? {
        let half = (span - range) / 2.0;
        let c = 0.1 * range;
        Some(1.0 - 0.5 * (half * half + half * half) / (c * c))
    } else {
        Some(1.0)
    }
}

fn density(k: f64, m: f64, dmin: f64, dmax: f64, lmin: f64, lmax: f64) -> f64 {
    let r = (k - 1.0) / (lmax - lmin);
    let rt = (m - 1.0) / (rmax(lmax, dmax) - rmin(dmin, lmin));
    2.0 - rmax(r / rt, rt / r)
}

fn density_max(k: f64, m: f64) -> Option<f64> {
    if lt(k, m)? { Some(1.0) } else { Some(2.0 - (k - 1.0) / (m - 1.0)) }
}

/// `labeling::extended(dmin, dmax, m)`, or `None` where R would raise an
/// error or warning.
pub fn extended(dmin: f64, dmax: f64, m: f64) -> Option<Vec<f64>> {
    if !(dmin.is_finite() && dmax.is_finite() && m.is_finite()) || m < 1.0 {
        return None;
    }
    let (dmin, dmax) = if dmin > dmax { (dmax, dmin) } else { (dmin, dmax) };
    if dmax - dmin < EPS || (dmax - dmin) > f64::MAX.sqrt() {
        return seq_length_out(dmin, dmax, m);
    }

    // (lmin, lmax, lstep, score)
    let mut best: Option<(f64, f64, f64)> = None;
    let mut best_score = -2.0;
    let mut j = 1.0;
    'j: loop {
        for (qi, &q) in Q.iter().enumerate() {
            let i = qi + 1;
            let sm = simplicity_max(i, j);
            if lt(W[0] * sm + W[1] + W[2] + W[3], best_score)? {
                break 'j;
            }
            let mut k = 2.0;
            loop {
                let dm = density_max(k, m)?;
                if lt(W[0] * sm + W[1] + W[2] * dm + W[3], best_score)? {
                    break;
                }
                let delta = (dmax - dmin) / (k + 1.0) / j / q;
                let mut z = delta.log10().ceil();
                loop {
                    let step = j * q * r_pow10(z);
                    let cm = coverage_max(dmin, dmax, step * (k - 1.0))?;
                    if lt(W[0] * sm + W[1] * cm + W[2] * dm + W[3], best_score)? {
                        break;
                    }
                    let min_start = (dmax / step).floor() * j - (k - 1.0) * j;
                    let max_start = (dmin / step).ceil() * j;
                    if lt(max_start, min_start)? {
                        z += 1.0;
                        continue;
                    }
                    for start in colon(min_start, max_start)? {
                        let lmin = start * (step / j);
                        let lmax = lmin + step * (k - 1.0);
                        let lstep = step;
                        let s = simplicity(i, j, lmin, lmax, lstep)?;
                        let c = coverage(dmin, dmax, lmin, lmax);
                        let g = density(k, m, dmin, dmax, lmin, lmax);
                        let l = 1.0;
                        let score = W[0] * s + W[1] * c + W[2] * g + W[3] * l;
                        if lt(best_score, score)? {
                            best = Some((lmin, lmax, lstep));
                            best_score = score;
                        }
                    }
                    z += 1.0;
                }
                k += 1.0;
            }
        }
        j += 1.0;
    }

    let (lmin, lmax, lstep) = best?;
    seq_by(lmin, lmax, lstep)
}

/// Runs [`extended`] for each `(dmin, dmax, m)`.
pub fn extended_batch(ranges: &[(f64, f64, f64)]) -> Vec<Option<Vec<f64>>> {
    ranges.iter().map(|&(dmin, dmax, m)| extended(dmin, dmax, m)).collect()
}

/// R's `10^z` (`R_POW()`), for integer-valued `z`.
fn r_pow10(z: f64) -> f64 {
    if z == 2.0 {
        100.0
    } else if z == 0.0 {
        1.0
    } else {
        10f64.powf(z)
    }
}

/// R's `from:to` for doubles with `from <= to`: `from + i` for `i` in
/// `0..=floor(to - from + 1 + FLT_EPSILON) - 1`.
fn colon(from: f64, to: f64) -> Option<impl Iterator<Item = f64>> {
    let r = (to - from).abs();
    if !(r < 1e9) {
        // R would allocate a vector this long; leave it to R.
        return None;
    }
    let n = (r + 1.0 + f32::EPSILON as f64) as u64;
    Some((0..n).map(move |i| from + i as f64))
}

/// `seq(from, to, by = by)` for doubles with `by > 0` (`seq.default()`).
fn seq_by(from: f64, to: f64, by: f64) -> Option<Vec<f64>> {
    let del = to - from;
    if del == 0.0 && to == 0.0 {
        return Some(vec![to]);
    }
    let finite_del = del.is_finite();
    let n = if finite_del { del / by } else { to / by - from / by };
    if !n.is_finite() || n < 0.0 || n > i32::MAX as f64 {
        return None;
    }
    if finite_del && del.abs() / rmax(to.abs(), from.abs()) < 100.0 * f64::EPSILON {
        return Some(vec![from]);
    }
    let n = (n + 1e-10) as i32;
    Some(
        (0..=n)
            .map(|i| {
                let x = if finite_del { from + i as f64 * by } else { (from / 4.0 + i as f64 * (by / 4.0)) * 4.0 };
                // pmin(x, to)
                if x <= to { x } else { to }
            })
            .collect(),
    )
}

/// `seq(from, to, length.out = m)` for doubles with `from <= to`
/// (`seq.default()`).
fn seq_length_out(from: f64, to: f64, m: f64) -> Option<Vec<f64>> {
    let len = m.ceil();
    // A length of 0 gives integer(0); leave that and negative lengths to R.
    if !(len >= 1.0 && len <= i32::MAX as f64) {
        return None;
    }
    let len = len as usize;
    if len <= 2 {
        return Some([from, to][..len].to_vec());
    }
    if from == to {
        return Some(vec![from; len]);
    }
    let n1 = (len - 1) as f64;
    let del = to - from;
    let mid = 1..=(len - 2);
    let out = if del.is_finite() {
        let by = del / n1;
        std::iter::once(from).chain(mid.map(|i| from + i as f64 * by)).chain([to]).collect()
    } else {
        let (from, to) = (from / 4.0, to / 4.0);
        let by = (to - from) / n1;
        std::iter::once(from).chain(mid.map(|i| from + i as f64 * by)).chain([to]).map(|x| x * 4.0).collect()
    };
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Expected values from labeling::extended() in R 4.6.1.
    #[test]
    fn matches_labeling() {
        assert_eq!(extended(0.0, 10.0, 5.0), Some(vec![0.0, 2.5, 5.0, 7.5, 10.0]));
        assert_eq!(extended(1.0, 99.0, 5.0), Some(vec![0.0, 25.0, 50.0, 75.0, 100.0]));
        assert_eq!(extended(-3.2, 7.9, 5.0), Some(vec![-2.5, 0.0, 2.5, 5.0, 7.5]));
        // Swapped bounds.
        assert_eq!(extended(10.0, 0.0, 5.0), extended(0.0, 10.0, 5.0));
    }

    #[test]
    fn degenerate_ranges_use_length_out() {
        assert_eq!(extended(1.0, 1.0, 5.0), Some(vec![1.0; 5]));
        assert_eq!(extended(1.0, 1.0, 2.0), Some(vec![1.0, 1.0]));
        assert_eq!(extended(1.0, 1.0, 1.0), Some(vec![1.0]));
        let huge = extended(-f64::MAX, f64::MAX, 3.0).unwrap();
        assert_eq!(huge, vec![-f64::MAX, 0.0, f64::MAX]);
    }

    #[test]
    fn declines_where_r_errors() {
        assert_eq!(extended(f64::NAN, 1.0, 5.0), None);
        assert_eq!(extended(0.0, f64::INFINITY, 5.0), None);
        assert_eq!(extended(1.0, 1.0, 0.0), None);
        // R loops forever here.
        assert_eq!(extended(0.0, 1.0, 0.5), None);
    }

    #[test]
    fn seq_by_mirrors_seq_default() {
        assert_eq!(seq_by(0.0, 1.0, 0.25), Some(vec![0.0, 0.25, 0.5, 0.75, 1.0]));
        assert_eq!(seq_by(0.0, 0.0, 1.0), Some(vec![0.0]));
        // pmin() caps the last value at `to`.
        assert_eq!(seq_by(0.1, 0.7, 0.2).unwrap().last(), Some(&0.7));
    }

    #[test]
    fn batch_runs_each_range() {
        let out = extended_batch(&[(0.0, 10.0, 5.0), (f64::NAN, 1.0, 5.0)]);
        assert_eq!(out, vec![extended(0.0, 10.0, 5.0), None]);
    }
}
