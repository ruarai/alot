//! A `guide_axis()`'s drawing (ggplot2 R/guide-axis.R, R/guide-.R):
//! `GuideAxis$assemble_drawing()` puts the ticks, the label grobs (one per
//! `n.dodge` row or column) and an empty title in a gtable, justifies it in
//! the axis cell, and draws the axis line under it. `build_ticks()` builds
//! the major, then minor, ticks as one polyline per break.

use crate::render::display::Rect;
use crate::render::page::{LineStyle, Painter};
use crate::render::title::Title;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Side {
    Top,
    Right,
    Bottom,
    Left,
}

/// Tick marks: break positions in npc along the axis, their length in
/// pixels and line style.
pub struct Ticks {
    pub pos: Vec<f64>,
    pub len: f64,
    pub style: LineStyle,
}

pub struct Axis {
    pub side: Side,
    /// The axis line (`axis.line.*`).
    pub line: Option<LineStyle>,
    /// `axis.ticks.length` (0 if the ticks are blank) and the minor ticks'
    /// length (when `minor.ticks`), which size the tick row or column.
    pub major_len: f64,
    pub minor_len: Option<f64>,
    pub ticks: Option<Ticks>,
    pub minor_ticks: Option<Ticks>,
    /// The label grobs, nearest the ticks first.
    pub labels: Vec<Title>,
    /// `rotate_just(element = text)`: `hjust` of vertical axes, `vjust` of
    /// horizontal ones, which places the labels when the cell is bigger
    /// than the axis.
    pub just: f64,
}

impl Axis {
    pub fn draw(&self, p: &mut Painter, c: &Rect) -> Option<()> {
        let vertical = matches!(self.side, Side::Left | Side::Right);
        let length = self.minor_len.unwrap_or(0.0).max(self.major_len).max(0.0);
        let sizes: Vec<f64> = self.labels.iter().map(|l| if vertical { l.grob.width() } else { l.grob.height() }).collect();
        let used = length + sizes.iter().sum::<f64>();
        let cell = if vertical { c.x1 - c.x0 } else { c.y1 - c.y0 };
        // The viewport is `max(gtable size, 1npc)` across the axis, against
        // the panel's side of the cell; the gtable's null rows (columns)
        // share the rest around the labels, `just` after them.
        let size = used.max(cell);
        let extra = size - used;
        let (lo, hi) = match self.side {
            Side::Bottom => (c.y0, c.y0 + size),
            Side::Top => (c.y1 - size, c.y1),
            Side::Left => (c.x1 - size, c.x1),
            Side::Right => (c.x0, c.x0 + size),
        };
        let before = if vertical { self.just * extra } else { (1.0 - self.just) * extra };
        let labels_first = matches!(self.side, Side::Top | Side::Left);
        let (tick_lo, tick_hi) = if labels_first { (hi - length, hi) } else { (lo, lo + length) };
        // Label cells along the axis' orthogonal dimension.
        let mut spans = vec![(0.0, 0.0); sizes.len()];
        let mut at = if labels_first { lo + before } else { lo + length + before };
        let order: Vec<usize> = if labels_first { (0..sizes.len()).rev().collect() } else { (0..sizes.len()).collect() };
        for i in order {
            spans[i] = (at, at + sizes[i]);
            at += sizes[i];
        }

        if let Some(line) = &self.line {
            let l = match self.side {
                Side::Bottom => vec![[c.x0, lo], [c.x1, lo]],
                Side::Top => vec![[c.x0, hi], [c.x1, hi]],
                Side::Left => vec![[hi, c.y1], [hi, c.y0]],
                Side::Right => vec![[lo, c.y1], [lo, c.y0]],
            };
            p.lines(vec![l], line);
        }
        let draw_ticks = |p: &mut Painter| {
            for t in [&self.ticks, &self.minor_ticks].into_iter().flatten() {
                let lines = t
                    .pos
                    .iter()
                    .filter(|v| v.is_finite())
                    .map(|&v| match self.side {
                        Side::Bottom => {
                            let x = c.x0 + v * (c.x1 - c.x0);
                            vec![[x, tick_lo + t.len], [x, tick_lo]]
                        }
                        Side::Top => {
                            let x = c.x0 + v * (c.x1 - c.x0);
                            vec![[x, tick_hi - t.len], [x, tick_hi]]
                        }
                        Side::Left => {
                            let y = c.y1 - v * (c.y1 - c.y0);
                            vec![[tick_hi - t.len, y], [tick_hi, y]]
                        }
                        Side::Right => {
                            let y = c.y1 - v * (c.y1 - c.y0);
                            vec![[tick_lo + t.len, y], [tick_lo, y]]
                        }
                    })
                    .collect();
                p.lines(lines, &t.style);
            }
        };
        let draw_labels = |p: &mut Painter| -> Option<()> {
            for (title, &(a, b)) in self.labels.iter().zip(&spans) {
                let cell = if vertical { Rect { x0: a, y0: c.y0, x1: b, y1: c.y1 } } else { Rect { x0: c.x0, y0: a, x1: c.x1, y1: b } };
                title.draw(p, &cell)?;
            }
            Some(())
        };
        // gtable draws by `z`: ticks, labels, except on the left, where the
        // labels come first.
        if self.side == Side::Left {
            draw_labels(p)?;
            draw_ticks(p);
        } else {
            draw_ticks(p);
            draw_labels(p)?;
        }
        Some(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::agg::{Cap, Join};
    use crate::render::display::Item;
    use crate::render::text::Font;

    fn style() -> LineStyle {
        LineStyle { col: [0, 0, 0, 255], lwd: 1.0, lty: 0, cap: Cap::Butt, join: Join::Round }
    }

    fn axis(side: Side, major: f64, minor: Option<f64>) -> Axis {
        let ticks = |len| Some(Ticks { pos: vec![0.0, 0.5, 1.0], len, style: style() });
        Axis { side, line: Some(style()), major_len: major, minor_len: minor, ticks: ticks(major), minor_ticks: minor.and_then(ticks), labels: vec![], just: 0.5 }
    }

    /// The paths an axis draws, as (batch count, row extent).
    fn rows(a: &Axis, cell: Rect) -> Option<Vec<(i64, i64)>> {
        let fonts: Vec<Font> = vec![];
        let mut p = Painter::new(&fonts, 100, 100);
        a.draw(&mut p, &cell)?;
        Some(p.list.items.iter().filter_map(Item::rows).collect())
    }

    #[test]
    fn bottom_ticks_hang_below_the_axis_line() {
        // A 10 px cell with 4 px ticks: the line at the cell's top, ticks
        // from the line down 4 px.
        let r = rows(&axis(Side::Bottom, 4.0, None), Rect { x0: 10.0, y0: 20.0, x1: 90.0, y1: 30.0 }).unwrap();
        assert_eq!(r[0], (19, 21)); // the line, 1 px wide, at y = 20
        assert_eq!(r[1], (20, 25)); // ticks: y = 20 to 24
    }

    #[test]
    fn top_ticks_rise_from_the_cell_bottom() {
        let r = rows(&axis(Side::Top, 4.0, None), Rect { x0: 10.0, y0: 20.0, x1: 90.0, y1: 30.0 }).unwrap();
        assert_eq!(r[0], (29, 31)); // the line at y = 30
        assert_eq!(r[1], (26, 31)); // ticks: y = 26 to 30
    }

    #[test]
    fn the_tick_cell_is_the_longest_of_major_and_minor_ticks() {
        let a = axis(Side::Bottom, 2.0, Some(6.0));
        let r = rows(&a, Rect { x0: 10.0, y0: 20.0, x1: 90.0, y1: 30.0 }).unwrap();
        // Minor ticks, 6 px, reach y = 26 from the line at 20; the major
        // ticks, 2 px, y = 22.
        assert_eq!(r[1], (20, 23));
        assert_eq!(r[2], (20, 27));
    }
}
