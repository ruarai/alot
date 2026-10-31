//! Legends (ggplot2 R/guide-legend.R, R/guide-colorbar.R, R/guide-.R,
//! R/guide-colorsteps.R, R/guide-bins.R, R/guides-.R): each guide is a
//! gtable of keys (or a colourbar, or a stack of bins), labels and a title,
//! padded and backed by `legend.background`, and the guides of one position
//! are packed into a box (`Guides$package_box()`) that `table_add_legends()`
//! (R/plot-build.R) puts beside the panel, or over it for inside legends.
//!
//! R resolves the theme and measures the text (R/render-legend.R); this
//! module does what `GuideLegend$measure_grobs()`, `arrange_layout()`,
//! `assemble_drawing()` and `Guide$add_title()` do with those sizes, solves
//! the tables as grid does (`layout::Table`) and draws the parts in the
//! order gtable draws them: background, title, then the rest as added.

use crate::render::agg::{Cap, Join};
use crate::render::axis::Side;
use crate::render::display::{Item, Rect};
use crate::render::layout::{Size, Table};
use crate::render::page::{LineStyle, Painter, RectEl};
use crate::render::panel::PointLayer;
use crate::render::rects::{RectBatch, RectSpec, RectStyle};
use crate::render::title::Title;

/// A guide's body: a grid of keys with labels, or a colourbar.
pub enum Body {
    Keys(Keys),
    Bar(Bar),
    Bins(Bins),
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
    /// The glyphs of each key, one per layer that draws one.
    pub marks: Vec<Vec<Glyph>>,
    /// `legend.key.justification`: each key (background and glyphs) is
    /// drawn in a box of its own size, justified in its cell.
    pub key_just: Option<(f64, f64)>,
    /// One label grob per key; empty for a guide without labels.
    pub labels: Vec<Title>,
    /// `legend.key.spacing.x` and `.y`.
    pub spacing: (f64, f64),
}

/// A key glyph (ggplot2 R/legend-draw.R), drawn in the key's box.
pub enum Glyph {
    /// `draw_key_point()`: a layer of one point at the key's centre.
    Point(PointLayer),
    /// `draw_key_polygon()` and `draw_key_rect()`: a `rectGrob()` centred
    /// in the key, `inset` pixels narrower and shorter than it, its
    /// dashes ended with `cap` (the layer's `lineend`). With `frac`, the
    /// rect is that share of the key's width and height instead
    /// (`rectGrob(width = 0.75, height = 0.5)` of `draw_key_boxplot()` and
    /// `draw_key_crossbar()`).
    Rect { inset: f64, el: RectEl, cap: Cap, frac: Option<(f64, f64)> },
    /// `draw_key_path()` (a segment across the middle) and
    /// `draw_key_timeseries()`: a polyline through points in npc of the
    /// key.
    Line { x: Vec<f64>, y: Vec<f64>, style: LineStyle },
    /// `draw_key_text()`: a title grob in the key.
    Text(Title),
}

impl Glyph {
    fn draw(&self, p: &mut Painter, c: &Rect) -> Option<()> {
        match self {
            Glyph::Point(l) => p.list.push(Item::Points(l.batch(c, p.threads))),
            Glyph::Rect { inset, el, cap, frac } => {
                let (cx, cy) = ((c.x0 + c.x1) / 2.0, (c.y0 + c.y1) / 2.0);
                let (hw, hh) = match frac {
                    Some((fw, fh)) => ((c.x1 - c.x0) * fw / 2.0, (c.y1 - c.y0) * fh / 2.0),
                    None => ((c.x1 - c.x0 - inset) / 2.0, (c.y1 - c.y0 - inset) / 2.0),
                };
                p.rect_capped(&Rect { x0: cx - hw, y0: cy - hh, x1: cx + hw, y1: cy + hh }, el, *cap);
            }
            Glyph::Line { x, y, style } => {
                let (w, h) = (c.x1 - c.x0, c.y1 - c.y0);
                let line = x.iter().zip(y).map(|(&x, &y)| [c.x0 + x * w, c.y1 - y * h]).collect();
                p.lines(vec![line], style);
            }
            Glyph::Text(t) => t.draw(p, c)?,
        }
        Some(())
    }
}

/// `guide_colourbar()` as a raster or rectangles, and
/// `guide_coloursteps()`.
pub struct Bar {
    /// `legend.key.width` and `.height` (already scaled for the bar).
    pub size: (f64, f64),
    pub horizontal: bool,
    /// The colours from low to high.
    pub image: Vec<[u8; 4]>,
    /// For rectangles and steps, each colour's span along the bar (npc
    /// from the bottom or left, low end first); `None` for the raster.
    pub rects: Option<Vec<(f64, f64)>>,
    pub frame: Option<RectEl>,
    pub ticks: Option<BarTicks>,
    /// One grob with the labels at their breaks.
    pub labels: Option<Title>,
}

/// `guide_bins()` (ggplot2 R/guide-bins.R): the keys stacked in one cell,
/// an axis line along the labels' side, ticks from that side inward and
/// one label grob.
pub struct Bins {
    pub horizontal: bool,
    /// Every key's size: the largest key's.
    pub key_size: (f64, f64),
    /// `legend.key`, the glyphs of each key, each key's own size and
    /// `legend.key.justification`, as for `Keys`.
    pub bg: Option<RectEl>,
    pub marks: Vec<Vec<Glyph>>,
    pub key_w: Vec<f64>,
    pub key_h: Vec<f64>,
    pub key_just: Option<(f64, f64)>,
    pub axis: Option<LineStyle>,
    /// Tick positions (npc along the cell, from the bottom or left), their
    /// length and style.
    pub ticks: Option<(Vec<f64>, f64, LineStyle)>,
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
    BinKeys,
    BinAxis,
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

/// The widths and heights of a guide of one key cell of `size` and one
/// label cell of `label` size on side `text` (a colourbar, or bins).
fn one_cell(text: Side, size: (f64, f64), label: (f64, f64)) -> (Vec<f64>, Vec<f64>) {
    let (lw, lh) = label;
    let widths = match text {
        Side::Left => vec![lw, size.0],
        Side::Right => vec![size.0, lw],
        _ => vec![lw.max(size.0)],
    };
    let heights = match text {
        Side::Top => vec![lh, size.1],
        Side::Bottom => vec![size.1, lh],
        _ => vec![lh.max(size.1)],
    };
    (widths, heights)
}

/// The key cell's and label cell's (row, column) for `one_cell()`.
fn one_cell_slots(text: Side) -> (usize, usize, usize, usize) {
    let (kr, kc) = (if text == Side::Top { 1 } else { 0 }, if text == Side::Left { 1 } else { 0 });
    let (lr, lc) = match text {
        Side::Top | Side::Left => (0, 0),
        Side::Bottom => (1, 0),
        Side::Right => (0, 1),
    };
    (kr, kc, lr, lc)
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
            Body::Bins(b) => {
                let n = b.marks.len() as f64;
                let size = if b.horizontal { (n * b.key_size.0, b.key_size.1) } else { (b.key_size.0, n * b.key_size.1) };
                let (lw, lh) = b.labels.as_ref().map_or((0.0, 0.0), grob_size);
                (widths, heights) = one_cell(text, size, (lw, lh));
                let (kr, kc, lr, lc) = one_cell_slots(text);
                for part in [Part::BinKeys, Part::BinAxis, Part::Ticks] {
                    cells.push((part, kr, kc, kr, kc));
                }
                if b.labels.is_some() {
                    cells.push((Part::BarLabels, lr, lc, lr, lc));
                }
            }
            Body::Bar(b) => {
                let (lw, lh) = b.labels.as_ref().map_or((0.0, 0.0), grob_size);
                (widths, heights) = one_cell(text, b.size, (lw, lh));
                let (kr, kc, lr, lc) = one_cell_slots(text);
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
                    draw_key(p, &c, keys.key_just.map(|j| (j, (keys.key_w[k], keys.key_h[k]))), keys.bg.as_ref(), &keys.marks[k])?;
                }
                (Part::BinKeys, Body::Bins(b)) => {
                    // The keys' gtable, centred in the cell as grid
                    // places a layout of absolute sizes.
                    let n = b.marks.len() as f64;
                    let (w, h) = b.key_size;
                    let (tw, th) = if b.horizontal { (n * w, h) } else { (w, n * h) };
                    let (x0, y0) = (c.x0 + (c.x1 - c.x0 - tw) / 2.0, c.y0 + (c.y1 - c.y0 - th) / 2.0);
                    for (k, marks) in b.marks.iter().enumerate() {
                        let (kx, ky) = if b.horizontal { (x0 + k as f64 * w, y0) } else { (x0, y0 + k as f64 * h) };
                        let kc = Rect { x0: kx, y0: ky, x1: kx + w, y1: ky + h };
                        draw_key(p, &kc, b.key_just.map(|j| (j, (b.key_w[k], b.key_h[k]))), b.bg.as_ref(), marks)?;
                    }
                }
                (Part::BinAxis, Body::Bins(b)) => {
                    if let Some(axis) = &b.axis {
                        let line = match self.text_position {
                            Side::Top => vec![[c.x0, c.y0], [c.x1, c.y0]],
                            Side::Bottom => vec![[c.x0, c.y1], [c.x1, c.y1]],
                            Side::Left => vec![[c.x0, c.y1], [c.x0, c.y0]],
                            Side::Right => vec![[c.x1, c.y1], [c.x1, c.y0]],
                        };
                        p.lines(vec![line], axis);
                    }
                }
                (Part::Ticks, Body::Bins(b)) => {
                    if let Some((pos, len, style)) = &b.ticks {
                        draw_bin_ticks(p, &c, self.text_position, pos, *len, style);
                    }
                }
                (Part::BarLabels, Body::Bins(b)) => b.labels.as_ref()?.draw(p, &c)?,
                (Part::Label(k), Body::Keys(keys)) => keys.labels[k].draw(p, &c)?,
                (Part::Bar, Body::Bar(b)) => match &b.rects {
                    None => p.raster(&c, &b.image, b.horizontal),
                    Some(rects) => draw_steps(p, &c, b.horizontal, rects, &b.image),
                },
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

/// One key's gTree in cell `c` (`GuideLegend$build_decor()`): with
/// `legend.key.justification` (`just`, with the key's own size) in a
/// viewport of the key's size justified in the cell; the key background,
/// then the glyphs.
fn draw_key(p: &mut Painter, c: &Rect, just: Option<((f64, f64), (f64, f64))>, bg: Option<&RectEl>, marks: &[Glyph]) -> Option<()> {
    let c = match just {
        Some(((jx, jy), (w, h))) => {
            let x0 = c.x0 + jx * (c.x1 - c.x0 - w);
            let y1 = c.y1 - jy * (c.y1 - c.y0 - h);
            Rect { x0, y0: y1 - h, x1: x0 + w, y1 }
        }
        None => *c,
    };
    if let Some(bg) = bg {
        p.rect(&c, bg);
    }
    for mark in marks {
        mark.draw(p, &c)?;
    }
    Some(())
}

/// `Guide$build_ticks()` for bins: one segment per position, from the
/// labels' side of the cell `len` inward (drawn from the inner end).
fn draw_bin_ticks(p: &mut Painter, c: &Rect, side: Side, pos: &[f64], len: f64, style: &LineStyle) {
    let lines = pos
        .iter()
        .map(|&v| {
            let x = c.x0 + v * (c.x1 - c.x0);
            let y = c.y1 - v * (c.y1 - c.y0);
            match side {
                Side::Right => vec![[c.x1 - len, y], [c.x1, y]],
                Side::Left => vec![[c.x0 + len, y], [c.x0, y]],
                Side::Top => vec![[x, c.y0 + len], [x, c.y0]],
                Side::Bottom => vec![[x, c.y1 - len], [x, c.y1]],
            }
        })
        .collect();
    p.lines(lines, style);
}

/// The bar's `rectGrob()` of rectangles or steps: one rect per colour,
/// filled, without an outline.
fn draw_steps(p: &mut Painter, c: &Rect, horizontal: bool, rects: &[(f64, f64)], colours: &[[u8; 4]]) {
    let (w, h) = (c.x1 - c.x0, c.y1 - c.y0);
    let specs = rects
        .iter()
        .zip(colours)
        .map(|(&(lo, hi), &fill)| {
            let (x0, y0, x1, y1) = if horizontal {
                (c.x0 + lo * w, c.y0, c.x0 + hi * w, c.y1)
            } else {
                (c.x0, c.y1 - hi * h, c.x1, c.y1 - lo * h)
            };
            RectSpec { x0, y0, x1, y1, fill, col: [0; 4], lwd: 0.0 }
        })
        .collect();
    p.list.push(Item::Rects(RectBatch::new(specs, RectStyle { join: Join::Round, mitre: 10.0, snap: true })));
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
    /// For inside legends, `legend.position.inside`: the point of the
    /// panel area (npc) the box is justified to; `None` outside, where the
    /// box is justified to the same point of its cell as its justification.
    pub inside: Option<(f64, f64)>,
    /// `legend.box.margin` as `[top, right, bottom, left]`.
    pub margin: [f64; 4],
    /// `legend.box.background`, behind the guides and the margin.
    pub background: Option<RectEl>,
    pub guides: Vec<Guide>,
}

impl LegendGroup {
    /// The guides' extent without the margin: the `guides` viewport's
    /// width and height.
    fn inner(&self) -> (f64, f64) {
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

    /// The box's width and height: `gtable_width()` and `gtable_height()`
    /// of the `guide-box`, the guides plus `legend.box.margin` (its
    /// justification margins are `null` and add nothing).
    pub fn size(&self) -> (f64, f64) {
        let (w, h) = self.inner();
        let [t, r, b, l] = self.margin;
        (w + l + r, h + t + b)
    }

    /// Draws the box in `cell`. The `guides` viewport, of the guides'
    /// extent, sits at the box's justification; the gtable laid out in it
    /// (margins included, `null` justification margins at zero) overflows
    /// it and is centred on it, as grid centres a layout larger than its
    /// viewport (grid src/layout.c `subRegion()`).
    pub fn draw(&self, p: &mut Painter, cell: &Rect) -> Option<()> {
        let (w, h) = self.inner();
        let [mt, mr, mb, ml] = self.margin;
        let (gx, gy) = self.global_just;
        let (ax, ay) = self.inside.unwrap_or(self.global_just);
        let (cw, ch) = (cell.x1 - cell.x0, cell.y1 - cell.y0);
        // The viewport's top left.
        let vx = cell.x0 + ax * cw - gx * w;
        let vy = cell.y1 - ay * ch - (1.0 - gy) * h;
        if let Some(bg) = &self.background {
            let (x0, y0) = (vx - (ml + mr) / 2.0, vy - (mt + mb) / 2.0);
            p.rect(&Rect { x0, y0, x1: x0 + w + ml + mr, y1: y0 + h + mt + mb }, bg);
        }
        let x0 = vx + (ml - mr) / 2.0;
        let y0 = vy + (mt - mb) / 2.0;
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
            key_just: None,
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
        let group = LegendGroup {
            horizontal: false, spacing: 7.0, box_just: (0.0, 1.0), global_just: (0.5, 0.5), inside: None,
            margin: [0.0; 4], background: None, guides: vec![a, b],
        };
        assert_eq!(group.size(), (wa.max(wb), ha + hb + 7.0));
        let group = LegendGroup { margin: [1.0, 2.0, 3.0, 4.0], ..group };
        assert_eq!(group.size(), (wa.max(wb) + 6.0, ha + hb + 7.0 + 4.0));
    }

    /// Draws with `f` on a `w` x `h` page and returns the pixels
    /// (`R | G << 8 | B << 16 | A << 24`).
    fn render(w: usize, h: usize, f: impl FnOnce(&mut Painter)) -> Vec<u32> {
        let fonts: Vec<crate::render::text::Font> = Vec::new();
        let mut p = Painter::new(&fonts, w, h);
        f(&mut p);
        crate::render::raster::render(&p.list, w, h, &crate::render::raster::Options { threads: 1, band_rows: 8 })
    }

    const RED: RectEl = RectEl { fill: [255, 0, 0, 255], col: [0; 4], lwd: 0.0, lty: 0, join: Join::Miter };

    #[test]
    fn an_inside_box_sits_at_its_position_by_its_justification_with_its_margin_around_it() {
        // One guide of 4 + 30 + 2 = 36 by 1 + 10 + 3 = 14, no labels.
        let mut k = keys(1, 1, 1, false);
        k.labels.clear();
        k.key_w = vec![30.0];
        let g = guide(Body::Keys(k), Side::Top, None);
        assert_eq!(g.size(), (36.0, 14.0));
        let group = LegendGroup {
            horizontal: false, spacing: 0.0, box_just: (0.0, 1.0), global_just: (1.0, 1.0), inside: Some((1.0, 1.0)),
            margin: [2.0, 4.0, 2.0, 4.0], background: Some(RED), guides: vec![g],
        };
        assert_eq!(group.size(), (44.0, 18.0));
        let cell = Rect { x0: 10.0, y0: 10.0, x1: 90.0, y1: 50.0 };
        let img = render(100, 60, |p| {
            group.draw(p, &cell);
        });
        let red = |x: usize, y: usize| img[y * 100 + x] & 0xFF;
        // The guides' viewport is justified to the cell's top right; the
        // layout with its margins overflows it, centred: the background
        // runs from x 90 - 36 - 4 = 50 to 94, y 10 - 2 = 8 to 26.
        assert!(red(50, 8) > 200 && red(93, 25) > 200);
        assert!(red(49, 15) == 0 && red(94, 15) == 0 && red(60, 26) == 0 && red(60, 7) == 0);
    }

    #[test]
    fn bins_stack_their_keys_in_one_cell_beside_the_labels() {
        let bins = Bins {
            horizontal: false, key_size: (10.0, 8.0), bg: Some(RED), marks: (0..3).map(|_| Vec::new()).collect(),
            key_w: vec![10.0; 3], key_h: vec![8.0; 3], key_just: None, axis: None, ticks: None,
            labels: Some(title(12.0, 0.0)),
        };
        let g = guide(Body::Bins(bins), Side::Top, None);
        let (t, parts) = g.assemble();
        assert_eq!(&t.widths[1..3], &[Size::Abs(10.0), Size::Abs(12.0)]);
        assert_eq!(g.size(), (4.0 + 10.0 + 12.0 + 2.0, 1.0 + 24.0 + 3.0));
        assert_eq!(&parts[..4], &[Part::BinKeys, Part::BinAxis, Part::Ticks, Part::BarLabels]);
    }

    #[test]
    fn steps_run_from_the_bottom_of_a_vertical_bar_and_the_left_of_a_horizontal_one() {
        let colours = [[255, 0, 0, 255], [0, 0, 255, 255]];
        let c = Rect { x0: 0.0, y0: 0.0, x1: 20.0, y1: 20.0 };
        let img = render(20, 20, |p| draw_steps(p, &c, false, &[(0.0, 0.25), (0.25, 1.0)], &colours));
        assert_eq!(img[18 * 20 + 5] & 0xFF, 255);
        assert_eq!(img[5 * 20 + 5] >> 16 & 0xFF, 255);
        let img = render(20, 20, |p| draw_steps(p, &c, true, &[(0.0, 0.25), (0.25, 1.0)], &colours));
        assert_eq!(img[5 * 20 + 2] & 0xFF, 255);
        assert_eq!(img[5 * 20 + 15] >> 16 & 0xFF, 255);
    }

    #[test]
    fn a_polygon_key_is_inset_by_its_line_width() {
        let glyph = Glyph::Rect { inset: 6.0, el: RED, cap: Cap::Butt, frac: None };
        let img = render(20, 20, |p| {
            glyph.draw(p, &Rect { x0: 0.0, y0: 0.0, x1: 20.0, y1: 20.0 });
        });
        // 3 pixels in on every side.
        assert_eq!(img[10 * 20 + 2] & 0xFF, 0);
        assert_eq!(img[10 * 20 + 3] & 0xFF, 255);
        assert_eq!(img[16 * 20 + 10] & 0xFF, 255);
        assert_eq!(img[17 * 20 + 10] & 0xFF, 0);
    }

    #[test]
    fn a_boxplot_key_box_is_a_share_of_the_key() {
        // rectGrob(width = 0.75, height = 0.5): x 2.5..17.5, y 5..15.
        let glyph = Glyph::Rect { inset: 6.0, el: RED, cap: Cap::Butt, frac: Some((0.75, 0.5)) };
        let img = render(20, 20, |p| {
            glyph.draw(p, &Rect { x0: 0.0, y0: 0.0, x1: 20.0, y1: 20.0 });
        });
        assert_eq!(img[10 * 20 + 1] & 0xFF, 0);
        assert_eq!(img[10 * 20 + 3] & 0xFF, 255);
        assert_eq!(img[10 * 20 + 16] & 0xFF, 255);
        assert_eq!(img[10 * 20 + 18] & 0xFF, 0);
        assert_eq!(img[3 * 20 + 10] & 0xFF, 0);
        assert_eq!(img[6 * 20 + 10] & 0xFF, 255);
        assert_eq!(img[16 * 20 + 10] & 0xFF, 0);
    }
}
