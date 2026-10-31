//! The full tier's page (PHASE2.md, Architecture 5): a [`Painter`] turns the
//! grobs of a plot table into display-list items, and [`draw_page`] walks
//! the table's cells in the order `ggplot_gtable()` draws them.
//!
//! The drawers mirror what grid hands ragg: element rects and lines become
//! rect and path batches, text goes through `text::draw_runs` (as ragg's
//! `plot_text()` does) into image items.

use std::collections::HashMap;

use crate::render::agg::{Cap, Join, Rule};
use crate::render::axis::Axis;
use crate::render::display::{DisplayList, Item, Rect};
use crate::render::layout::{Box as Cell, Table};
use crate::render::panel::Panel;
use crate::render::paths::{PathBatch, PathSpec, Stroke};
use crate::render::rects::{RectBatch, RectSpec, RectStyle};
use crate::render::text::{self, Font, Hinted, Run};
use crate::render::title::Title;

/// A theme `element_line` as grid's polyline gpar: colour, width in
/// pixels, R's packed line type (0 solid), end and join.
#[derive(Clone, Copy, Debug)]
pub struct LineStyle {
    pub col: [u8; 4],
    pub lwd: f64,
    pub lty: u32,
    pub cap: Cap,
    pub join: Join,
}

/// A theme `element_rect`: fill, outline colour and width in pixels.
#[derive(Clone, Copy, Debug)]
pub struct RectEl {
    pub fill: [u8; 4],
    pub col: [u8; 4],
    pub lwd: f64,
    pub join: Join,
}

/// A theme `element_text`'s font and colour: an index into the page's
/// fonts, the size and line height in pixels.
#[derive(Clone, Copy, Debug)]
pub struct TextStyle {
    pub font: usize,
    pub size: f64,
    pub line: f64,
    pub colour: [u8; 4],
}

/// Collects display-list items.
pub struct Painter<'f, 'a> {
    pub list: DisplayList,
    fonts: &'f [Font<'a>],
    hinted: HashMap<(usize, u64), Option<Hinted<'f, 'a>>>,
    /// ragg's clip box for text: the whole page.
    page_clip: [i32; 4],
    /// Worker threads for placing points (0: the default).
    pub threads: usize,
}

impl<'f, 'a> Painter<'f, 'a> {
    pub fn new(fonts: &'f [Font<'a>], width: usize, height: usize) -> Self {
        Painter { list: DisplayList::new(), fonts, hinted: HashMap::new(), page_clip: [0, 0, width as i32 - 1, height as i32 - 1], threads: 0 }
    }

    pub fn push_clip(&mut self, r: Rect) {
        self.list.push(Item::PushClip(r));
    }

    pub fn pop_clip(&mut self) {
        self.list.push(Item::PopClip);
    }

    /// `rectGrob()` of one element rect over `r`.
    pub fn rect(&mut self, r: &Rect, el: &RectEl) {
        let spec = RectSpec { x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1, fill: el.fill, col: el.col, lwd: el.lwd };
        self.list.push(Item::Rects(RectBatch::new(vec![spec], RectStyle { join: el.join, mitre: 10.0, snap: true })));
    }

    /// `polylineGrob()` with one open polyline per entry of `lines`.
    pub fn lines(&mut self, lines: Vec<Vec<[f64; 2]>>, st: &LineStyle) {
        let specs: Vec<PathSpec> = lines
            .into_iter()
            .map(|l| PathSpec {
                rings: vec![l],
                closed: false,
                fill: [0; 4],
                rule: Rule::NonZero,
                col: st.col,
                stroke: Stroke { lwd: st.lwd, lty: st.lty, cap: st.cap, join: st.join, mitre: 10.0 },
            })
            .collect();
        if !specs.is_empty() {
            self.list.push(Item::Paths(PathBatch::new(&specs)));
        }
    }

    /// Text runs in one style. `None` if ragg's drawing of them isn't
    /// mirrored (a glyph missing from the font).
    pub fn text(&mut self, runs: &[Run], st: &TextStyle) -> Option<()> {
        if runs.is_empty() || st.colour[3] == 0 {
            return Some(());
        }
        let font = self.fonts.get(st.font)?;
        let key = (st.font, st.size.to_bits());
        let hinted = self.hinted.entry(key).or_insert_with(|| Hinted::new(font, st.size));
        let image = text::draw_runs(font, hinted.as_mut()?, st.size, st.line, runs, st.colour, self.page_clip)?;
        if let Some(image) = image {
            self.list.push(Item::Image(image));
        }
        Some(())
    }
}

/// What a plot's cells draw.
pub struct PageSpec {
    pub width: usize,
    pub height: usize,
    /// Device background, non-premultiplied RGBA.
    pub bg: [u8; 4],
    pub table: Table,
    /// `plot.background`, if drawn.
    pub background: Option<RectEl>,
    pub panel: Panel,
    /// Axes by cell name: "axis-t", "axis-l", "axis-r", "axis-b".
    pub axes: Vec<(String, Axis)>,
    /// Titles by cell name (axis titles, title, subtitle, caption, tag).
    pub titles: Vec<(String, Title)>,
    pub threads: usize,
}

fn rect_of(b: &Cell) -> Rect {
    Rect { x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1 }
}

/// Draws the page in gtable's order (R/plot-build.R, R/facet-null.R): the
/// background, the panel table (the panel, then the axes top, left, right,
/// bottom by their `z`), then the labels, legends and titles in the order
/// they were added. `None` if something can't be drawn as ragg does.
pub fn draw_page(spec: &PageSpec, fonts: &[Font]) -> Option<DisplayList> {
    let mut p = Painter::new(fonts, spec.width, spec.height);
    p.threads = spec.threads;
    p.list.push(Item::Clear(spec.bg));
    let boxes = spec.table.solve(spec.width as f64, spec.height as f64);
    let find = |name: &str| boxes.iter().find(|b| b.name == name);
    if let (Some(el), Some(b)) = (&spec.background, find("background")) {
        p.rect(&rect_of(b), el);
    }
    if let Some(b) = find("panel") {
        spec.panel.draw(&mut p, &rect_of(b));
    }
    for name in ["axis-t", "axis-l", "axis-r", "axis-b"] {
        if let (Some((_, axis)), Some(b)) = (spec.axes.iter().find(|(n, _)| n == name), find(name)) {
            axis.draw(&mut p, &rect_of(b))?;
        }
    }
    let early = ["background", "panel", "spacer", "axis-t", "axis-l", "axis-r", "axis-b"];
    for b in boxes.iter().filter(|b| !early.contains(&b.name.as_str())) {
        if let Some((_, title)) = spec.titles.iter().find(|(n, _)| *n == b.name) {
            title.draw(&mut p, &rect_of(b))?;
        }
    }
    Some(p.list)
}
