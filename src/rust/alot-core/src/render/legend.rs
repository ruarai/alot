//! Legends (ggplot2 R/guide-legend.R, R/guide-colorbar.R, R/guide-.R,
//! R/guides-.R): each guide is a gtable of keys (or a colourbar), labels
//! and a title, padded and backed by `legend.background`, and the guides of
//! one position are packed into a box (`Guides$package_box()`) that
//! `table_add_legends()` (R/plot-build.R) puts beside the panel.
//!
//! R resolves the theme and measures the text (R/render-legend.R); this
//! module does what `GuideLegend$measure_grobs()`, `arrange_layout()`,
//! `assemble_drawing()` and `Guide$add_title()` do with those sizes, solves
//! the tables as grid does (`layout::Table`) and draws the parts in the
//! order gtable draws them: background, title, then the rest as added.

use crate::render::axis::Side;
use crate::render::display::{Item, Rect};
use crate::render::layout::{Size, Table};
use crate::render::page::{LineStyle, Painter, RectEl};
use crate::render::panel::PointLayer;
use crate::render::title::Title;

/// A guide's body: a grid of keys with labels, or a colourbar.
pub enum Body {
    Keys(Keys),
    Bar(Bar),
}

/// `guide_legend()` keys (`GuideLegend$build_decor()`, `build_labels()`).
pub struct Keys {
    /// `nrow`, `ncol` and `legend.byrow`.
    pub nrow: usize,
    pub ncol: usize,
    pub byrow: bool,
    /// Each key's size in pixels: the largest of its glyphs and the default.
    pub key_w: Vec<f64>,
    pub key_h: Vec<f64>,
    /// `legend.key.width` and `legend.key.height`.
    pub default: (f64, f64),
    /// `legend.key`, drawn behind each key's glyphs.
    pub bg: Option<RectEl>,
    /// The glyphs of each key: layers of one point at the key's centre.
    pub marks: Vec<Vec<PointLayer>>,
    /// One label grob per key; empty for a guide without labels.
    pub labels: Vec<Title>,
    /// `legend.key.spacing.x` and `.y`.
    pub spacing: (f64, f64),
}

/// `guide_colourbar()` as a raster.
pub struct Bar {
    /// `legend.key.width` and `.height` (already scaled for the bar).
    pub size: (f64, f64),
    pub horizontal: bool,
    /// The colours from low to high.
    pub image: Vec<[u8; 4]>,
    pub frame: Option<RectEl>,
    pub ticks: Option<BarTicks>,
    /// One grob with the labels at their breaks.
    pub labels: Option<Title>,
}

/// `Guide$build_ticks()` for a colourbar: both sides, `len` each.
pub struct BarTicks {
    pub pos: Vec<f64>,
    pub len: [f64; 2],
    pub style: LineStyle,
}

pub struct Guide {
    pub body: Body,
    pub title: Option<Title>,
    pub title_position: Side,
    /// `rotate_just(element = legend.title)`.
    pub title_just: (f64, f64),
    pub text_position: Side,
    /// `legend.margin` as `[top, right, bottom, left]`.
    pub padding: [f64; 4],
    pub background: Option<RectEl>,
}

/// What a cell of a guide's table holds.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Part {
    Background,
    Title,
    Key(usize),
    Label(usize),
    Bar,
    Frame,
    Ticks,
    BarLabels,
}

/// The size a grob has in a gtable (`width_cm()`, `height_cm()`): a
/// `titleGrob()` with a margin in one direction only has a `null` size in
/// the other, which converts to 0.
fn grob_size(t: &Title) -> (f64, f64) {
    let g = &t.grob;
    let w = if g.margin_x == g.margin_y || g.margin_x { g.width() } else { 0.0 };
    let h = if g.margin_x == g.margin_y || g.margin_y { g.height() } else { 0.0 };
    (w, h)
}

/// `vec_interleave()` of equal-length vectors, without the last element
/// (`head(, -1)`).
fn interleave(parts: &[&[f64]]) -> Vec<f64> {
    let n = parts[0].len();
    let mut out: Vec<f64> = (0..n).flat_map(|i| parts.iter().map(move |p| p[i])).collect();
    out.pop();
    out
}

fn max_by(n: usize, v: impl Iterator<Item = (usize, f64)>) -> Vec<f64> {
    let mut out = vec![0.0f64; n];
    for (i, x) in v {
        out[i] = out[i].max(x);
    }
    out
}

impl Guide {
    /// `(row, col)` of break `i` (0-based): `arrange_layout()`.
    fn slot(keys: &Keys, i: usize) -> (usize, usize) {
        if keys.byrow { (i / keys.ncol, i % keys.ncol) } else { (i % keys.nrow, i / keys.nrow) }
    }

    /// The guide's gtable: `measure_grobs()` (sizes), `arrange_layout()`,
    /// `assemble_drawing()`, with the cells' contents in `Part`s in cell
    /// order.
    fn assemble(&self) -> (Table, Vec<Part>) {
        let mut t = Table::default();
        let mut parts = Vec::new();
        let text = self.text_position;
        // The key and label cells of each break, 0-based.
        let (widths, heights): (Vec<f64>, Vec<f64>);
        let mut cells: Vec<(Part, usize, usize, usize, usize)> = Vec::new();
        match &self.body {
            Body::Keys(k) => {
                let n = k.key_w.len();
                let (nrow, ncol) = (k.nrow, k.ncol);
                let slots: Vec<(usize, usize)> = (0..n).map(|i| Self::slot(k, i)).collect();
                let col_of = |v: &[f64]| max_by(ncol, slots.iter().enumerate().map(|(i, s)| (s.1, v[i])));
                let row_of = |v: &[f64]| max_by(nrow, slots.iter().enumerate().map(|(i, s)| (s.0, v[i])));
                let key_widths: Vec<f64> = col_of(&k.key_w).into_iter().map(|w| w.max(k.default.0)).collect();
                let key_heights: Vec<f64> = row_of(&k.key_h).into_iter().map(|h| h.max(k.default.1)).collect();
                let sizes: Vec<(f64, f64)> = if k.labels.is_empty() { vec![(0.0, 0.0); n] } else { k.labels.iter().map(grob_size).collect() };
                let label_widths = col_of(&sizes.iter().map(|s| s.0).collect::<Vec<_>>());
                let label_heights = row_of(&sizes.iter().map(|s| s.1).collect::<Vec<_>>());
                let hgap = vec![k.spacing.0; ncol];
                let vgap = vec![k.spacing.1; nrow];
                let pmax = |a: &[f64], b: &[f64]| a.iter().zip(b).map(|(x, y)| x.max(*y)).collect::<Vec<f64>>();
                widths = match text {
                    Side::Left => interleave(&[&label_widths, &key_widths, &hgap]),
                    Side::Right => interleave(&[&key_widths, &label_widths, &hgap]),
                    _ => interleave(&[&pmax(&label_widths, &key_widths), &hgap]),
                };
                heights = match text {
                    Side::Top => interleave(&[&label_heights, &key_heights, &vgap]),
                    Side::Bottom => interleave(&[&key_heights, &label_heights, &vgap]),
                    _ => interleave(&[&pmax(&label_heights, &key_heights), &vgap]),
                };
                for (i, &(row, col)) in slots.iter().enumerate() {
                    // 1-based, as arrange_layout() counts.
                    let (row, col) = (row + 1, col + 1);
                    let mut key_row = row * 2 - 1;
                    let mut key_col = col * 2 - 1;
                    key_row += match text { Side::Top => row, Side::Bottom => row - 1, _ => 0 };
                    let lab_row = match text { Side::Top => key_row - 1, Side::Bottom => key_row + 1, _ => key_row };
                    key_col += match text { Side::Left => col, Side::Right => col - 1, _ => 0 };
                    let lab_col = match text { Side::Left => key_col - 1, Side::Right => key_col + 1, _ => key_col };
                    cells.push((Part::Key(i), key_row - 1, key_col - 1, key_row - 1, key_col - 1));
                    if !k.labels.is_empty() {
                        cells.push((Part::Label(i), lab_row - 1, lab_col - 1, lab_row - 1, lab_col - 1));
                    }
                }
                // Keys first, then labels, as the table adds them.
                cells.sort_by_key(|c| matches!(c.0, Part::Label(_)));
            }
            Body::Bar(b) => {
                let (lw, lh) = b.labels.as_ref().map_or((0.0, 0.0), grob_size);
                widths = match text {
                    Side::Left => vec![lw, b.size.0],
                    Side::Right => vec![b.size.0, lw],
                    _ => vec![lw.max(b.size.0)],
                };
                heights = match text {
                    Side::Top => vec![lh, b.size.1],
                    Side::Bottom => vec![b.size.1, lh],
                    _ => vec![lh.max(b.size.1)],
                };
                let (kr, kc) = (if text == Side::Top { 1 } else { 0 }, if text == Side::Left { 1 } else { 0 });
                let (lr, lc) = match text {
                    Side::Top => (0, 0),
                    Side::Bottom => (1, 0),
                    Side::Left => (0, 0),
                    _ => (0, 1),
                };
                for part in [Part::Bar, Part::Frame, Part::Ticks] {
                    cells.push((part, kr, kc, kr, kc));
                }
                if b.labels.is_some() {
                    cells.push((Part::BarLabels, lr, lc, lr, lc));
                }
            }
        }
        t.widths = widths.into_iter().map(Size::Abs).collect();
        t.heights = heights.into_iter().map(Size::Abs).collect();
        for (part, r0, c0, r1, c1) in cells {
            t.add_cell("", r0, c0, r1, c1);
            parts.push(part);
        }
        // add_title()
        if let Some(title) = &self.title {
            let (tw, th) = grob_size(title);
            let (nr, nc) = (t.nrow(), t.ncol());
            match self.title_position {
                Side::Top => {
                    t.add_rows(&[Size::Abs(th)], 0);
                    t.add_cell("", 0, 0, 0, nc - 1);
                }
                Side::Bottom => {
                    t.add_rows(&[Size::Abs(th)], nr);
                    t.add_cell("", nr, 0, nr, nc - 1);
                }
                Side::Left => {
                    t.add_cols(&[Size::Abs(tw)], 0);
                    t.add_cell("", 0, 0, nr - 1, 0);
                }
                Side::Right => {
                    t.add_cols(&[Size::Abs(tw)], nc);
                    t.add_cell("", 0, nc, nr - 1, nc);
                }
            }
            parts.push(Part::Title);
            let sum = |s: &[Size]| s.iter().map(|x| if let Size::Abs(v) = x { *v } else { 0.0 }).sum::<f64>();
            match self.title_position {
                Side::Top | Side::Bottom => {
                    let extra = (tw - sum(&t.widths)).max(0.0);
                    if extra > 0.0 {
                        t.add_cols(&[Size::Abs(self.title_just.0 * extra)], 0);
                        t.add_cols(&[Size::Abs((1.0 - self.title_just.0) * extra)], t.ncol());
                    }
                }
                _ => {
                    let extra = (th - sum(&t.heights)).max(0.0);
                    if extra > 0.0 {
                        t.add_rows(&[Size::Abs((1.0 - self.title_just.1) * extra)], 0);
                        t.add_rows(&[Size::Abs(self.title_just.1 * extra)], t.nrow());
                    }
                }
            }
        }
        t.add_padding(self.padding);
        t.add_cell("", 0, 0, t.nrow() - 1, t.ncol() - 1);
        parts.push(Part::Background);
        (t, parts)
    }

    /// The width and height of the guide's gtable.
    pub fn size(&self) -> (f64, f64) {
        let (t, _) = self.assemble();
        let sum = |s: &[Size]| s.iter().map(|x| if let Size::Abs(v) = x { *v } else { 0.0 }).sum::<f64>();
        (sum(&t.widths), sum(&t.heights))
    }

    /// Draws the guide with its top left at `(x, y)`.
    pub fn draw(&self, p: &mut Painter, x: f64, y: f64) -> Option<()> {
        let (t, parts) = self.assemble();
        let (w, h) = self.size();
        let boxes = t.solve(w, h);
        let cell = |i: usize| {
            let b = &boxes[i];
            Rect { x0: x + b.x0, y0: y + b.y0, x1: x + b.x1, y1: y + b.y1 }
        };
        let order = |part: &Part| match part {
            Part::Background => 0,
            Part::Title => 1,
            _ => 2,
        };
        let mut idx: Vec<usize> = (0..parts.len()).collect();
        idx.sort_by_key(|&i| order(&parts[i]));
        for i in idx {
            let c = cell(i);
            match (parts[i], &self.body) {
                (Part::Background, _) => {
                    if let Some(bg) = &self.background {
                        p.rect(&c, bg);
                    }
                }
                (Part::Title, _) => self.title.as_ref()?.draw(p, &c)?,
                (Part::Key(k), Body::Keys(keys)) => {
                    if let Some(bg) = &keys.bg {
                        p.rect(&c, bg);
                    }
                    for mark in &keys.marks[k] {
                        p.list.push(Item::Points(mark.batch(&c, p.threads)));
                    }
                }
                (Part::Label(k), Body::Keys(keys)) => keys.labels[k].draw(p, &c)?,
                (Part::Bar, Body::Bar(b)) => p.raster(&c, &b.image, b.horizontal),
                (Part::Frame, Body::Bar(b)) => {
                    if let Some(frame) = &b.frame {
                        p.rect(&c, frame);
                    }
                }
                (Part::Ticks, Body::Bar(b)) => {
                    if let Some(ticks) = &b.ticks {
                        draw_ticks(p, &c, b.horizontal, ticks);
                    }
                }
                (Part::BarLabels, Body::Bar(b)) => b.labels.as_ref()?.draw(p, &c)?,
                _ => return None,
            }
        }
        Some(())
    }
}

/// `GuideColourbar$build_ticks()`: a segment from each side's edge inward
/// for every break, the first side (right, or bottom) first.
fn draw_ticks(p: &mut Painter, c: &Rect, horizontal: bool, ticks: &BarTicks) {
    let (w, h) = (c.x1 - c.x0, c.y1 - c.y0);
    for (side, &len) in ticks.len.iter().enumerate() {
        let lines = ticks
            .pos
            .iter()
            .map(|&v| {
                if horizontal {
                    let x = c.x0 + v * w;
                    let (edge, inner) = if side == 0 { (c.y1, c.y1 - len) } else { (c.y0, c.y0 + len) };
                    vec![[x, inner], [x, edge]]
                } else {
                    let y = c.y1 - v * h;
                    let (edge, inner) = if side == 0 { (c.x1, c.x1 - len) } else { (c.x0, c.x0 + len) };
                    vec![[inner, y], [edge, y]]
                }
            })
            .collect();
        p.lines(lines, &ticks.style);
    }
}

/// The guides of one position (`Guides$package_box()`).
pub struct LegendGroup {
    /// `legend.box` is horizontal.
    pub horizontal: bool,
    /// `legend.spacing.x` or `.y` between the guides.
    pub spacing: f64,
    /// `legend.box.just`: where each guide sits in its share of the box.
    pub box_just: (f64, f64),
    /// `legend.justification.<position>`: where the box sits in its cell.
    pub global_just: (f64, f64),
    pub guides: Vec<Guide>,
}

impl LegendGroup {
    /// The box's width and height: `gtable_width()` and `gtable_height()`
    /// of the `guide-box`.
    pub fn size(&self) -> (f64, f64) {
        let sizes: Vec<(f64, f64)> = self.guides.iter().map(Guide::size).collect();
        let gaps = self.spacing * (sizes.len().saturating_sub(1)) as f64;
        let max = |f: fn(&(f64, f64)) -> f64| sizes.iter().map(f).fold(0.0, f64::max);
        let sum = |f: fn(&(f64, f64)) -> f64| sizes.iter().map(f).sum::<f64>();
        if self.horizontal {
            (sum(|s| s.0) + gaps, max(|s| s.1))
        } else {
            (max(|s| s.0), sum(|s| s.1) + gaps)
        }
    }

    /// Draws the box in `cell`, justified by `legend.justification`.
    pub fn draw(&self, p: &mut Painter, cell: &Rect) -> Option<()> {
        let (w, h) = self.size();
        let x0 = cell.x0 + self.global_just.0 * ((cell.x1 - cell.x0) - w);
        let y0 = cell.y0 + (1.0 - self.global_just.1) * ((cell.y1 - cell.y0) - h);
        let (bx, by) = self.box_just;
        let mut at = 0.0;
        for g in &self.guides {
            let (gw, gh) = g.size();
            if self.horizontal {
                g.draw(p, x0 + at, y0 + (1.0 - by) * (h - gh))?;
                at += gw + self.spacing;
            } else {
                g.draw(p, x0 + bx * (w - gw), y0 + at)?;
                at += gh + self.spacing;
            }
        }
        Some(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::layout::TitleGrob;
    use crate::render::page::TextStyle;

    fn title(w: f64, h: f64) -> Title {
        Title {
            grob: TitleGrob { labels: vec![(w, h)], descent: 0.0, angle: 0.0, hjust: 0.0, vjust: 0.5, margin: [0.0; 4], margin_x: true, margin_y: true },
            labels: vec!["x".into()],
            x: None,
            y: None,
            just: (0.0, 0.5),
            style: TextStyle { font: 0, size: 10.0, line: 12.0, colour: [0, 0, 0, 255] },
            check_overlap: false,
        }
    }

    fn keys(n: usize, nrow: usize, ncol: usize, byrow: bool) -> Keys {
        Keys {
            nrow,
            ncol,
            byrow,
            key_w: vec![10.0; n],
            key_h: vec![10.0; n],
            default: (10.0, 10.0),
            bg: None,
            marks: (0..n).map(|_| Vec::new()).collect(),
            labels: (0..n).map(|i| title(20.0 + i as f64, 8.0)).collect(),
            spacing: (3.0, 0.0),
        }
    }

    fn guide(body: Body, title_position: Side, title: Option<Title>) -> Guide {
        Guide { body, title, title_position, title_just: (0.0, 0.5), text_position: Side::Right, padding: [1.0, 2.0, 3.0, 4.0], background: None }
    }

    #[test]
    fn a_vertical_legend_stacks_keys_with_labels_beside_them() {
        let g = guide(Body::Keys(keys(3, 3, 1, false)), Side::Top, Some(title(30.0, 12.0)));
        let (t, _) = g.assemble();
        // Keys 10 + labels (widest 22), padding 4 + 2; title row 12, keys
        // 3 x 10, padding 1 + 3.
        assert_eq!(g.size(), (4.0 + 10.0 + 22.0 + 2.0 + 0.0, 1.0 + 12.0 + 30.0 + 3.0));
        assert_eq!(t.ncol(), 2 + 2);
    }

    #[test]
    fn a_title_wider_than_the_table_adds_columns_by_its_justification() {
        let mut g = guide(Body::Keys(keys(1, 1, 1, false)), Side::Top, Some(title(60.0, 12.0)));
        g.title_just = (0.25, 0.5);
        // Table 10 + 20 = 30 wide; the title is 60: 30 extra, a quarter on the left.
        let (t, _) = g.assemble();
        assert_eq!(&t.widths[1..4], &[Size::Abs(7.5), Size::Abs(10.0), Size::Abs(20.0)]);
        assert_eq!(g.size().0, 4.0 + 60.0 + 2.0);
    }

    #[test]
    fn keys_fill_columns_first_unless_by_row() {
        let k = keys(5, 2, 3, false);
        let slots: Vec<_> = (0..5).map(|i| Guide::slot(&k, i)).collect();
        assert_eq!(slots, vec![(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)]);
        let k = keys(5, 2, 3, true);
        let slots: Vec<_> = (0..5).map(|i| Guide::slot(&k, i)).collect();
        assert_eq!(slots, vec![(0, 0), (0, 1), (0, 2), (1, 0), (1, 1)]);
    }

    #[test]
    fn a_vertical_box_is_as_wide_as_its_widest_guide_and_as_tall_as_all_plus_spacing() {
        let a = guide(Body::Keys(keys(2, 2, 1, false)), Side::Top, None);
        let b = guide(Body::Keys(keys(1, 1, 1, false)), Side::Top, None);
        let (wa, ha) = a.size();
        let (wb, hb) = b.size();
        let group = LegendGroup { horizontal: false, spacing: 7.0, box_just: (0.0, 1.0), global_just: (0.5, 0.5), guides: vec![a, b] };
        assert_eq!(group.size(), (wa.max(wb), ha + hb + 7.0));
    }
}
