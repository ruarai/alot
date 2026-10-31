//! The panel's background, grid lines and border (ggplot2 R/guides-grid.R
//! `guide_grid()`, `Coord$render_bg()` and `Coord$render_fg()`), drawn in
//! the panel's cell and clipped to it when the coord's `clip` is "on".

use crate::render::display::Rect;
use crate::render::page::{LineStyle, Painter, RectEl};

/// One `breaks_as_grid()` call: a line per break, across the panel.
pub struct GridLines {
    /// Break positions in npc along the panel.
    pub pos: Vec<f64>,
    /// Horizontal lines (the y breaks) or vertical (the x breaks).
    pub horizontal: bool,
    pub style: LineStyle,
}

pub struct Panel {
    pub clip: bool,
    /// `panel.background`.
    pub background: Option<RectEl>,
    /// In drawing order: minor y, minor x, major y, major x.
    pub grid: Vec<GridLines>,
    /// `panel.border`.
    pub border: Option<RectEl>,
}

impl Panel {
    pub fn draw(&self, p: &mut Painter, c: &Rect) {
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
        if let Some(border) = &self.border {
            p.rect(c, border);
        }
        if self.clip {
            p.pop_clip();
        }
    }
}
