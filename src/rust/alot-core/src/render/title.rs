//! `titleGrob()` drawing (ggplot2 R/margins.R): labels placed in a cell
//! with the justification rotated by the angle and the margins applied, as
//! grid then positions and ragg draws the text. Axis labels, axis titles,
//! the plot title, subtitle, caption and tag are all title grobs.
//!
//! `check.overlap` mirrors grid's `gridText()` (R src/library/grid/src/
//! grid.c): each label's rotated text rectangle (`textRect()`) is tested
//! against the rectangles of the labels already kept (`intersect()`), in
//! order.

use crate::render::display::Rect;
use crate::render::layout::TitleGrob;
use crate::render::page::{Painter, TextStyle};
use crate::render::text::Run;

pub struct Title {
    /// Sizes and margins as `titleGrob()` measures them, one `(w, h)` per
    /// label in `labels`' order.
    pub grob: TitleGrob,
    pub labels: Vec<String>,
    /// Label positions in npc across the cell, `None` for the default
    /// (`rotate_just()` of the angle, hjust and vjust).
    pub x: Option<Vec<f64>>,
    pub y: Option<Vec<f64>>,
    /// Pixels added to every label's x and y (y up), for positions such as
    /// `unit(1, "npc") - (1 - hjust) * width` (`table_add_tag()`, ggplot2
    /// R/plot-build.R).
    pub shift: (f64, f64),
    /// `rotate_just(angle, hjust, vjust)`.
    pub just: (f64, f64),
    pub style: TextStyle,
    pub check_overlap: bool,
}

type Quad = [[f64; 2]; 4];

/// `linesIntersect()` (grid util.c).
fn lines_intersect(p1: [f64; 2], p2: [f64; 2], p3: [f64; 2], p4: [f64; 2]) -> bool {
    let (x1, y1, x2, y2, x3, y3, x4, y4) = (p1[0], p1[1], p2[0], p2[1], p3[0], p3[1], p4[0], p4[1]);
    let denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
    let ua = (x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3);
    if denom == 0.0 {
        if ua == 0.0 {
            if x1 == x2 {
                return !((y1 < y3 && y1.max(y2) < y3.min(y4)) || (y3 < y1 && y3.max(y4) < y1.min(y2)));
            }
            return !((x1 < x3 && x1.max(x2) < x3.min(x4)) || (x3 < x1 && x3.max(x4) < x1.min(x2)));
        }
        return false;
    }
    let ub = (x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3);
    let (ua, ub) = (ua / denom, ub / denom);
    ua > 0.0 && ua < 1.0 && ub > 0.0 && ub < 1.0
}

/// `intersect()`: whether any edge of `a` crosses an edge of `b`.
fn rects_intersect(a: &Quad, b: &Quad) -> bool {
    (0..4).any(|i| (0..4).any(|j| lines_intersect(a[i], a[(i + 1) % 4], b[j], b[(j + 1) % 4])))
}

/// `textRect()`: the text's `w` x `h` rectangle justified by `(hj, vj)` and
/// rotated by `rot` degrees about the anchor `(x, y)` (y up).
fn text_rect(x: f64, y: f64, w: f64, h: f64, hj: f64, vj: f64, rot: f64) -> Quad {
    let (s, c) = if rot != 0.0 { rot.to_radians().sin_cos() } else { (0.0, 1.0) };
    let corner = |px: f64, py: f64| {
        let (jx, jy) = (px - hj * w, py - vj * h);
        [jx * c - jy * s + x, jx * s + jy * c + y]
    };
    [corner(0.0, 0.0), corner(w, 0.0), corner(w, h), corner(0.0, h)]
}

impl Title {
    /// Draws the labels in `cell` (device pixels, y down).
    pub fn draw(&self, p: &mut Painter, cell: &Rect) -> Option<()> {
        let clip = p.page_clip();
        self.draw_clipped(p, cell, clip)
    }

    /// Draws the labels in `cell`, clipped to ragg's clip box `clip`.
    pub fn draw_clipped(&self, p: &mut Painter, cell: &Rect, clip: [i32; 4]) -> Option<()> {
        let g = &self.grob;
        let (w, h) = (cell.x1 - cell.x0, cell.y1 - cell.y0);
        let n = self.labels.len();
        let at = |v: &Option<Vec<f64>>, i: usize, default: f64| v.as_ref().map_or(default, |v| v[i % v.len()]);
        let mut kept: Vec<Quad> = Vec::new();
        let mut runs = Vec::with_capacity(n);
        for (i, text) in self.labels.iter().enumerate() {
            let (mut x, mut y) =
                (at(&self.x, i, self.just.0) * w + self.shift.0, at(&self.y, i, self.just.1) * h + self.shift.1);
            if g.margin_x {
                x += -g.margin[1] * self.just.0 + g.margin[3] * (1.0 - self.just.0);
            }
            if g.margin_y {
                y += -g.margin[0] * self.just.1 + g.margin[2] * (1.0 - self.just.1);
            }
            let (px, py) = (cell.x0 + x, cell.y1 - y);
            if !(px.is_finite() && py.is_finite()) {
                continue;
            }
            if self.check_overlap {
                let (lw, lh) = g.labels[i];
                let rect = text_rect(px, -py, lw, lh, g.hjust, g.vjust, g.angle);
                if kept.iter().any(|k| rects_intersect(&rect, k)) {
                    continue;
                }
                kept.push(rect);
            }
            runs.push(Run { x: px, y: py, hjust: g.hjust, vjust: g.vjust, rot: g.angle, text });
        }
        p.text_clipped(&runs, &self.style, clip)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crossing_rects_intersect_but_apart_or_nested_ones_do_not() {
        // grid's intersect() tests edges only: nested rects don't cross.
        let a = text_rect(0.0, 0.0, 10.0, 4.0, 0.0, 0.0, 0.0);
        assert!(rects_intersect(&a, &text_rect(5.0, -2.0, 10.0, 4.0, 0.0, 0.0, 0.0)));
        assert!(!rects_intersect(&a, &text_rect(11.0, 0.0, 10.0, 4.0, 0.0, 0.0, 0.0)));
        assert!(!rects_intersect(&a, &text_rect(1.0, 1.0, 2.0, 2.0, 0.0, 0.0, 0.0)));
    }

    #[test]
    fn text_rect_is_justified_then_rotated_about_the_anchor() {
        let r = text_rect(10.0, 20.0, 6.0, 2.0, 0.5, 0.5, 90.0);
        // Centred on the anchor, then a quarter turn: 2 wide, 6 high.
        let xs: Vec<f64> = r.iter().map(|p| p[0]).collect();
        let ys: Vec<f64> = r.iter().map(|p| p[1]).collect();
        let span = |v: &[f64]| v.iter().cloned().fold(f64::MIN, f64::max) - v.iter().cloned().fold(f64::MAX, f64::min);
        assert!((span(&xs) - 2.0).abs() < 1e-9 && (span(&ys) - 6.0).abs() < 1e-9);
        assert!((xs.iter().sum::<f64>() / 4.0 - 10.0).abs() < 1e-9 && (ys.iter().sum::<f64>() / 4.0 - 20.0).abs() < 1e-9);
    }
}
