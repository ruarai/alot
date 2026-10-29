use alot_core::scale::range;
use extendr_api::prelude::*;

/// Train continuous ranges for `n` scales. `x` is a double or integer
/// vector, `scale_id` 1-based scale indices, `existing` a length-2n double
/// vector of current ranges (NaN pair for untrained). Returns a length-2n
/// double vector of new ranges, NA pairs for scales that saw no values.
#[extendr]
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

extendr_module! {
    mod alot;
    fn train_continuous_grouped;
}
