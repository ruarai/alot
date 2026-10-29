//! Continuous range training, matching `scales::train_continuous()`.

/// Train one continuous range per scale in a single pass.
///
/// `scale_id[i]` is the 0-based scale that value `values[i]` trains.
/// `existing` holds each scale's current range, or `None` if untrained.
/// Values are `Option<f64>` so integer NAs can be passed as `None`.
///
/// Returns one entry per scale: `None` if no values were routed to that
/// scale (ggplot2 skips training on empty input), otherwise the new range.
/// Like `range(existing, new, finite = TRUE)`, non-finite values are
/// ignored and a range with no finite values is `[Inf, -Inf]`.
pub fn train_continuous_grouped<I>(
    values: I,
    scale_id: &[usize],
    existing: &[Option<[f64; 2]>],
) -> Vec<Option<[f64; 2]>>
where
    I: IntoIterator<Item = Option<f64>>,
{
    let n = existing.len();
    let mut seen = vec![false; n];
    let mut lo = vec![f64::INFINITY; n];
    let mut hi = vec![f64::NEG_INFINITY; n];

    for (v, &s) in values.into_iter().zip(scale_id) {
        seen[s] = true;
        if let Some(v) = v {
            if v.is_finite() {
                lo[s] = lo[s].min(v);
                hi[s] = hi[s].max(v);
            }
        }
    }

    (0..n)
        .map(|s| {
            if !seen[s] {
                return None;
            }
            let (mut l, mut h) = (lo[s], hi[s]);
            if let Some([el, eh]) = existing[s] {
                for e in [el, eh] {
                    if e.is_finite() {
                        l = l.min(e);
                        h = h.max(e);
                    }
                }
            }
            Some([l, h])
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vals(v: &[f64]) -> Vec<Option<f64>> {
        v.iter().copied().map(Some).collect()
    }

    #[test]
    fn ranges_per_scale() {
        let out = train_continuous_grouped(
            vals(&[3.0, 1.0, 10.0, -2.0]),
            &[0, 0, 1, 1],
            &[None, None],
        );
        assert_eq!(out, vec![Some([1.0, 3.0]), Some([-2.0, 10.0])]);
    }

    #[test]
    fn ignores_non_finite_and_merges_existing() {
        let out = train_continuous_grouped(
            vec![Some(f64::NAN), Some(f64::INFINITY), None, Some(5.0)],
            &[0, 0, 0, 0],
            &[Some([0.0, 2.0])],
        );
        assert_eq!(out, vec![Some([0.0, 5.0])]);
    }

    #[test]
    fn empty_scale_untouched_and_all_non_finite_is_inf() {
        let out = train_continuous_grouped(vec![None], &[1], &[None, None]);
        assert_eq!(out, vec![None, Some([f64::INFINITY, f64::NEG_INFINITY])]);
    }

    #[test]
    fn existing_infinite_range_is_dropped() {
        let out = train_continuous_grouped(
            vals(&[4.0]),
            &[0],
            &[Some([f64::INFINITY, f64::NEG_INFINITY])],
        );
        assert_eq!(out, vec![Some([4.0, 4.0])]);
    }
}
