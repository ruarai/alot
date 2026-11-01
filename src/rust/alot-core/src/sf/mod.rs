//! Simple features (sf) geometry, on coordinates already read from an sfc.

/// Bounding box `[xmin, ymin, xmax, ymax]` of XY coordinates, as sf's
/// `compute_bbox()` gives it for finite coordinates. `None` until the first
/// coordinate is added.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Bbox(pub Option<[f64; 4]>);

impl Bbox {
    /// Extends the box over `xy`, the column-major `n x 2` coordinates of
    /// one sfg matrix (or the `c(x, y)` of a POINT). Returns false, leaving
    /// the box as it was, if `xy` has an odd length or a non-finite value.
    pub fn extend(&mut self, xy: &[f64]) -> bool {
        if xy.len() % 2 != 0 || !xy.iter().all(|v| v.is_finite()) {
            return false;
        }
        let (xs, ys) = xy.split_at(xy.len() / 2);
        for (&x, &y) in xs.iter().zip(ys) {
            self.0 = Some(match self.0 {
                None => [x, y, x, y],
                Some([x0, y0, x1, y1]) => [x0.min(x), y0.min(y), x1.max(x), y1.max(y)],
            });
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bbox_spans_both_columns() {
        let mut b = Bbox::default();
        assert!(b.extend(&[1.0, 3.0, -2.0, 5.0, 0.0, 7.0]));
        assert_eq!(b.0, Some([-2.0, 0.0, 3.0, 7.0]));
        assert!(b.extend(&[10.0, -1.0]));
        assert_eq!(b.0, Some([-2.0, -1.0, 10.0, 7.0]));
    }

    #[test]
    fn bbox_rejects_non_finite_and_odd_input() {
        let mut b = Bbox::default();
        assert!(b.extend(&[1.0, 2.0]));
        assert!(!b.extend(&[f64::NAN, 2.0]));
        assert!(!b.extend(&[f64::INFINITY, 2.0]));
        assert!(!b.extend(&[1.0, 2.0, 3.0]));
        assert_eq!(b.0, Some([1.0, 2.0, 1.0, 2.0]));
    }

    #[test]
    fn empty_input_leaves_box_unset() {
        let mut b = Bbox::default();
        assert!(b.extend(&[]));
        assert_eq!(b.0, None);
    }
}
