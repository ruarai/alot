//! First row of each distinct combination of facet values in one layer, to
//! shrink the input of `unique0(vec_rbind0(...))` in `combine_vars`
//! (ggplot2 R/facet-.R).
//!
//! Each column gives every row a `u64` key; R picks keys whose equality is
//! at least as strict as vctrs' (factor codes, double bits, string
//! pointers). Every vctrs-distinct row that comes first is then also a
//! first row here, so `unique0()` over the returned rows, in order, gives
//! the same result as over the whole layer.

use std::collections::HashMap;
use std::hash::BuildHasherDefault;

use crate::scale::discrete::MixHasher;

type CodeMap = HashMap<u64, u32, BuildHasherDefault<MixHasher>>;

/// 0-based, ascending rows of the first occurrence of each distinct key
/// combination among `n` rows. `key(col, row)` is the key of a cell;
/// `cards[col]` is `Some(k)` when that column's keys lie in `0..k`.
pub fn first_rows(n: usize, cards: &[Option<usize>], key: impl Fn(usize, usize) -> u64) -> Vec<usize> {
    if cards.is_empty() {
        return if n > 0 { vec![0] } else { vec![] };
    }

    // As ggplot2's id(): give each row a dense code over the columns seen so
    // far, combining one column at a time in mixed radix, and recode
    // densely whenever the radix product would outgrow a seen-table.
    let limit = n.max(1 << 16);
    let mut codes = vec![0u32; n];
    let mut k = 1usize;
    for (c, card) in cards.iter().enumerate() {
        let (col, m): (Box<dyn Fn(usize) -> u64>, usize) = match card {
            Some(m) => (Box::new(|i| key(c, i)), *m),
            None => {
                let (col, m) = densify((0..n).map(|i| key(c, i)), n);
                (Box::new(move |i| col[i] as u64), m)
            }
        };
        match k.checked_mul(m).filter(|&km| km <= limit) {
            Some(km) => {
                for (i, code) in codes.iter_mut().enumerate() {
                    *code = (*code as u64 * m as u64 + col(i)) as u32;
                }
                k = km;
            }
            None => {
                let (dense, distinct) = densify((0..n).map(|i| codes[i] as u64 * m as u64 + col(i)), n);
                codes = dense;
                k = distinct;
            }
        }
    }

    let mut seen = vec![false; k];
    let mut out = Vec::new();
    for (i, &code) in codes.iter().enumerate() {
        if !seen[code as usize] {
            seen[code as usize] = true;
            out.push(i);
        }
    }
    out
}

/// Codes `0..m` for the distinct values of `keys`, in order of first
/// appearance, and `m`.
fn densify(keys: impl Iterator<Item = u64>, n: usize) -> (Vec<u32>, usize) {
    let mut map = CodeMap::default();
    let mut out = Vec::with_capacity(n);
    // Runs of equal values are common in layer data; skip the lookup.
    let mut last: Option<(u64, u32)> = None;
    for k in keys {
        let code = match last {
            Some((lk, lc)) if lk == k => lc,
            _ => {
                let next = map.len() as u32;
                let code = *map.entry(k).or_insert(next);
                last = Some((k, code));
                code
            }
        };
        out.push(code);
    }
    let m = map.len();
    (out, m)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(cols: &[Vec<u64>], cards: &[Option<usize>]) -> Vec<usize> {
        let n = cols.first().map_or(0, Vec::len);
        first_rows(n, cards, |c, i| cols[c][i])
    }

    #[test]
    fn dense_one_column() {
        assert_eq!(run(&[vec![2, 0, 2, 1, 0]], &[Some(3)]), vec![0, 1, 3]);
    }

    #[test]
    fn dense_and_hashed_agree() {
        let cols = vec![vec![1, 0, 1, 1, 0, 2], vec![0, 0, 0, 1, 0, 1]];
        let dense = run(&cols, &[Some(3), Some(2)]);
        assert_eq!(dense, vec![0, 1, 3, 5]);
        assert_eq!(run(&cols, &[None, Some(2)]), dense);
        assert_eq!(run(&cols, &[Some(1 << 20), Some(1 << 20)]), dense);
    }

    #[test]
    fn hashed_large_keys() {
        let cols = vec![vec![u64::MAX, 7, u64::MAX, 7, 8]];
        assert_eq!(run(&cols, &[None]), vec![0, 1, 4]);
    }

    #[test]
    fn empty_and_no_columns() {
        assert_eq!(run(&[vec![]], &[Some(2)]), Vec::<usize>::new());
        assert_eq!(run(&[vec![]], &[None]), Vec::<usize>::new());
        assert_eq!(first_rows(3, &[], |_, _| 0), vec![0]);
        assert_eq!(first_rows(0, &[], |_, _| 0), Vec::<usize>::new());
    }
}
