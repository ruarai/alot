//! Discrete position training (`ScaleDiscretePosition$train`).
//!
//! The kernel does not reimplement `scales:::discrete_range`. Instead it
//! picks, for each scale, a short subsequence of the rows routed to that
//! scale that trains to exactly the same range, and R calls the scale's own
//! `train()` on it:
//!
//! - discrete input (factor, character, logical): the first occurrence of
//!   each distinct value, NA included. `unique()`, `levels()`,
//!   `droplevels()` and `any(is.na())` give the same answer on it as on the
//!   full slice;
//! - continuous input (trains `range_c`): the first row holding the
//!   smallest finite value and the first holding the largest, which `range(
//!   finite = TRUE)` reduces to the same pair.
//!
//! Indices are 0-based and ascending within each scale.

use std::collections::HashSet;
use std::hash::{BuildHasherDefault, Hash, Hasher};

/// Row indices per scale.
pub type ScaleRows = Vec<Vec<usize>>;

/// First occurrence of each distinct key per scale, for keys in
/// `0..n_keys` (factor codes, logicals). `scale_id[i]` is the 0-based scale
/// of row `i`.
pub fn first_occurrences_dense<I>(keys: I, n_keys: usize, scale_id: &[usize], n_scales: usize) -> ScaleRows
where
    I: IntoIterator<Item = usize>,
{
    // A seen-table per scale x key is fastest, but with many scales and
    // many keys it would outgrow the data; hash instead.
    if n_scales.saturating_mul(n_keys) > scale_id.len() + (1 << 16) {
        return first_occurrences(keys, scale_id, n_scales);
    }
    let mut seen = vec![false; n_scales * n_keys];
    let mut out = vec![Vec::new(); n_scales];
    for (i, (k, &s)) in keys.into_iter().zip(scale_id).enumerate() {
        let slot = &mut seen[s * n_keys + k];
        if !*slot {
            *slot = true;
            out[s].push(i);
        }
    }
    out
}

/// First occurrence of each distinct key per scale, for arbitrary keys
/// (e.g. string pointers).
pub fn first_occurrences<I, K>(keys: I, scale_id: &[usize], n_scales: usize) -> ScaleRows
where
    I: IntoIterator<Item = K>,
    K: Hash + Eq + Copy,
{
    let mut seen: HashSet<(usize, K), BuildHasherDefault<MixHasher>> = HashSet::default();
    let mut out = vec![Vec::new(); n_scales];
    let mut last: Option<(usize, K)> = None;
    for (i, (k, &s)) in keys.into_iter().zip(scale_id).enumerate() {
        // Runs of equal values are common in layer data; skip the lookup.
        if last == Some((s, k)) {
            continue;
        }
        last = Some((s, k));
        if seen.insert((s, k)) {
            out[s].push(i);
        }
    }
    out
}

/// Per scale, the first row with the smallest finite value and the first
/// with the largest (one row if they coincide, none if the scale has no
/// finite values). Like R's `min()`/`max()`, ties keep the first row.
pub fn extremes<I>(values: I, scale_id: &[usize], n_scales: usize) -> ScaleRows
where
    I: IntoIterator<Item = Option<f64>>,
{
    let mut lo: Vec<Option<(usize, f64)>> = vec![None; n_scales];
    let mut hi: Vec<Option<(usize, f64)>> = vec![None; n_scales];
    for (i, (v, &s)) in values.into_iter().zip(scale_id).enumerate() {
        let Some(v) = v.filter(|v| v.is_finite()) else { continue };
        if lo[s].map_or(true, |(_, m)| v < m) {
            lo[s] = Some((i, v));
        }
        if hi[s].map_or(true, |(_, m)| v > m) {
            hi[s] = Some((i, v));
        }
    }
    lo.into_iter()
        .zip(hi)
        .map(|(l, h)| match (l, h) {
            (Some((a, _)), Some((b, _))) if a == b => vec![a],
            (Some((a, _)), Some((b, _))) => vec![a.min(b), a.max(b)],
            _ => Vec::new(),
        })
        .collect()
}

/// A small multiplicative hasher. SipHash (std's default) dominates the
/// cost for pointer and integer keys; this mixes high bits back down so
/// aligned pointers still spread over buckets.
#[derive(Default)]
struct MixHasher(u64);

impl Hasher for MixHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.write_u64(b as u64);
        }
    }

    fn write_u64(&mut self, x: u64) {
        self.0 = (self.0.rotate_left(5) ^ x).wrapping_mul(0x9e37_79b9_7f4a_7c15);
    }

    fn write_usize(&mut self, x: usize) {
        self.write_u64(x as u64);
    }

    fn write_u32(&mut self, x: u32) {
        self.write_u64(x as u64);
    }

    fn write_i32(&mut self, x: i32) {
        self.write_u64(x as u32 as u64);
    }

    fn finish(&self) -> u64 {
        self.0 ^ (self.0 >> 32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dense_first_occurrences_per_scale() {
        let out = first_occurrences_dense([2, 0, 2, 1, 0, 0], 3, &[0, 0, 0, 1, 1, 1], 2);
        assert_eq!(out, vec![vec![0, 1], vec![3, 4]]);
    }

    #[test]
    fn dense_falls_back_to_hash_for_large_domains() {
        let keys = [5usize, 100_000, 5, 99_999];
        let out = first_occurrences_dense(keys, 100_001, &[0, 1, 0, 1], 2);
        assert_eq!(out, vec![vec![0], vec![1, 3]]);
    }

    #[test]
    fn hashed_first_occurrences_and_unseen_scales() {
        let out = first_occurrences(["b", "a", "b", "b", "c"], &[0, 0, 0, 2, 2], 3);
        assert_eq!(out, vec![vec![0, 1], vec![], vec![3, 4]]);
    }

    #[test]
    fn same_key_in_different_scales_counts_once_per_scale() {
        let out = first_occurrences([7, 7, 7, 7], &[0, 1, 1, 0], 2);
        assert_eq!(out, vec![vec![0], vec![1]]);
    }

    #[test]
    fn extremes_keep_first_ties_and_skip_non_finite() {
        let v = [Some(3.0), None, Some(f64::NAN), Some(1.0), Some(f64::INFINITY), Some(3.0), Some(1.0)];
        let out = extremes(v, &[0; 7], 1);
        assert_eq!(out, vec![vec![0, 3]]);
    }

    #[test]
    fn extremes_single_value_and_no_finite_values() {
        let out = extremes([Some(2.0), None, Some(f64::NEG_INFINITY)], &[0, 1, 1], 3);
        assert_eq!(out, vec![vec![0], vec![], vec![]]);
    }

    #[test]
    fn extremes_max_before_min() {
        let out = extremes([Some(9.0), Some(4.0), Some(-1.0)], &[0, 0, 0], 1);
        assert_eq!(out, vec![vec![0, 2]]);
    }
}
