//! The panel's background, grid lines and border (ggplot2 R/guides-grid.R
//! `guide_grid()`, `Coord$render_bg()` and `Coord$render_fg()`), drawn in
//! the panel's cell and clipped to it when the coord's `clip` is "on".

use crate::render::display::Item;
use crate::render::display::Rect;
use crate::render::layers::{PathLayer, RectLayer, TextLayer};
use crate::render::paths::PathBatch;
use crate::render::page::{LineStyle, Painter, RectEl};
use crate::render::points::{Point, PointBatch};

/// One `breaks_as_grid()` call: a line per break, across the panel.
pub struct GridLines {
    /// Break positions in npc along the panel.
    pub pos: Vec<f64>,
    /// Horizontal lines (the y breaks) or vertical (the x breaks).
    pub horizontal: bool,
    pub style: LineStyle,
}

/// A `geom_point()` layer (ggplot2 R/geom-point.R `GeomPoint$draw_panel()`):
/// positions in data units, rescaled linearly into the panel as
/// `Coord$transform()` does, and the aesthetics `pointsGrob()` is given.
pub struct PointLayer {
    pub x: Vec<f64>,
    pub y: Vec<f64>,
    pub x_range: [f64; 2],
    pub y_range: [f64; 2],
    /// pch, `size` and `stroke`, each of length 1 or `x.len()`.
    pub shape: Vec<f64>,
    pub size: Vec<f64>,
    pub stroke: Vec<f64>,
    pub col: Vec<[u8; 4]>,
    pub fill: Vec<[u8; 4]>,
    /// `.pt`, `.stroke` and the resolution in pixels per inch.
    pub pt: f64,
    pub stroke_scale: f64,
    pub res: f64,
}

fn at(v: &[f64], i: usize) -> f64 {
    if v.len() == 1 { v[0] } else { v[i] }
}

impl PointLayer {
    /// The layer's points in panel cell `c`, as the hybrid tier's
    /// `rs_render_points()` places them.
    pub(crate) fn batch(&self, c: &Rect, threads: usize) -> PointBatch {
        let (pw, ph) = (c.x1 - c.x0, c.y1 - c.y0);
        let npc = |v: f64, r: &[f64; 2]| {
            if v == f64::INFINITY {
                1.0
            } else if v == f64::NEG_INFINITY {
                0.0
            } else {
                (v - r[0]) / (r[1] - r[0])
            }
        };
        PointBatch::from_fn(self.x.len(), threads, |i| {
            let st = at(&self.stroke, i);
            Some(Point {
                x: c.x0 + npc(self.x[i], &self.x_range) * pw,
                y: c.y0 + (1.0 - npc(self.y[i], &self.y_range)) * ph,
                shape: at(&self.shape, i) as i32,
                size: (at(&self.size, i) * self.pt + st * self.stroke_scale / 2.0) * self.res / 72.0,
                lwd: st * self.stroke_scale / 2.0 * self.res / 96.0,
                col: self.col[i],
                fill: self.fill[i],
            })
        })
    }
}

/// A layer's drawing, in the order the layers were added.
pub enum Layer {
    Points(PointLayer),
    Rects(RectLayer),
    Paths(PathLayer),
    Text(TextLayer),
}

pub struct Panel {
    pub clip: bool,
    /// `panel.background`.
    pub background: Option<RectEl>,
    /// In drawing order: minor y, minor x, major y, major x.
    pub grid: Vec<GridLines>,
    /// The layers, in order, drawn over the grid.
    pub layers: Vec<Layer>,
    /// `panel.border`.
    pub border: Option<RectEl>,
}

impl Panel {
    /// Draws the panel in cell `c`; `None` if a layer's text can't be drawn
    /// as ragg does.
    pub fn draw(&self, p: &mut Painter, c: &Rect) -> Option<()> {
        if self.clip {
            p.push_clip(*c);
        }
        if let Some(bg) = &self.background {
            p.rect(c, bg);
        }
        let (w, h) = (c.x1 - c.x0, c.y1 - c.y0);
        for g in &self.grid {
            let lines = g
                .pos
                .iter()
                .filter(|v| v.is_finite())
                .map(|&v| {
                    if g.horizontal {
                        let y = c.y1 - v * h;
                        vec![[c.x0, y], [c.x1, y]]
                    } else {
                        let x = c.x0 + v * w;
                        vec![[x, c.y1], [x, c.y0]]
                    }
                })
                .collect();
            p.lines(lines, &g.style);
        }
        // ragg's clip box for text: the panel's, or the page.
        let clip = if self.clip { p.text_clip_box(c) } else { p.page_clip() };
        for layer in &self.layers {
            match layer {
                Layer::Points(l) => p.list.push(Item::Points(l.batch(c, p.threads))),
                Layer::Rects(l) => p.list.push(Item::Rects(l.batch(c))),
                Layer::Paths(l) => {
                    let specs = l.specs(c);
                    if !specs.is_empty() {
                        p.list.push(Item::Paths(PathBatch::new(&specs)));
                    }
                }
                Layer::Text(l) => l.draw(p, c, clip)?,
            }
        }
        if let Some(border) = &self.border {
            p.rect(c, border);
        }
        if self.clip {
            p.pop_clip();
        }
        Some(())
    }
}
