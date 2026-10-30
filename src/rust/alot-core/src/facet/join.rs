//! Assigns layer rows to layout rows on the facet variables, replacing
//! `join_keys()` + `match()` in `map_facet_data` (ggplot2 R/facet-.R).
//!
//! R turns each facet variable into codes in a shared value space: the data
//! column's factor codes, and the layout column's values matched to the same
//! levels. A row then joins the first layout row whose codes all equal its
//! own, as `match(keys$x, keys$y)` does. Codes are 0-based; a `None` or
//! out-of-range code never matches.

use std::collections::HashMap;
use std::hash::BuildHasherDefault;

use crate::scale::discrete::MixHasher;

enum Table {
    Dense(Vec<Option<usize>>),
    Hashed(HashMap<u64, usize, BuildHasherDefault<MixHasher>>),
}

/// Layout rows indexed by their codes.
pub struct Join {
    cards: Vec<usize>,
    table: Table,
}

impl Join {
    /// Index the `n_layout` layout rows. `layout` holds one code iterator
    /// per variable, `cards` the number of codes each variable can take and
    /// `n_data` the number of rows to be looked up (it sizes the table).
    /// `None` (decline) if the key space overflows `u64`.
    pub fn new<L>(layout: Vec<L>, cards: &[usize], n_layout: usize, n_data: usize) -> Option<Self>
    where
        L: Iterator<Item = Option<usize>>,
    {
        let space = cards.iter().try_fold(1u64, |acc, &c| acc.checked_mul(c as u64))?;
        let mut keys = vec![Some(0u64); n_layout];
        for (codes, &card) in layout.into_iter().zip(cards) {
            for (key, code) in keys.iter_mut().zip(codes) {
                *key = key.and_then(|k| push(k, code, card));
            }
        }

        // A dense key -> layout row table is fastest; past the data size it
        // would cost more to fill than the lookups save, so hash instead.
        let table = if space <= (n_data as u64).max(1 << 16) {
            let mut table = vec![None; space as usize];
            for (j, key) in keys.iter().enumerate().rev() {
                if let Some(k) = key {
                    table[*k as usize] = Some(j);
                }
            }
            Table::Dense(table)
        } else {
            let mut table = HashMap::default();
            for (j, key) in keys.iter().enumerate() {
                if let Some(k) = key {
                    table.entry(*k).or_insert(j);
                }
            }
            Table::Hashed(table)
        };
        Some(Join { cards: cards.to_vec(), table })
    }

    /// The 0-based index of the first layout row with `codes` (one per
    /// variable), or `None`.
    pub fn find(&self, codes: impl IntoIterator<Item = Option<usize>>) -> Option<usize> {
        let mut key = 0u64;
        for (code, &card) in codes.into_iter().zip(&self.cards) {
            key = push(key, code, card)?;
        }
        match &self.table {
            Table::Dense(t) => t[key as usize],
            Table::Hashed(t) => t.get(&key).copied(),
        }
    }
}

// Appends one mixed-radix digit; the key space was checked for overflow.
fn push(key: u64, code: Option<usize>, card: usize) -> Option<u64> {
    match code {
        Some(c) if c < card => Some(key * card as u64 + c as u64),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(data: &[Vec<Option<usize>>], layout: &[Vec<Option<usize>>], cards: &[usize]) -> Option<Vec<Option<usize>>> {
        let n = data.first().map_or(0, Vec::len);
        let n_layout = layout.first().map_or(0, Vec::len);
        let join = Join::new(layout.iter().map(|v| v.iter().copied()).collect(), cards, n_layout, n)?;
        Some((0..n).map(|i| join.find(data.iter().map(|v| v[i]))).collect())
    }

    #[test]
    fn one_variable() {
        let data = vec![vec![Some(2), Some(0), Some(1), Some(0)]];
        let layout = vec![vec![Some(0), Some(1), Some(2)]];
        assert_eq!(run(&data, &layout, &[3]), Some(vec![Some(2), Some(0), Some(1), Some(0)]));
    }

    #[test]
    fn values_missing_from_layout_and_none_codes_do_not_match() {
        let data = vec![vec![Some(0), Some(1), Some(2), None]];
        let layout = vec![vec![None, Some(1)]];
        assert_eq!(run(&data, &layout, &[3]), Some(vec![None, Some(1), None, None]));
    }

    #[test]
    fn two_variables_match_on_both() {
        let data = vec![vec![Some(0), Some(1), Some(1)], vec![Some(1), Some(0), Some(1)]];
        let layout = vec![
            vec![Some(0), Some(0), Some(1), Some(1)],
            vec![Some(0), Some(1), Some(0), Some(1)],
        ];
        assert_eq!(run(&data, &layout, &[2, 2]), Some(vec![Some(1), Some(2), Some(3)]));
    }

    #[test]
    fn duplicate_layout_rows_take_the_first() {
        let data = vec![vec![Some(1)]];
        let layout = vec![vec![Some(1), Some(0), Some(1)]];
        assert_eq!(run(&data, &layout, &[2]), Some(vec![Some(0)]));
        // The hashed path too.
        let big = 1 << 20;
        let data = vec![vec![Some(big - 1)]];
        let layout = vec![vec![Some(big - 1), Some(big - 1)]];
        assert_eq!(run(&data, &layout, &[big]), Some(vec![Some(0)]));
    }

    #[test]
    fn hashed_and_dense_agree() {
        let data = vec![vec![Some(5), Some(70_000), Some(3)], vec![Some(1), Some(0), Some(2)]];
        let layout = vec![vec![Some(70_000), Some(5)], vec![Some(0), Some(1)]];
        assert_eq!(run(&data, &layout, &[100_000, 3]), Some(vec![Some(1), Some(0), None]));
        let data = vec![vec![Some(5), Some(7), Some(3)], vec![Some(1), Some(0), Some(2)]];
        let layout = vec![vec![Some(7), Some(5)], vec![Some(0), Some(1)]];
        assert_eq!(run(&data, &layout, &[10, 3]), Some(vec![Some(1), Some(0), None]));
    }

    #[test]
    fn out_of_range_codes_do_not_match() {
        let data = vec![vec![Some(3)]];
        let layout = vec![vec![Some(3)]];
        assert_eq!(run(&data, &layout, &[3]), Some(vec![None]));
    }

    #[test]
    fn empty_inputs() {
        assert_eq!(run(&[vec![]], &[vec![Some(0)]], &[1]), Some(vec![]));
        assert_eq!(run(&[vec![Some(0)]], &[vec![]], &[1]), Some(vec![None]));
    }

    #[test]
    fn overflowing_key_space_declines() {
        let data = vec![vec![Some(0)], vec![Some(0)], vec![Some(0)]];
        let layout = data.clone();
        assert_eq!(run(&data, &layout, &[1 << 30, 1 << 30, 1 << 30]), None);
    }
}
