//! Grouped-kernel driver: the group index over `PANEL` × `group` and a
//! generic per-group runner that mirrors `Stat$compute_layer` /
//! `Stat$compute_panel` (ggplot2 R/stat-.R) without splitting the data.
//!
//! ggplot2 splits a layer with `dapply(data, "PANEL", ...)` (panels in
//! factor-code order, R/compat-plyr.R) and then `split(data, data$group)`
//! (groups in ascending integer order). Rows keep their input order within a
//! group. `GroupIndex` reproduces that order as a row permutation.

use std::collections::HashMap;

/// Rows of a layer, grouped and ordered as ggplot2 splits them.
#[derive(Debug, Clone, PartialEq)]
pub struct GroupIndex {
    /// Row permutation (0-based input rows). Group `g` is
    /// `order[offsets[g]..offsets[g + 1]]`, rows in input order.
    pub order: Vec<usize>,
    /// `n_groups + 1` offsets into `order`.
    pub offsets: Vec<usize>,
    /// 0-based ordinal of each group's panel among the panels present.
    pub panel: Vec<usize>,
}

impl GroupIndex {
    /// Builds the index from 1-based `PANEL` factor codes and, if given,
    /// `group` values. Returns `None` if a code or group is missing (ggplot2
    /// never produces those; the caller falls back), or if the lengths differ.
    pub fn new<P, G>(panel: P, group: Option<G>) -> Option<Self>
    where
        P: IntoIterator<Item = Option<i32>>,
        G: IntoIterator<Item = Option<i32>>,
    {
        let keys: Vec<(i32, i32)> = match group {
            Some(group) => {
                let mut group = group.into_iter();
                let keys = panel
                    .into_iter()
                    .map(|p| Some((p?, group.next()??)))
                    .collect::<Option<Vec<_>>>()?;
                if group.next().is_some() {
                    return None;
                }
                keys
            }
            None => panel.into_iter().map(|p| Some((p?, 0))).collect::<Option<Vec<_>>>()?,
        };
        Some(Self::from_keys(&keys))
    }

    /// Index over panels only, as `Position$compute_layer` splits.
    pub fn panels<P: IntoIterator<Item = Option<i32>>>(panel: P) -> Option<Self> {
        Self::new(panel, None::<std::iter::Empty<Option<i32>>>)
    }

    fn from_keys(keys: &[(i32, i32)]) -> Self {
        let n = keys.len();
        if n == 0 {
            return GroupIndex { order: Vec::new(), offsets: vec![0], panel: Vec::new() };
        }

        // Dense id per row, ascending in (panel, group), plus the panel of
        // each id. A direct table when the key space is small, else a hash
        // map of distinct keys sorted afterwards.
        let (pmin, pmax, gmin, gmax) = keys.iter().fold(
            (i32::MAX, i32::MIN, i32::MAX, i32::MIN),
            |(a, b, c, d), &(p, g)| (a.min(p), b.max(p), c.min(g), d.max(g)),
        );
        let pw = (pmax as i64 - pmin as i64 + 1) as u64;
        let gw = (gmax as i64 - gmin as i64 + 1) as u64;
        let mut row_id: Vec<u32> = Vec::with_capacity(n);
        let mut id_panel: Vec<i32> = Vec::new();

        if pw.saturating_mul(gw) <= (4 * n as u64).max(1 << 16) {
            let slot = |&(p, g): &(i32, i32)| ((p - pmin) as u64 * gw + (g - gmin) as u64) as usize;
            let mut rank = vec![u32::MAX; (pw * gw) as usize];
            for k in keys {
                rank[slot(k)] = 0;
            }
            let mut next = 0u32;
            for (s, r) in rank.iter_mut().enumerate() {
                if *r == 0 {
                    *r = next;
                    next += 1;
                    id_panel.push(pmin + (s as u64 / gw) as i32);
                }
            }
            row_id.extend(keys.iter().map(|k| rank[slot(k)]));
        } else {
            let mut seen: HashMap<(i32, i32), u32> = HashMap::new();
            let mut distinct: Vec<(i32, i32)> = Vec::new();
            let mut last: Option<((i32, i32), u32)> = None;
            for &k in keys {
                let id = match last {
                    Some((lk, lid)) if lk == k => lid,
                    _ => *seen.entry(k).or_insert_with(|| {
                        distinct.push(k);
                        (distinct.len() - 1) as u32
                    }),
                };
                last = Some((k, id));
                row_id.push(id);
            }
            let mut sorted: Vec<u32> = (0..distinct.len() as u32).collect();
            sorted.sort_unstable_by_key(|&i| distinct[i as usize]);
            let mut rank = vec![0u32; distinct.len()];
            for (r, &i) in sorted.iter().enumerate() {
                rank[i as usize] = r as u32;
                id_panel.push(distinct[i as usize].0);
            }
            for id in row_id.iter_mut() {
                *id = rank[*id as usize];
            }
        }

        // Counting sort of rows by id (stable, so input order within groups).
        let n_groups = id_panel.len();
        let mut offsets = vec![0usize; n_groups + 1];
        for &id in &row_id {
            offsets[id as usize + 1] += 1;
        }
        for g in 0..n_groups {
            offsets[g + 1] += offsets[g];
        }
        let mut cursor = offsets[..n_groups].to_vec();
        let mut order = vec![0usize; n];
        for (i, &id) in row_id.iter().enumerate() {
            order[cursor[id as usize]] = i;
            cursor[id as usize] += 1;
        }

        let mut panel = Vec::with_capacity(n_groups);
        let mut ordinal = 0usize;
        for g in 0..n_groups {
            if g > 0 && id_panel[g] != id_panel[g - 1] {
                ordinal += 1;
            }
            panel.push(ordinal);
        }

        GroupIndex { order, offsets, panel }
    }

    pub fn n_groups(&self) -> usize {
        self.offsets.len() - 1
    }

    pub fn n_panels(&self) -> usize {
        self.panel.last().map_or(0, |&p| p + 1)
    }

    /// Input rows of group `g`, in input order.
    pub fn rows(&self, g: usize) -> &[usize] {
        &self.order[self.offsets[g]..self.offsets[g + 1]]
    }
}

/// One output column of a kernel.
#[derive(Debug, Clone, PartialEq)]
pub enum Values {
    Double(Vec<Option<f64>>),
    Integer(Vec<Option<i32>>),
    Logical(Vec<Option<bool>>),
}

impl Values {
    pub fn len(&self) -> usize {
        match self {
            Values::Double(v) => v.len(),
            Values::Integer(v) => v.len(),
            Values::Logical(v) => v.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn same_type(&self, other: &Values) -> bool {
        std::mem::discriminant(self) == std::mem::discriminant(other)
    }

    fn append(&mut self, other: Values) {
        match (self, other) {
            (Values::Double(a), Values::Double(b)) => a.extend(b),
            (Values::Integer(a), Values::Integer(b)) => a.extend(b),
            (Values::Logical(a), Values::Logical(b)) => a.extend(b),
            _ => unreachable!("checked by same_type"),
        }
    }
}

/// Named output columns of a kernel, all of the same length.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Columns {
    pub names: Vec<String>,
    pub values: Vec<Values>,
}

impl Columns {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, name: &str, values: Values) -> &mut Self {
        self.names.push(name.to_string());
        self.values.push(values);
        self
    }

    /// Number of rows; 0 when there are no columns (ggplot2's `empty()`).
    pub fn n_rows(&self) -> usize {
        self.values.first().map_or(0, Values::len)
    }
}

/// Equality of two rows of a column, as `vctrs::vec_unique_count()` sees
/// it. `None` means the column cannot decide here, and the driver declines.
pub trait RowEq {
    fn row_eq(&self, i: usize, j: usize) -> Option<bool>;
}

/// Exact equality, for integer, logical and factor-code storage.
pub struct Exact<'a, T>(pub &'a [T]);

impl<T: PartialEq> RowEq for Exact<'_, T> {
    fn row_eq(&self, i: usize, j: usize) -> Option<bool> {
        Some(self.0[i] == self.0[j])
    }
}

/// Doubles as vctrs compares them: `NA` equals `NA`, `NaN` equals `NaN`,
/// the two differ, and other values use `==` (so `0 == -0`).
pub struct Dbl<'a>(pub &'a [f64]);

/// R's `NA_real_` is a NaN whose low word is 1954 (`R_IsNA`).
pub fn is_r_na(x: f64) -> bool {
    x.is_nan() && (x.to_bits() & 0xffff_ffff) == 1954
}

impl RowEq for Dbl<'_> {
    fn row_eq(&self, i: usize, j: usize) -> Option<bool> {
        let (a, b) = (self.0[i], self.0[j]);
        Some(match (a.is_nan(), b.is_nan()) {
            (false, false) => a == b,
            (true, true) => is_r_na(a) == is_r_na(b),
            _ => false,
        })
    }
}

/// A column the driver cannot compare; any check on it declines.
pub struct Undecidable;

impl RowEq for Undecidable {
    fn row_eq(&self, _: usize, _: usize) -> Option<bool> {
        None
    }
}

/// An input column the driver may carry through, as `compute_panel` does
/// for columns that are constant within a group.
pub struct Carry<'a> {
    pub name: &'a str,
    pub eq: &'a dyn RowEq,
}

/// The group a kernel is called on.
pub struct Group<'a> {
    /// Group ordinal in the index.
    pub index: usize,
    /// 0-based panel ordinal among the panels present.
    pub panel: usize,
    /// Input rows, in input order.
    pub rows: &'a [usize],
}

/// Output of one panel that produced rows.
#[derive(Debug, Clone, PartialEq)]
pub struct PanelOutput {
    /// Panel ordinal in the index.
    pub panel: usize,
    /// Number of output rows.
    pub n_rows: usize,
    /// Number of groups with output.
    pub n_groups: usize,
    /// Per carry column: not constant within some group of this panel, so
    /// ggplot2 drops it from the panel. Always false for kernel outputs.
    pub non_constant: Vec<bool>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Grouped {
    /// Kernel output of every non-empty group, concatenated in index order.
    pub columns: Columns,
    /// Per output row, the first input row of its group: carried columns
    /// are those rows' values.
    pub carry_rows: Vec<usize>,
    /// Panels that produced output, in order.
    pub panels: Vec<PanelOutput>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum GroupedError {
    /// A carry column could not be compared; the caller should fall back.
    Undecidable(String),
    /// The kernel returned different column names or types across groups.
    Mismatch(String),
}

/// Runs `kernel` once per group of `index` and combines the results as
/// `Stat$compute_panel` does (ggplot2 R/stat-.R), with `dapply()` over
/// panels around it:
///
/// - groups whose output has no rows contribute nothing;
/// - every other group gets each `carry` column not among its outputs,
///   with the value of the group's first row;
/// - a carry column that is not constant within any non-empty group of a
///   panel is flagged in that panel's `non_constant`, for the caller to drop
///   (and warn about) as `compute_panel` does.
///
/// All non-empty outputs must have the same column names and types.
pub fn run_grouped<F>(index: &GroupIndex, carry: &[Carry], mut kernel: F) -> Result<Grouped, GroupedError>
where
    F: FnMut(Group) -> Columns,
{
    let mut columns: Option<Columns> = None;
    let mut carry_rows = Vec::new();
    let mut panels: Vec<PanelOutput> = Vec::new();
    // Carry columns that the kernel outputs itself are never checked.
    let mut is_output = vec![false; carry.len()];

    for g in 0..index.n_groups() {
        let rows = index.rows(g);
        let panel = index.panel[g];
        let out = kernel(Group { index: g, panel, rows });
        let n_out = out.n_rows();
        if n_out == 0 {
            continue;
        }
        if out.values.iter().any(|v| v.len() != n_out) {
            return Err(GroupedError::Mismatch("kernel columns differ in length".into()));
        }

        match &mut columns {
            None => {
                for (c, flag) in carry.iter().zip(is_output.iter_mut()) {
                    *flag = out.names.iter().any(|n| n == c.name);
                }
                columns = Some(out);
            }
            Some(acc) => {
                let same = acc.names == out.names
                    && acc.values.iter().zip(&out.values).all(|(a, b)| a.same_type(b));
                if !same {
                    return Err(GroupedError::Mismatch("kernel output differs between groups".into()));
                }
                for (a, b) in acc.values.iter_mut().zip(out.values) {
                    a.append(b);
                }
            }
        }

        if panels.last().map_or(true, |p| p.panel != panel) {
            panels.push(PanelOutput { panel, n_rows: 0, n_groups: 0, non_constant: vec![false; carry.len()] });
        }
        let current = panels.last_mut().unwrap();
        current.n_rows += n_out;
        current.n_groups += 1;
        for (k, c) in carry.iter().enumerate() {
            if is_output[k] || current.non_constant[k] {
                continue;
            }
            for &r in &rows[1..] {
                match c.eq.row_eq(rows[0], r) {
                    Some(true) => {}
                    Some(false) => {
                        current.non_constant[k] = true;
                        break;
                    }
                    None => return Err(GroupedError::Undecidable(c.name.to_string())),
                }
            }
        }
        carry_rows.extend(std::iter::repeat(rows[0]).take(n_out));
    }

    Ok(Grouped { columns: columns.unwrap_or_default(), carry_rows, panels })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn some(v: &[i32]) -> Vec<Option<i32>> {
        v.iter().copied().map(Some).collect()
    }

    fn index(panel: &[i32], group: &[i32]) -> GroupIndex {
        GroupIndex::new(some(panel), Some(some(group))).unwrap()
    }

    #[test]
    fn orders_by_panel_then_group_keeping_row_order() {
        let ix = index(&[2, 1, 2, 1, 1, 2], &[3, -1, -1, 5, -1, 3]);
        assert_eq!(ix.order, vec![1, 4, 3, 2, 0, 5]);
        assert_eq!(ix.offsets, vec![0, 2, 3, 4, 6]);
        assert_eq!(ix.panel, vec![0, 0, 1, 1]);
        assert_eq!(ix.n_panels(), 2);
    }

    #[test]
    fn sparse_keys_match_dense_order() {
        let panel = [1, 3, 1, 3, 1];
        let group = [i32::MAX, -7, i32::MIN + 1, 0, i32::MAX];
        let ix = index(&panel, &group);
        assert_eq!(ix.order, vec![2, 0, 4, 1, 3]);
        assert_eq!(ix.offsets, vec![0, 1, 3, 4, 5]);
        assert_eq!(ix.panel, vec![0, 0, 1, 1]);
    }

    #[test]
    fn panels_only_and_missing_and_empty() {
        let ix = GroupIndex::panels(some(&[2, 1, 2])).unwrap();
        assert_eq!(ix.order, vec![1, 0, 2]);
        assert_eq!(ix.offsets, vec![0, 1, 3]);
        assert!(GroupIndex::new(vec![Some(1), None], Some(some(&[1, 1]))).is_none());
        assert!(GroupIndex::new(some(&[1, 1]), Some(vec![Some(1), None])).is_none());
        assert!(GroupIndex::new(some(&[1, 1]), Some(some(&[1]))).is_none());
        let ix = GroupIndex::new(Vec::new(), Some(Vec::new())).unwrap();
        assert_eq!(ix.n_groups(), 0);
        assert_eq!(ix.n_panels(), 0);
    }

    #[test]
    fn double_equality_follows_vctrs() {
        let na = f64::from_bits(0x7ff0_0000_0000_07a2);
        let v = [na, f64::NAN, 0.0, -0.0, na];
        let eq = Dbl(&v);
        assert_eq!(eq.row_eq(0, 4), Some(true));
        assert_eq!(eq.row_eq(0, 1), Some(false));
        assert_eq!(eq.row_eq(2, 3), Some(true));
        assert_eq!(eq.row_eq(1, 2), Some(false));
    }

    // Outputs the group's `x` values and its size, like a trivial stat.
    fn identity_kernel<'a>(x: &'a [f64]) -> impl FnMut(Group) -> Columns + 'a {
        move |g| {
            let mut out = Columns::new();
            out.push("x", Values::Double(g.rows.iter().map(|&r| Some(x[r])).collect()));
            out.push("n", Values::Integer(vec![Some(g.rows.len() as i32); g.rows.len()]));
            out
        }
    }

    #[test]
    fn concatenates_and_flags_non_constant_per_panel() {
        let ix = index(&[1, 1, 2, 2, 1], &[1, 2, 1, 1, 1]);
        let x = [10.0, 20.0, 30.0, 40.0, 50.0];
        let a = [1, 1, 1, 2, 3]; // varies within panel 2's group only
        let (ae, xe) = (Exact(&a[..]), Dbl(&x[..]));
        let carry = [Carry { name: "x", eq: &xe }, Carry { name: "a", eq: &ae }];
        let out = run_grouped(&ix, &carry, identity_kernel(&x)).unwrap();

        assert_eq!(out.columns.names, vec!["x", "n"]);
        assert_eq!(
            out.columns.values[0],
            Values::Double(vec![Some(10.0), Some(50.0), Some(20.0), Some(30.0), Some(40.0)])
        );
        assert_eq!(out.carry_rows, vec![0, 0, 1, 2, 2]);
        assert_eq!(
            out.panels,
            vec![
                PanelOutput { panel: 0, n_rows: 3, n_groups: 2, non_constant: vec![false, true] },
                PanelOutput { panel: 1, n_rows: 2, n_groups: 1, non_constant: vec![false, true] },
            ]
        );
    }

    #[test]
    fn empty_groups_are_skipped_and_undecidable_declines() {
        let ix = index(&[1, 1, 2], &[1, 2, 1]);
        let out = run_grouped(&ix, &[], |g| {
            let mut out = Columns::new();
            if g.index != 1 {
                out.push("y", Values::Logical(vec![Some(true)]));
            }
            out
        })
        .unwrap();
        assert_eq!(out.carry_rows, vec![0, 2]);
        assert_eq!(out.panels.iter().map(|p| p.panel).collect::<Vec<_>>(), vec![0, 1]);

        // Single-row groups need no comparison, so they never decline.
        let x = [1.0, 2.0, 3.0];
        let carry = [Carry { name: "s", eq: &Undecidable }];
        assert!(run_grouped(&ix, &carry, identity_kernel(&x)).is_ok());
        let ix = index(&[1, 1, 2], &[1, 1, 1]);
        let err = run_grouped(&ix, &carry, identity_kernel(&x)).unwrap_err();
        assert_eq!(err, GroupedError::Undecidable("s".into()));
    }

    #[test]
    fn mismatched_outputs_error() {
        let ix = index(&[1, 1], &[1, 2]);
        let err = run_grouped(&ix, &[], |g| {
            let mut out = Columns::new();
            if g.index == 0 {
                out.push("y", Values::Double(vec![Some(1.0)]));
            } else {
                out.push("y", Values::Integer(vec![Some(1)]));
            }
            out
        })
        .unwrap_err();
        assert!(matches!(err, GroupedError::Mismatch(_)));
    }
}
