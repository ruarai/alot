//! Continuous colour mapping: `ScaleContinuous$map` (ggplot2
//! `R/scale-.R`) with a `scales::pal_gradient_n()` palette, whose
//! `colour_ramp()` interpolates Lab knots with `stats::approxfun()` and
//! encodes the result with farver's `encode_colour()`.
//!
//! Upstream applies the palette to the unique rescaled values only and
//! then matches each row to its value. Every step is elementwise except
//! `encode_colour()`'s alpha rule, which treats a single alpha value
//! differently from several (see [`hex::Alpha`]); [`map_colour`] keeps
//! that rule whether it colours unique values or rows.

use std::collections::HashMap;
use std::hash::BuildHasherDefault;

use super::hex::{self, Alpha, Hex};
use super::lab::D65;
use crate::scale::discrete::MixHasher;
use crate::scale::map::{Oob, Rescale};

/// A linear `stats::approxfun()` (`rule = 1` or given `yleft`/`yright`):
/// knots `x`, increasing without ties as `regularize.values()` leaves them,
/// and values `y`.
#[derive(Clone, Debug)]
pub struct Approx {
    pub x: Vec<f64>,
    pub y: Vec<f64>,
    pub yleft: f64,
    pub yright: f64,
}

impl Approx {
    /// R's `R_approxfun` and `approx1` (`src/library/stats/src/approx.c`)
    /// for one point: NaN passes through, points outside the knots give
    /// `yleft`/`yright`, and the interval is found by bisection.
    pub fn eval(&self, v: f64) -> f64 {
        if v.is_nan() {
            return v;
        }
        let (x, y) = (&self.x, &self.y);
        let n = x.len();
        if n == 0 {
            return f64::NAN;
        }
        let (mut i, mut j) = (0, n - 1);
        if v < x[i] {
            return self.yleft;
        }
        if v > x[j] {
            return self.yright;
        }
        while i + 1 < j {
            let ij = (i + j) / 2;
            if v < x[ij] {
                j = ij;
            } else {
                i = ij;
            }
        }
        if v == x[j] {
            return y[j];
        }
        if v == x[i] {
            return y[i];
        }
        y[i] + (y[j] - y[i]) * ((v - x[i]) / (x[j] - x[i]))
    }
}

/// A `pal_gradient_n()` palette: the optional `values` remapping, then
/// `colour_ramp()`'s interpolators for L, a, b and (unless every colour is
/// opaque) alpha.
#[derive(Clone, Debug)]
pub struct Ramp {
    pub values: Option<Approx>,
    pub lab: [Approx; 3],
    pub alpha: Option<Approx>,
}

impl Ramp {
    /// The palette on rescaled values `x`: `pal_gradient_n()`'s function,
    /// then `colour_ramp()`'s with `encode_colour()`. `None` is NA.
    pub fn colours(&self, x: &[f64]) -> Vec<Option<Hex>> {
        let x: Vec<f64> = match &self.values {
            Some(f) => x.iter().map(|&v| f.eval(v)).collect(),
            None => x.to_vec(),
        };
        let alpha: Option<Vec<f64>> = self.alpha.as_ref().map(|f| x.iter().map(|&v| f.eval(v)).collect());
        let alpha = Alpha::new(alpha.as_deref());
        x.iter()
            .enumerate()
            .map(|(i, &v)| hex::encode_lab(self.lab.each_ref().map(|f| f.eval(v)), &alpha, i, &D65))
            .collect()
    }
}

/// The result of [`map_colour`].
#[derive(Clone, Debug)]
pub enum Mapped {
    /// Row `i`'s colour is `colours[codes[i]]`.
    Coded { codes: Vec<u32>, colours: Vec<Option<Hex>> },
    /// One colour per row.
    Rows(Vec<Option<Hex>>),
}

/// Codes rescaled values as `unique()` and `match()` would. Every NA or
/// NaN shares one code: its colour is NA whatever the alpha rule, and the
/// rule only tells one unique value from several, which merging NA with
/// NaN cannot change.
#[derive(Default)]
struct Uniques {
    seen: HashMap<u64, u32, BuildHasherDefault<MixHasher>>,
    values: Vec<f64>,
    last: Option<(u64, u32)>,
}

impl Uniques {
    fn code(&mut self, v: f64) -> u32 {
        // `unique()` compares doubles with `==`: adding 0 turns -0 into 0.
        let key = if v.is_nan() { f64::NAN.to_bits() } else { (v + 0.0).to_bits() };
        // Runs of equal values are common in layer data; skip the lookup.
        if let Some((k, code)) = self.last {
            if k == key {
                return code;
            }
        }
        let values = &mut self.values;
        let code = *self.seen.entry(key).or_insert_with(|| {
            values.push(v);
            (values.len() - 1) as u32
        });
        self.last = Some((key, code));
        code
    }
}

/// Rows sampled before deciding between coding and colouring row by row.
const SAMPLE: usize = 4096;

/// Maps `x` (NaN for NA) onto colours: `oob` against `limits`, `rescale`,
/// then the ramp. As upstream, the ramp runs on the unique rescaled values,
/// unless more than half the first [`SAMPLE`] rows are distinct: then
/// hashing costs more than it saves, and the ramp runs on every row. That
/// gives the same colours, as there are then at least three unique values
/// and the alpha rule for several values applies to each row alike.
pub fn map_colour<X>(x: X, limits: [f64; 2], oob: Oob, rescale: Rescale, ramp: &Ramp) -> Mapped
where
    X: IntoIterator<Item = f64>,
{
    let x: Vec<f64> = x
        .into_iter()
        .map(|v| rescale.apply(oob.apply(Some(v), limits).unwrap_or(f64::NAN)))
        .collect();
    let mut uniq = Uniques::default();
    let sample = x.len().min(SAMPLE);
    let mut codes: Vec<u32> = Vec::with_capacity(x.len());
    codes.extend(x[..sample].iter().map(|&v| uniq.code(v)));
    if sample >= 4 && 2 * uniq.values.len() > sample {
        return Mapped::Rows(ramp.colours(&x));
    }
    codes.extend(x[sample..].iter().map(|&v| uniq.code(v)));
    Mapped::Coded { codes, colours: ramp.colours(&uniq.values) }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NA: f64 = f64::NAN;

    fn approx(x: &[f64], y: &[f64]) -> Approx {
        Approx { x: x.to_vec(), y: y.to_vec(), yleft: NA, yright: NA }
    }

    #[test]
    fn approx_matches_r() {
        let f = approx(&[0.0, 0.25, 0.5, 1.0], &[10.0, 20.0, -5.0, 1.0]);
        assert_eq!(f.eval(0.0), 10.0);
        assert_eq!(f.eval(0.25), 20.0);
        assert_eq!(f.eval(1.0), 1.0);
        assert_eq!(f.eval(0.125), 10.0 + (20.0 - 10.0) * ((0.125 - 0.0) / (0.25 - 0.0)));
        assert_eq!(f.eval(0.75), -5.0 + (1.0 - -5.0) * ((0.75 - 0.5) / (1.0 - 0.5)));
        assert!(f.eval(-0.1).is_nan() && f.eval(1.1).is_nan() && f.eval(NA).is_nan());
        let g = Approx { yleft: -1.0, yright: 2.0, ..f };
        assert_eq!((g.eval(-1.0), g.eval(f64::INFINITY)), (-1.0, 2.0));
    }

    fn ramp(alpha: Option<Approx>) -> Ramp {
        // Lab of "#132B43" and "#56B1F7", as farver decodes them.
        let x = [0.0, 1.0];
        Ramp {
            values: None,
            lab: [
                approx(&x, &[16.850779893314083, 69.565125881010957]),
                approx(&x, &[-0.2951089752190883, -5.9043049797686269]),
                approx(&x, &[-17.888407877147195, -42.778366037596683]),
            ],
            alpha,
        }
    }

    fn strs(m: &Mapped) -> Vec<Option<&str>> {
        fn get(h: &Option<Hex>) -> Option<&str> {
            h.as_ref().map(Hex::as_str)
        }
        match m {
            Mapped::Coded { codes, colours } => codes.iter().map(|&c| get(&colours[c as usize])).collect(),
            Mapped::Rows(colours) => colours.iter().map(get).collect(),
        }
    }

    fn n_colours(m: &Mapped) -> usize {
        match m {
            Mapped::Coded { colours, .. } | Mapped::Rows(colours) => colours.len(),
        }
    }

    #[test]
    fn maps_through_oob_and_rescale() {
        let r = ramp(None);
        let x = [0.0, 10.0, 5.0, NA, 11.0, f64::INFINITY];
        let out = map_colour(x, [0.0, 10.0], Oob::Censor { only_finite: true }, Rescale::Linear { from: [0.0, 10.0] }, &r);
        let s = strs(&out);
        // Six rows, all distinct: coloured row by row.
        assert!(matches!(out, Mapped::Rows(_)));
        assert_eq!(s[0], Some("#132B43"));
        assert_eq!(s[1], Some("#56B1F7"));
        assert!(s[2].is_some());
        assert_eq!(&s[3..], &[None, None, None]);
    }

    #[test]
    fn codes_unique_values() {
        let r = ramp(None);
        let x: Vec<f64> = (0..10_000).map(|i| [0.0, 5.0, NA, 11.0, f64::INFINITY, -0.0][i % 6]).collect();
        let out = map_colour(x, [0.0, 10.0], Oob::Censor { only_finite: true }, Rescale::Linear { from: [0.0, 10.0] }, &r);
        assert!(matches!(out, Mapped::Coded { .. }));
        // NA and censored rows share the NA code, and -0 is 0; censor()
        // keeps Inf, which the ramp maps to NA (`yright`).
        assert_eq!(n_colours(&out), 4);
        let s = strs(&out);
        assert_eq!(&s[..6], &[Some("#132B43"), s[1], None, None, None, Some("#132B43")]);
        assert!(s[1].is_some());
    }

    #[test]
    fn single_value_uses_the_single_alpha_rule() {
        // Opaque at 0, half transparent at 1.
        let r = ramp(Some(approx(&[0.0, 1.0], &[1.0, 0.5])));
        let oob = Oob::Censor { only_finite: true };
        let lin = Rescale::Linear { from: [0.0, 10.0] };
        // Several values: an opaque row gets no suffix.
        let out = map_colour([0.0, 10.0, 0.0], [0.0, 10.0], oob, lin, &r);
        assert_eq!(strs(&out), [Some("#132B43"), Some("#56B1F780"), Some("#132B43")]);
        // One unique value (0 and -0 are equal): FF is kept.
        let out = map_colour([0.0, -0.0], [0.0, 10.0], oob, lin, &r);
        assert_eq!(strs(&out), [Some("#132B43FF"), Some("#132B43FF")]);
        // Rescale::Zero maps everything to 0.5, NA stays NA.
        let out = map_colour([3.0, NA], [3.0, 3.0], oob, Rescale::Zero, &r);
        let s = strs(&out);
        assert_eq!(s[1], None);
        assert_eq!(s[0].unwrap().len(), 9);
    }
}
