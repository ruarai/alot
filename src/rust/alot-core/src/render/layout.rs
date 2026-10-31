//! The page layout (PHASE2.md, Architecture 3): a gtable-like table of
//! rows and columns solved as grid's layout does, and the assembly of a
//! single-panel plot's table as `ggplot_gtable()` does it.
//!
//! - **Table** mirrors gtable's `gtable_add_rows()`, `gtable_add_cols()`,
//!   `gtable_add_padding()` and `gtable_add_grob()` on a layout of
//!   absolute and `null` sizes. Units that mix `null` with absolute parts
//!   (`sum(0.5null, 1cm)`) evaluate their `null` parts as 0 in a layout, so
//!   they are absolute sizes here, converted to pixels by the caller. Text
//!   sizes are measured by [`TitleGrob`] from string metrics.
//! - **Solve** is grid's `calcViewportLayout()` (R 4.6.1
//!   src/library/grid/src/layout.c): known sizes first, then respected
//!   `null` sizes, then the remaining `null` sizes, and `subRegion()` to
//!   place the layout centred on the page.
//! - **Plot table** is `FacetNull$draw_panels()` and `Facet$draw_labels()`
//!   (ggplot2 R/facet-null.R, R/facet-.R), `table_add_legends()`, the
//!   title, subtitle and caption rows and `table_add_tag()` of
//!   `ggplot_gtable()` (R/plot-build.R), and the plot margin.

use std::f64::consts::PI;

/// A row height or column width in pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Size {
    Abs(f64),
    /// A pure `null` unit, which shares the space left over.
    Null(f64),
}

/// A grob's place in the table; rows and columns are 0-based and inclusive.
#[derive(Clone, Debug, PartialEq)]
pub struct Cell {
    pub name: String,
    pub t: usize,
    pub l: usize,
    pub b: usize,
    pub r: usize,
}

/// A box in device pixels from the page's top left.
#[derive(Clone, Debug, PartialEq)]
pub struct Box {
    pub name: String,
    pub x0: f64,
    pub y0: f64,
    pub x1: f64,
    pub y1: f64,
}

/// A gtable: sizes, the grobs' cells in drawing order, and whether `null`
/// sizes keep their aspect ratio (`respect`).
#[derive(Clone, Debug, Default)]
pub struct Table {
    pub widths: Vec<Size>,
    pub heights: Vec<Size>,
    pub cells: Vec<Cell>,
    pub respect: bool,
}

impl Table {
    pub fn nrow(&self) -> usize {
        self.heights.len()
    }

    pub fn ncol(&self) -> usize {
        self.widths.len()
    }

    /// `gtable_add_rows()`: inserts `sizes` before row `pos` (0 is the top,
    /// `nrow()` the bottom); cells at or below `pos` move down.
    pub fn add_rows(&mut self, sizes: &[Size], pos: usize) {
        let n = sizes.len();
        self.heights.splice(pos..pos, sizes.iter().copied());
        for c in &mut self.cells {
            if c.t >= pos {
                c.t += n;
            }
            if c.b >= pos {
                c.b += n;
            }
        }
    }

    /// `gtable_add_cols()`.
    pub fn add_cols(&mut self, sizes: &[Size], pos: usize) {
        let n = sizes.len();
        self.widths.splice(pos..pos, sizes.iter().copied());
        for c in &mut self.cells {
            if c.l >= pos {
                c.l += n;
            }
            if c.r >= pos {
                c.r += n;
            }
        }
    }

    /// `gtable_add_padding()` with `[top, right, bottom, left]`.
    pub fn add_padding(&mut self, pad: [f64; 4]) {
        self.add_rows(&[Size::Abs(pad[0])], 0);
        self.add_cols(&[Size::Abs(pad[1])], self.ncol());
        self.add_rows(&[Size::Abs(pad[2])], self.nrow());
        self.add_cols(&[Size::Abs(pad[3])], 0);
    }

    /// `gtable_add_grob()`.
    pub fn add_cell(&mut self, name: &str, t: usize, l: usize, b: usize, r: usize) {
        self.cells.push(Cell { name: name.to_string(), t, l, b, r });
    }

    /// `find_panel()`: the extent of the cells named `panel*`.
    pub fn find_panel(&self) -> Option<(usize, usize, usize, usize)> {
        let mut it = self.cells.iter().filter(|c| c.name.starts_with("panel"));
        let first = it.next()?;
        Some(it.fold((first.t, first.l, first.b, first.r), |a, c| (a.0.min(c.t), a.1.min(c.l), a.2.max(c.b), a.3.max(c.r))))
    }

    /// `plot_extent()`: the extent of all cells.
    pub fn extent(&self) -> (usize, usize, usize, usize) {
        self.cells.iter().fold((usize::MAX, usize::MAX, 0, 0), |a, c| (a.0.min(c.t), a.1.min(c.l), a.2.max(c.b), a.3.max(c.r)))
    }

    /// The boxes of the cells on a `width` × `height` page, as grid's
    /// layout viewport places them (`subRegion()`, centred).
    pub fn solve(&self, width: f64, height: f64) -> Vec<Box> {
        let (w, h) = allocate(&self.widths, &self.heights, width, height, self.respect);
        let total_w: f64 = w.iter().sum();
        let total_h: f64 = h.iter().sum();
        let left = (width - total_w) / 2.0;
        let top = (height - total_h) / 2.0;
        let before = |v: &[f64], n: usize| v[..n].iter().sum::<f64>();
        self.cells
            .iter()
            .map(|c| Box {
                name: c.name.clone(),
                x0: left + before(&w, c.l),
                y0: top + before(&h, c.t),
                x1: left + before(&w, c.r + 1),
                y1: top + before(&h, c.b + 1),
            })
            .collect()
    }
}

/// grid's `allocationRemaining()`.
fn remaining(initial: f64, left: f64) -> bool {
    if initial == 0.0 {
        true
    } else if initial > 0.0 {
        left > 0.0
    } else {
        left < 0.0
    }
}

/// grid's `calcViewportLayout()`: the widths and heights of a layout on a
/// `width` × `height` page.
fn allocate(widths: &[Size], heights: &[Size], width: f64, height: f64, respect: bool) -> (Vec<f64>, Vec<f64>) {
    let known = |s: &[Size]| s.iter().map(|x| if let Size::Abs(v) = x { *v } else { 0.0 }).sum::<f64>();
    let nulls = |s: &[Size]| s.iter().map(|x| if let Size::Null(v) = x { *v } else { 0.0 }).sum::<f64>();
    let start = |s: &[Size]| s.iter().map(|x| if let Size::Abs(v) = x { *v } else { 0.0 }).collect::<Vec<f64>>();
    let (mut w, mut h) = (start(widths), start(heights));
    let mut left_w = width - known(widths);
    let mut left_h = height - known(heights);
    // Respected null sizes (with `respect = TRUE` all of them are).
    if respect && (remaining(width, left_w) || remaining(height, left_h)) {
        let (sum_w, sum_h) = (nulls(widths), nulls(heights));
        let (temp_w, temp_h) = (left_w, left_h);
        let (mut denom, mut mult) = if temp_h * sum_w > sum_h * temp_w { (sum_w, temp_w) } else { (sum_h, temp_h) };
        for (i, s) in widths.iter().enumerate() {
            if let Size::Null(v) = s {
                if sum_h == 0.0 {
                    (denom, mult) = (sum_w, temp_w);
                }
                w[i] = v / denom * mult;
                left_w -= w[i];
            }
        }
        for (i, s) in heights.iter().enumerate() {
            if let Size::Null(v) = s {
                if sum_w == 0.0 {
                    (denom, mult) = (sum_h, temp_h);
                }
                h[i] = v / denom * mult;
                left_h -= h[i];
            }
        }
    }
    // The remaining null sizes (all of them without `respect`).
    let rest = |sizes: &[Size], out: &mut [f64], parent: f64, left: f64| {
        let total = if respect { 0.0 } else { nulls(sizes) };
        if remaining(parent, left) && total > 0.0 {
            for (i, s) in sizes.iter().enumerate() {
                if let Size::Null(v) = s {
                    out[i] = left * v / total;
                }
            }
        }
    };
    rest(widths, &mut w, width, left_w);
    rest(heights, &mut h, height, left_h);
    (w, h)
}

/// The label(s) of a `titleGrob()` (ggplot2 R/margins.R): each string's
/// width and height as grid measures them (`GEStrWidth()`, `GEStrHeight()`).
#[derive(Clone, Debug)]
pub struct TitleGrob {
    /// `(width, height)` of each label in pixels.
    pub labels: Vec<(f64, f64)>,
    /// `font_descent()`: the descent of "gjpqyQ" in the label's font.
    pub descent: f64,
    /// Rotation in degrees.
    pub angle: f64,
    pub hjust: f64,
    pub vjust: f64,
    /// `[top, right, bottom, left]` in pixels.
    pub margin: [f64; 4],
    pub margin_x: bool,
    pub margin_y: bool,
}

impl TitleGrob {
    /// The extent of the labels' text rectangles, rotated about their
    /// anchors (grid's `textRect()` and the bounds of `gridText()`), plus
    /// the descent, as `titleGrob()` sets `width` and `height`.
    fn text_size(&self) -> (f64, f64) {
        let rot = self.angle.to_radians();
        let (sin, cos) = rot.sin_cos();
        let mut x = (f64::INFINITY, f64::NEG_INFINITY);
        let mut y = (f64::INFINITY, f64::NEG_INFINITY);
        for &(w, h) in &self.labels {
            for (cx, cy) in [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)] {
                let (px, py) = (cx - self.hjust * w, cy - self.vjust * h);
                let (rx, ry) = (px * cos - py * sin, px * sin + py * cos);
                x = (x.0.min(rx), x.1.max(rx));
                y = (y.0.min(ry), y.1.max(ry));
            }
        }
        if self.labels.is_empty() {
            return (0.0, 0.0);
        }
        // `(angle %% 360) / 180 * pi`
        let a = self.angle.rem_euclid(360.0) / 180.0 * PI;
        (x.1 - x.0 + a.sin().abs() * self.descent, y.1 - y.0 + a.cos().abs() * self.descent)
    }

    /// `widthDetails.titleGrob()`.
    pub fn width(&self) -> f64 {
        let (w, _) = self.text_size();
        if self.margin_x {
            self.margin[3] + w + self.margin[1]
        } else {
            w
        }
    }

    /// `heightDetails.titleGrob()`.
    pub fn height(&self) -> f64 {
        let (_, h) = self.text_size();
        if self.margin_y {
            self.margin[0] + h + self.margin[2]
        } else {
            h
        }
    }
}

/// A guide axis (`GuideAxis$measure_grobs()`, ggplot2 R/guide-axis.R): the
/// longest tick, then the labels (one grob per dodge row or column). Its
/// size across the axis is `ticks + labels`; the spacer is always 0.
pub fn axis_size(major: f64, minor: Option<f64>, labels: &[TitleGrob], vertical: bool) -> f64 {
    let tick = [0.0, major, minor.unwrap_or(0.0)].into_iter().fold(0.0, f64::max);
    tick + labels.iter().map(|l| if vertical { l.width() } else { l.height() }).sum::<f64>()
}

/// Where a plot tag goes (`plot.tag.position`, `plot.tag.location`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TagLocation {
    Margin,
    Plot,
    Panel,
}

#[derive(Clone, Debug)]
pub struct Tag {
    pub width: f64,
    pub height: f64,
    pub top: bool,
    pub left: bool,
    pub right: bool,
    pub bottom: bool,
    pub location: TagLocation,
}

/// A legend box: its size, with `box.spacing` before it.
#[derive(Clone, Copy, Debug)]
pub struct LegendBox {
    pub width: f64,
    pub height: f64,
}

/// `facet_wrap()` with fixed scales (`FacetWrap$draw_panels()`, ggplot2
/// R/facet-.R, R/facet-wrap.R): the panels' grid and what goes between.
#[derive(Clone, Debug, Default)]
pub struct WrapSpec {
    pub nrow: usize,
    pub ncol: usize,
    /// `(row, col)`, 0-based, of each panel.
    pub panels: Vec<(usize, usize)>,
    /// `panel.spacing.x` and `.y`.
    pub spacing: (f64, f64),
    /// The strips' height (`max_height()` of all of them), `None` if there
    /// are no strips.
    pub strip: Option<f64>,
}

/// Axis positions, in the order `weave_axes()` adds them.
pub const WRAP_SIDES: [&str; 4] = ["t", "b", "l", "r"];

impl WrapSpec {
    fn occupied(&self) -> Vec<Vec<bool>> {
        let mut m = vec![vec![false; self.ncol]; self.nrow];
        for &(r, c) in &self.panels {
            m[r][c] = true;
        }
        m
    }

    /// The axis of each side (top, bottom, left, right) drawn in each grid
    /// cell, `[side][row][col]`, as `attach_axes()` leaves them: only on the
    /// outer panels, and back on the panels next to an empty one. `has`:
    /// whether the scale has an axis at each side.
    pub fn axis_cells(&self, has: [bool; 4]) -> [Vec<Vec<bool>>; 4] {
        let (nr, nc) = (self.nrow, self.ncol);
        let occ = self.occupied();
        let mut out: [Vec<Vec<bool>>; 4] = std::array::from_fn(|k| {
            (0..nr).map(|r| (0..nc).map(|c| has[k] && occ[r][c] && match k {
                0 => r == 0,
                1 => r == nr - 1,
                2 => c == 0,
                _ => c == nc - 1,
            }).collect()).collect()
        });
        for r in 0..nr {
            for c in 0..nc {
                if !occ[r][c] {
                    continue;
                }
                let empty = |rr: isize, cc: isize| rr >= 0 && cc >= 0 && (rr as usize) < nr && (cc as usize) < nc && !occ[rr as usize][cc as usize];
                let (ri, ci) = (r as isize, c as isize);
                if empty(ri + 1, ci) { out[1][r][c] = has[1]; }
                if empty(ri - 1, ci) { out[0][r][c] = has[0]; }
                if empty(ri, ci + 1) { out[3][r][c] = has[3]; }
                if empty(ri, ci - 1) { out[2][r][c] = has[2]; }
            }
        }
        out
    }

    /// `measure_axes()`: the size of each row (top, bottom) or column
    /// (left, right) of axes, ignoring those that border an empty panel.
    fn measure(&self, side: usize, flags: &[Vec<bool>], size: f64) -> Vec<f64> {
        let occ = self.occupied();
        let rows = side < 2;
        let n = if rows { self.nrow } else { self.ncol };
        let shift: isize = [1, -1, 1, -1][side];
        let mut cm = vec![vec![0.0; self.ncol]; self.nrow];
        for r in 0..self.nrow {
            for c in 0..self.ncol {
                if flags[r][c] {
                    cm[r][c] = size;
                }
            }
        }
        for r in 0..self.nrow {
            for c in 0..self.ncol {
                if occ[r][c] {
                    continue;
                }
                let (rr, cc) = if rows { (r as isize + shift, c as isize) } else { (r as isize, c as isize + shift) };
                if rr >= 0 && cc >= 0 && (rr as usize) < self.nrow && (cc as usize) < self.ncol {
                    cm[rr as usize][cc as usize] = 0.0;
                }
            }
        }
        (0..n).map(|i| {
            if rows { cm[i].iter().cloned().fold(0.0, f64::max) } else { cm.iter().map(|row| row[i]).fold(0.0, f64::max) }
        }).collect()
    }

    /// `FacetWrap$draw_panels()`: `init_gtable()`, `attach_axes()` and
    /// `attach_strips()` for strips on top, placed inside.
    fn table(&self, s: &PlotSpec) -> Table {
        use Size::{Abs, Null};
        let mut t = Table {
            widths: vec![Null(1.0); self.ncol],
            heights: vec![Null(s.aspect.map_or(1.0, f64::abs)); self.nrow],
            cells: Vec::new(),
            respect: s.aspect.is_some(),
        };
        for c in 0..self.ncol {
            for r in 0..self.nrow {
                t.add_cell(&format!("panel-{}-{}", c + 1, r + 1), r, c, r, c);
            }
        }
        for i in (1..self.ncol).rev() {
            t.add_cols(&[Abs(self.spacing.0)], i);
        }
        for i in (1..self.nrow).rev() {
            t.add_rows(&[Abs(self.spacing.1)], i);
        }
        let flags = self.axis_cells(s.has_axis);
        let sizes = [s.axis_t, s.axis_b, s.axis_l, s.axis_r];
        for side in 0..4 {
            let m = self.measure(side, &flags[side], sizes[side]);
            weave(&mut t, side >= 2, -1 + (side % 2 == 1) as isize, &m, &format!("axis-{}", WRAP_SIDES[side]));
        }
        if let Some(h) = self.strip {
            let occ = self.occupied();
            let m: Vec<f64> = occ.iter().map(|row| if row.iter().any(|&o| o) { h } else { 0.0 }).collect();
            weave(&mut t, false, -1, &m, "strip-t");
        }
        t
    }
}

/// `weave_tables_row()` (columns when `cols`) with `shift`: a row (column)
/// of `sizes[i]` beside each row (column) of panels, and a cell for each
/// panel in it.
fn weave(t: &mut Table, cols: bool, shift: isize, sizes: &[f64], name: &str) {
    let panels: Vec<&Cell> = t.cells.iter().filter(|c| c.name.starts_with("panel")).collect();
    let uniq = |f: &dyn Fn(&Cell) -> usize| {
        let mut v: Vec<usize> = panels.iter().map(|c| f(c)).collect();
        v.sort();
        v.dedup();
        v
    };
    let (prow, pcol) = (uniq(&|c| c.t), uniq(&|c| c.l));
    let (along, across) = if cols { (pcol, prow) } else { (prow, pcol) };
    for i in (0..along.len()).rev() {
        let pos = (along[i] as isize + 1 + shift) as usize;
        if cols {
            t.add_cols(&[Size::Abs(sizes[i])], pos);
        } else {
            t.add_rows(&[Size::Abs(sizes[i])], pos);
        }
        for (j, &a) in across.iter().enumerate() {
            let label = format!("{}-{}-{}", name, j + 1, i + 1);
            if cols { t.add_cell(&label, a, pos, a, pos) } else { t.add_cell(&label, pos, a, pos, a) }
        }
    }
}

/// Everything the single-panel plot table needs, in pixels.
#[derive(Clone, Debug, Default)]
pub struct PlotSpec {
    /// The panel's aspect ratio (height / width), if respected.
    pub aspect: Option<f64>,
    /// Axis widths (left, right) and heights (top, bottom).
    pub axis_l: f64,
    pub axis_r: f64,
    pub axis_t: f64,
    pub axis_b: f64,
    /// Axis title heights (top, bottom) and widths (left, right).
    pub xlab_t: f64,
    pub xlab_b: f64,
    pub ylab_l: f64,
    pub ylab_r: f64,
    /// Legend boxes, `None` if absent.
    pub legend_right: Option<LegendBox>,
    pub legend_left: Option<LegendBox>,
    pub legend_bottom: Option<LegendBox>,
    pub legend_top: Option<LegendBox>,
    pub legend_inside: bool,
    pub legend_spacing: f64,
    /// `legend.location = "plot"`.
    pub legend_plot: bool,
    pub title: f64,
    pub subtitle: f64,
    pub caption: f64,
    /// `plot.title.position = "plot"`, `plot.caption.position = "plot"`.
    pub title_plot: bool,
    pub caption_plot: bool,
    pub tag: Option<Tag>,
    /// `plot.margin`: `[top, right, bottom, left]`.
    pub margin: [f64; 4],
    pub background: bool,
    /// `facet_wrap()`; `None` for a single panel.
    pub wrap: Option<WrapSpec>,
    /// With `wrap`: whether each axis (top, bottom, left, right) exists
    /// even where its size is 0.
    pub has_axis: [bool; 4],
}

/// The table `ggplot_gtable()` builds for a single panel (`FacetNull`) or
/// a `facet_wrap()`.
pub fn plot_table(s: &PlotSpec) -> Table {
    let t = if let Some(w) = &s.wrap { w.table(s) } else { single_table(s) };
    plot_table_rest(t, s)
}

fn single_table(s: &PlotSpec) -> Table {
    use Size::{Abs, Null};
    // FacetNull$draw_panels(): a 3 x 3 table, filled by column.
    let mut t = Table {
        widths: vec![Abs(s.axis_l), Null(1.0), Abs(s.axis_r)],
        heights: vec![Abs(s.axis_t), Null(s.aspect.map_or(1.0, f64::abs)), Abs(s.axis_b)],
        cells: Vec::new(),
        respect: s.aspect.is_some(),
    };
    for (name, r, c) in [
        ("spacer", 0, 0), ("axis-l", 1, 0), ("spacer", 2, 0),
        ("axis-t", 0, 1), ("panel", 1, 1), ("axis-b", 2, 1),
        ("spacer", 0, 2), ("axis-r", 1, 2), ("spacer", 2, 2),
    ] {
        t.add_cell(name, r, c, r, c);
    }
    t
}

fn plot_table_rest(mut t: Table, s: &PlotSpec) -> Table {
    use Size::Abs;
    // Facet$draw_labels()
    let (pt, pl, pb, pr) = t.find_panel().unwrap();
    t.add_rows(&[Abs(s.xlab_t)], 0);
    t.add_cell("xlab-t", 0, pl, 0, pr);
    t.add_rows(&[Abs(s.xlab_b)], t.nrow());
    t.add_cell("xlab-b", t.nrow() - 1, pl, t.nrow() - 1, pr);
    let (pt2, _, pb2, _) = t.find_panel().unwrap();
    let _ = (pt, pb);
    t.add_cols(&[Abs(s.ylab_l)], 0);
    t.add_cell("ylab-l", pt2, 0, pb2, 0);
    t.add_cols(&[Abs(s.ylab_r)], t.ncol());
    t.add_cell("ylab-r", pt2, t.ncol() - 1, pb2, t.ncol() - 1);

    // table_add_legends()
    let place = |t: &Table| if s.legend_plot { t.extent() } else { t.find_panel().unwrap() };
    let spacing = |l: &Option<LegendBox>| Abs(if l.is_some() { s.legend_spacing } else { 0.0 });
    let width = |l: &Option<LegendBox>| Abs(l.map_or(0.0, |l| l.width));
    let height = |l: &Option<LegendBox>| Abs(l.map_or(0.0, |l| l.height));
    let (pt, _, pb, _) = place(&t);
    t.add_cols(&[spacing(&s.legend_right)], t.ncol());
    t.add_cols(&[width(&s.legend_right)], t.ncol());
    t.add_cell("guide-box-right", pt, t.ncol() - 1, pb, t.ncol() - 1);
    t.add_cols(&[spacing(&s.legend_left)], 0);
    t.add_cols(&[width(&s.legend_left)], 0);
    t.add_cell("guide-box-left", pt, 0, pb, 0);
    let (_, pl, _, pr) = place(&t);
    t.add_rows(&[spacing(&s.legend_bottom)], t.nrow());
    t.add_rows(&[height(&s.legend_bottom)], t.nrow());
    t.add_cell("guide-box-bottom", t.nrow() - 1, pl, t.nrow() - 1, pr);
    t.add_rows(&[spacing(&s.legend_top)], 0);
    t.add_rows(&[height(&s.legend_top)], 0);
    t.add_cell("guide-box-top", 0, pl, 0, pr);
    let (pt, pl, pb, pr) = t.find_panel().unwrap();
    t.add_cell("guide-box-inside", pt, pl, pb, pr);

    // Title, subtitle and caption.
    let (_, pl, _, pr) = t.find_panel().unwrap();
    let (tl, tr) = if s.title_plot { (0, t.ncol() - 1) } else { (pl, pr) };
    let (cl, cr) = if s.caption_plot { (0, t.ncol() - 1) } else { (pl, pr) };
    t.add_rows(&[Abs(s.subtitle)], 0);
    t.add_cell("subtitle", 0, tl, 0, tr);
    t.add_rows(&[Abs(s.title)], 0);
    t.add_cell("title", 0, tl, 0, tr);
    t.add_rows(&[Abs(s.caption)], t.nrow());
    t.add_cell("caption", t.nrow() - 1, cl, t.nrow() - 1, cr);

    add_tag(&mut t, s.tag.as_ref());

    t.add_padding(s.margin);

    if s.background {
        // Added last but drawn first.
        let (n, m) = (t.nrow() - 1, t.ncol() - 1);
        t.cells.insert(0, Cell { name: "background".to_string(), t: 0, l: 0, b: n, r: m });
    }
    t
}

/// `table_add_tag()`.
fn add_tag(t: &mut Table, tag: Option<&Tag>) {
    t.add_padding([0.0; 4]);
    let Some(tag) = tag else { return };
    let (n_row, n_col) = (t.nrow(), t.ncol());
    if tag.location == TagLocation::Plot {
        t.add_cell("tag", 0, 0, n_row - 1, n_col - 1);
        return;
    }
    let (mut pt, mut pl, mut pb, mut pr) = if tag.location == TagLocation::Panel {
        t.find_panel().unwrap()
    } else {
        if tag.top {
            t.heights[0] = Size::Abs(tag.height);
        }
        if tag.left {
            t.widths[0] = Size::Abs(tag.width);
        }
        if tag.right {
            t.widths[n_col - 1] = Size::Abs(tag.width);
        }
        if tag.bottom {
            t.heights[n_row - 1] = Size::Abs(tag.height);
        }
        (0, 0, n_row - 1, n_col - 1)
    };
    if tag.top {
        pb = pt;
    }
    if tag.left {
        pr = pl;
    }
    if tag.right {
        pl = pr;
    }
    if tag.bottom {
        pt = pb;
    }
    t.add_cell("tag", pt, pl, pb, pr);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn abs(v: f64) -> Size {
        Size::Abs(v)
    }

    #[test]
    fn unrespected_null_takes_the_rest() {
        let mut t = Table { widths: vec![abs(10.0), Size::Null(1.0), Size::Null(3.0)], heights: vec![Size::Null(1.0)], ..Default::default() };
        t.add_cell("a", 0, 1, 0, 2);
        let b = t.solve(110.0, 50.0);
        assert_eq!((b[0].x0, b[0].x1, b[0].y0, b[0].y1), (10.0, 110.0, 0.0, 50.0));
    }

    #[test]
    fn respected_table_is_centred() {
        // A square panel (1 : 1) on a 200 x 100 page with 10 px beside it.
        let mut t = Table { widths: vec![abs(10.0), Size::Null(1.0)], heights: vec![Size::Null(1.0)], respect: true, ..Default::default() };
        t.add_cell("panel", 0, 1, 0, 1);
        let b = t.solve(200.0, 100.0);
        // The panel is 100 wide, limited by the 100 high page; with the 10 px
        // column the table is 110 wide, centred.
        assert!((b[0].x1 - b[0].x0 - 100.0).abs() < 1e-9);
        assert!((b[0].x0 - 55.0).abs() < 1e-9);
    }

    #[test]
    fn add_rows_shifts_cells() {
        let mut t = Table { widths: vec![Size::Null(1.0)], heights: vec![abs(1.0), abs(2.0)], ..Default::default() };
        t.add_cell("a", 1, 0, 1, 0);
        t.add_rows(&[abs(5.0)], 1);
        assert_eq!(t.cells[0].t, 2);
        t.add_rows(&[abs(5.0)], 0);
        assert_eq!((t.cells[0].t, t.cells[0].b), (3, 3));
    }

    fn wrap(n: usize, ncol: usize) -> WrapSpec {
        let nrow = n.div_ceil(ncol);
        WrapSpec { nrow, ncol, panels: (0..n).map(|i| (i / ncol, i % ncol)).collect(), spacing: (5.0, 7.0), strip: Some(10.0) }
    }

    #[test]
    fn wrap_axes_are_on_the_outer_panels_and_beside_empty_slots() {
        // Five panels in 2 x 3: the slot at (1, 2) is empty.
        let w = wrap(5, 3);
        let f = w.axis_cells([true; 4]);
        // Bottom: the last row, and (0, 2) above the empty slot.
        assert_eq!(f[1], vec![vec![false, false, true], vec![true, true, false]]);
        // Top: the first row only; left and right the outer columns, and
        // the right axis of (1, 1) beside the empty slot.
        assert_eq!(f[0], vec![vec![true; 3], vec![false; 3]]);
        assert_eq!(f[2], vec![vec![true, false, false], vec![true, false, false]]);
        assert_eq!(f[3], vec![vec![false, false, true], vec![false, true, false]]);
    }

    #[test]
    fn wrap_table_weaves_axes_strips_and_spacing_around_each_panel_row() {
        let w = wrap(4, 2);
        let s = PlotSpec { axis_t: 0.0, axis_b: 20.0, axis_l: 30.0, axis_r: 0.0, wrap: Some(w), has_axis: [false, true, true, false], ..Default::default() };
        let t = plot_table(&s);
        let boxes = t.solve(400.0, 300.0);
        let at = |n: &str| boxes.iter().find(|b| b.name == n).unwrap_or_else(|| panic!("{n}")).clone();
        // The strip sits just above its panel, 10 high; rows are 7 apart
        // with the bottom axis (20) between panels.
        let (strip, panel, below) = (at("strip-t-1-1"), at("panel-1-1"), at("panel-1-2"));
        assert!((strip.y1 - panel.y0).abs() < 1e-9 && (strip.y1 - strip.y0 - 10.0).abs() < 1e-9);
        assert!((at("axis-b-1-1").y0 - panel.y1).abs() < 1e-9);
        assert!((at("strip-t-1-2").y0 - at("axis-b-1-1").y1 - 7.0).abs() < 1e-9);
        assert!(below.y0 > panel.y1);
        // Spacing between columns; interior left axes have no room.
        assert!((at("panel-2-1").x0 - at("panel-1-1").x1 - 5.0).abs() < 1e-9);
        assert!((at("axis-l-1-1").x1 - panel.x0).abs() < 1e-9 && (at("axis-l-1-2").x1 - at("panel-2-1").x0).abs() < 1e-9);
    }

    #[test]
    fn rotated_title_adds_descent_across() {
        let g = TitleGrob { labels: vec![(40.0, 10.0)], descent: 3.0, angle: 90.0, hjust: 0.5, vjust: 1.0, margin: [0.0, 2.0, 0.0, 4.0], margin_x: true, margin_y: false };
        assert!((g.width() - (4.0 + 10.0 + 3.0 + 2.0)).abs() < 1e-9);
    }
}
