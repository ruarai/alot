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
}

/// The table `ggplot_gtable()` builds for a single panel (`FacetNull`).
pub fn plot_table(s: &PlotSpec) -> Table {
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

    #[test]
    fn rotated_title_adds_descent_across() {
        let g = TitleGrob { labels: vec![(40.0, 10.0)], descent: 3.0, angle: 90.0, hjust: 0.5, vjust: 1.0, margin: [0.0, 2.0, 0.0, 4.0], margin_x: true, margin_y: false };
        assert!((g.width() - (4.0 + 10.0 + 3.0 + 2.0)).abs() < 1e-9);
    }
}
