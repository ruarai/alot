//! Rect, path and text layers of a panel (ggplot2 R/geom-rect.R,
//! R/geom-path.R and R/geom-text.R `draw_panel()`): positions in data units,
//! rescaled linearly into the panel cell as `Coord$transform()` does (text
//! comes already transformed, in npc), and the aesthetics `rectGrob()`,
//! `polylineGrob()`/`polygonGrob()`/`pathGrob()` and `textGrob()` are
//! given. The hybrid tier's `rs_render_rects()` and `rs_render_paths()`
//! (alot-r/src/render.rs) place marks the same way.

use crate::render::agg::{Cap, Join, Rule};
use crate::render::display::Rect;
use crate::render::page::{Painter, TextStyle};
use crate::render::paths::{PathSpec, Stroke};
use crate::render::raster;
use crate::render::rects::{RectBatch, RectSpec, RectStyle};
use crate::render::text::Run;

/// Where `v` falls in `r`, in npc, with infinite values squished to the
/// edges as `CoordCartesian$transform()` does.
fn npc(v: f64, r: &[f64; 2]) -> f64 {
    if v == f64::INFINITY {
        1.0
    } else if v == f64::NEG_INFINITY {
        0.0
    } else {
        (v - r[0]) / (r[1] - r[0])
    }
}

/// A `geom_rect()`, `geom_tile()`, `geom_bar()` or `geom_col()` layer
/// (`GeomRect$draw_panel()`): one `rectGrob()` of all its rects.
pub struct RectLayer {
    pub xmin: Vec<f64>,
    pub xmax: Vec<f64>,
    pub ymin: Vec<f64>,
    pub ymax: Vec<f64>,
    pub x_range: [f64; 2],
    pub y_range: [f64; 2],
    pub fill: Vec<[u8; 4]>,
    pub col: Vec<[u8; 4]>,
    /// grid's `lwd` (linewidth * .pt; 0 for blank line types).
    pub lwd: Vec<f64>,
    pub join: Join,
    /// Pixels per inch.
    pub res: f64,
}

impl RectLayer {
    /// The layer's rects in panel cell `c`. Built in parallel chunks: a
    /// 1000 x 1000 tile layer has 1e6 rects.
    pub(crate) fn batch(&self, c: &Rect) -> RectBatch {
        let (pw, ph) = (c.x1 - c.x0, c.y1 - c.y0);
        let n = self.xmin.len();
        let spec = |i: usize| RectSpec {
            x0: c.x0 + npc(self.xmin[i], &self.x_range) * pw,
            y0: c.y0 + (1.0 - npc(self.ymin[i], &self.y_range)) * ph,
            x1: c.x0 + npc(self.xmax[i], &self.x_range) * pw,
            y1: c.y0 + (1.0 - npc(self.ymax[i], &self.y_range)) * ph,
            fill: self.fill[i],
            col: self.col[i],
            lwd: self.lwd[i] * self.res / 96.0,
        };
        let chunk = n.div_ceil(raster::default_threads()).max(1 << 15);
        let blank = RectSpec { x0: f64::NAN, y0: 0.0, x1: 0.0, y1: 0.0, fill: [0; 4], col: [0; 4], lwd: 0.0 };
        let mut specs = vec![blank; n];
        std::thread::scope(|scope| {
            for (k, dst) in specs.chunks_mut(chunk).enumerate() {
                let spec = &spec;
                scope.spawn(move || {
                    for (j, d) in dst.iter_mut().enumerate() {
                        *d = spec(k * chunk + j);
                    }
                });
            }
        });
        RectBatch::new(specs, RectStyle { join: self.join, mitre: 10.0, snap: true })
    }
}

/// A `geom_path()`, `geom_line()` or `geom_step()` layer
/// (`GeomPath$draw_panel()`): one polyline per group, in the rows' order.
/// Rows `0..x.len()` are in drawing order; `path` gives each row's path
/// (0-based, into the per-path columns) and rows of one path are
/// consecutive.
pub struct PathLayer {
    pub x: Vec<f64>,
    pub y: Vec<f64>,
    pub path: Vec<i32>,
    pub x_range: [f64; 2],
    pub y_range: [f64; 2],
    pub col: Vec<[u8; 4]>,
    /// grid's `lwd` per path (linewidth * .pt; 0 for blank line types).
    pub lwd: Vec<f64>,
    /// R's packed line type per path.
    pub lty: Vec<u32>,
    /// Fill per path (empty when no path is filled): a path with `Some` is a closed polygon
    /// (`polygonGrob()`, filled non-zero as ragg's `drawPolygon()` fills),
    /// drawn whole; ribbons (`GeomRibbon$draw_group()`) mix them with
    /// polylines in drawing order.
    pub fill: Vec<Option<[u8; 4]>>,
    pub cap: Cap,
    pub join: Join,
    pub mitre: f64,
    pub res: f64,
}

impl PathLayer {
    /// The layer's polylines in panel cell `c`, split at non-finite points
    /// as grid draws each run separately.
    pub(crate) fn specs(&self, c: &Rect) -> Vec<PathSpec> {
        let (pw, ph) = (c.x1 - c.x0, c.y1 - c.y0);
        let mut specs = Vec::new();
        let mut k = 0;
        while k < self.x.len() {
            let p = self.path[k] as usize;
            let stroke = Stroke { lwd: self.lwd[p] * self.res / 96.0, lty: self.lty[p], cap: self.cap, join: self.join, mitre: self.mitre };
            if let Some(&Some(fill)) = self.fill.get(p) {
                let mut ring = Vec::new();
                while k < self.x.len() && self.path[k] as usize == p {
                    ring.push([c.x0 + npc(self.x[k], &self.x_range) * pw, c.y0 + (1.0 - npc(self.y[k], &self.y_range)) * ph]);
                    k += 1;
                }
                specs.push(PathSpec { rings: vec![ring], closed: true, fill, rule: Rule::NonZero, col: self.col[p], stroke });
                continue;
            }
            let mut rings: Vec<Vec<[f64; 2]>> = vec![Vec::new()];
            while k < self.x.len() && self.path[k] as usize == p {
                let pt = [c.x0 + npc(self.x[k], &self.x_range) * pw, c.y0 + (1.0 - npc(self.y[k], &self.y_range)) * ph];
                if pt[0].is_finite() && pt[1].is_finite() {
                    rings.last_mut().unwrap().push(pt);
                } else {
                    rings.push(Vec::new());
                }
                k += 1;
            }
            specs.extend(rings.into_iter().filter(|r| !r.is_empty()).map(|r| PathSpec {
                rings: vec![r],
                closed: false,
                fill: [0; 4],
                rule: Rule::NonZero,
                col: self.col[p],
                stroke,
            }));
        }
        specs
    }
}

/// One label of a `geom_text()` layer.
pub struct Label {
    /// Position in npc across the panel.
    pub x: f64,
    pub y: f64,
    pub hjust: f64,
    pub vjust: f64,
    /// `angle`, in degrees.
    pub rot: f64,
    pub text: String,
    pub style: TextStyle,
}

/// A `geom_text()` layer (`GeomText$draw_panel()`): one `textGrob()`, its
/// labels in data order.
pub struct TextLayer {
    pub labels: Vec<Label>,
}

impl TextLayer {
    /// Draws the labels in panel cell `c`, clipped to `clip` (ragg's
    /// inclusive clip box). `None` if a string can't be drawn as ragg does.
    /// Consecutive labels in one style are drawn together; labels in
    /// different styles in order, so overlaps composite as on a device.
    pub(crate) fn draw(&self, p: &mut Painter, c: &Rect, clip: [i32; 4]) -> Option<()> {
        let (w, h) = (c.x1 - c.x0, c.y1 - c.y0);
        let mut k = 0;
        while k < self.labels.len() {
            let style = self.labels[k].style;
            let end = self.labels[k..].iter().position(|l| l.style != style).map_or(self.labels.len(), |d| k + d);
            let runs: Vec<Run> = self.labels[k..end]
                .iter()
                .map(|l| Run { x: c.x0 + l.x * w, y: c.y1 - l.y * h, hjust: l.hjust, vjust: l.vjust, rot: l.rot, text: &l.text })
                .filter(|r| r.x.is_finite() && r.y.is_finite())
                .collect();
            p.text_clipped(&runs, &style, clip)?;
            k = end;
        }
        Some(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cell() -> Rect {
        Rect { x0: 10.0, y0: 20.0, x1: 110.0, y1: 70.0 }
    }

    #[test]
    fn rects_rescale_into_the_cell_and_squish_infinities() {
        let l = RectLayer {
            xmin: vec![0.0, f64::NEG_INFINITY], xmax: vec![5.0, f64::INFINITY],
            ymin: vec![0.0, 0.0], ymax: vec![10.0, 5.0],
            x_range: [0.0, 10.0], y_range: [0.0, 10.0],
            fill: vec![[1, 2, 3, 255]; 2], col: vec![[0; 4]; 2], lwd: vec![0.0; 2],
            join: Join::Miter, res: 96.0,
        };
        let b = l.batch(&cell());
        // The cell's rows, plus the margin a rect's edge pixels need.
        let (top, bottom) = b.rows();
        assert!((19..=20).contains(&top) && (70..=72).contains(&bottom), "{:?}", b.rows());
    }

    #[test]
    fn paths_split_at_non_finite_points() {
        let l = PathLayer {
            x: vec![0.0, 5.0, f64::NAN, 10.0, 10.0], y: vec![0.0, 5.0, 5.0, 0.0, 10.0],
            path: vec![0, 0, 0, 0, 0],
            x_range: [0.0, 10.0], y_range: [0.0, 10.0],
            col: vec![[0, 0, 0, 255]], lwd: vec![1.0], lty: vec![0], fill: vec![],
            cap: Cap::Butt, join: Join::Round, mitre: 10.0, res: 96.0,
        };
        let specs = l.specs(&cell());
        assert_eq!(specs.len(), 2);
        assert_eq!(specs[0].rings[0], vec![[10.0, 70.0], [60.0, 45.0]]);
        assert_eq!(specs[1].rings[0], vec![[110.0, 70.0], [110.0, 20.0]]);
    }

    #[test]
    fn filled_paths_are_closed_polygons_in_order() {
        let l = PathLayer {
            x: vec![0.0, 10.0, 10.0, 0.0, 0.0, 10.0], y: vec![5.0, 5.0, 0.0, 0.0, 5.0, 5.0], path: vec![0, 0, 0, 0, 1, 1],
            x_range: [0.0, 10.0], y_range: [0.0, 10.0],
            col: vec![[0; 4], [0, 0, 0, 255]], lwd: vec![0.0, 1.0], lty: vec![0, 0], fill: vec![Some([9, 9, 9, 255]), None],
            cap: Cap::Butt, join: Join::Round, mitre: 10.0, res: 96.0,
        };
        let specs = l.specs(&cell());
        assert_eq!(specs.len(), 2);
        assert!(specs[0].closed && !specs[1].closed);
        assert_eq!(specs[0].fill, [9, 9, 9, 255]);
        assert_eq!(specs[0].rings[0], vec![[10.0, 45.0], [110.0, 45.0], [110.0, 70.0], [10.0, 70.0]]);
    }

    #[test]
    fn paths_of_different_ids_are_separate() {
        let l = PathLayer {
            x: vec![0.0, 1.0, 2.0, 3.0], y: vec![0.0; 4], path: vec![0, 0, 1, 1],
            x_range: [0.0, 10.0], y_range: [0.0, 10.0],
            col: vec![[0, 0, 0, 255], [255, 0, 0, 255]], lwd: vec![1.0, 2.0], lty: vec![0, 0], fill: vec![],
            cap: Cap::Butt, join: Join::Round, mitre: 10.0, res: 96.0,
        };
        let specs = l.specs(&cell());
        assert_eq!(specs.len(), 2);
        assert_eq!(specs[1].col, [255, 0, 0, 255]);
        assert_eq!(specs[1].stroke.lwd, 2.0);
    }
}
