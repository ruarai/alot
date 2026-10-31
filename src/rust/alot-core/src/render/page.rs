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
use crate::render::layout::{Box as Cell, Grob, Table};
use crate::render::legend::LegendGroup;
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

/// A theme `element_rect`: fill, outline colour, width in pixels and R's
/// packed line type (0 solid).
#[derive(Clone, Copy, Debug)]
pub struct RectEl {
    pub fill: [u8; 4],
    pub col: [u8; 4],
    pub lwd: f64,
    pub lty: u32,
    pub join: Join,
}

/// A theme `element_text`'s font and colour: an index into the page's
/// fonts, the size and line height in pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
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

    /// `rectGrob()` of one element rect over `r`. A dashed outline goes
    /// through the path drawer as ragg's `drawRect()` builds it: the
    /// filled path from GERect()'s first corner (grid's left, bottom) up,
    /// right and down, dashed and stroked with grid's default round ends.
    pub fn rect(&mut self, r: &Rect, el: &RectEl) {
        self.rect_capped(r, el, Cap::Round);
    }

    /// `rect()` with the line end `cap` for dashed outlines (a legend
    /// key's `lineend`).
    pub fn rect_capped(&mut self, r: &Rect, el: &RectEl, cap: Cap) {
        if el.lty != 0 && el.lwd > 0.0 && el.col[3] > 0 {
            let ring = vec![[r.x0, r.y1], [r.x0, r.y0], [r.x1, r.y0], [r.x1, r.y1]];
            let spec = PathSpec {
                rings: vec![ring],
                closed: true,
                fill: el.fill,
                rule: Rule::NonZero,
                col: el.col,
                stroke: Stroke { lwd: el.lwd, lty: el.lty, cap, join: el.join, mitre: 10.0 },
            };
            self.list.push(Item::Paths(PathBatch::new(&[spec])));
            return;
        }
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

    /// `rasterGrob()` of a colourbar's colours (low to high, opaque or not)
    /// stretched over `c` with `interpolate = TRUE`, as ragg's
    /// `drawRaster()` draws it: AGG's bilinear span generator over the
    /// image with edge pixels cloned, at the rect's exact position with
    /// its edge coverage. The image is one pixel wide with the highest
    /// colour first (vertical), or one high (horizontal).
    pub fn raster(&mut self, c: &Rect, colours: &[[u8; 4]], horizontal: bool) {
        if let Some(image) = bar_image(c, colours, horizontal, self.page_clip) {
            self.list.push(Item::Image(image));
        }
    }

    pub fn page_clip(&self) -> [i32; 4] {
        self.page_clip
    }

    /// ragg's clip box (inclusive) for a clip to `r`, as
    /// `text_clip()` in R/render-text.R gets it from grid's clip rectangle:
    /// limited to the page, then truncated.
    pub fn text_clip_box(&self, r: &Rect) -> [i32; 4] {
        let [_, _, x1, y1] = self.page_clip;
        let (w, h) = (x1 as f64 + 1.0, y1 as f64 + 1.0);
        [
            r.x0.max(0.0).trunc() as i32,
            r.y0.max(0.0).trunc() as i32,
            (r.x1.min(w).trunc() as i32).min(x1),
            (r.y1.min(h).trunc() as i32).min(y1),
        ]
    }

    /// Text runs in one style, clipped to the page. `None` if ragg's
    /// drawing of them isn't mirrored (a glyph missing from the font).
    pub fn text(&mut self, runs: &[Run], st: &TextStyle) -> Option<()> {
        self.text_clipped(runs, st, self.page_clip)
    }

    /// Text runs in one style, clipped to `clip` (ragg's inclusive clip box).
    pub fn text_clipped(&mut self, runs: &[Run], st: &TextStyle, clip: [i32; 4]) -> Option<()> {
        if runs.is_empty() || st.colour[3] == 0 {
            return Some(());
        }
        let font = self.fonts.get(st.font)?;
        let key = (st.font, st.size.to_bits());
        let hinted = self.hinted.entry(key).or_insert_with(|| Hinted::new(font, st.size));
        let image = text::draw_runs(font, hinted.as_mut()?, st.size, st.line, runs, st.colour, clip)?;
        if let Some(image) = image {
            self.list.push(Item::Image(image));
        }
        Some(())
    }
}

/// `agg::multiply()` of 8-bit values.
fn mul8(a: u32, b: u32) -> u32 {
    let t = a * b + 128;
    ((t >> 8) + t) >> 8
}

fn iround(v: f64) -> i64 {
    (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i64
}

/// The pixels `Painter::raster()` draws, premultiplied, cropped to the page
/// (`clip` is ragg's inclusive clip box).
fn bar_image(c: &Rect, colours: &[[u8; 4]], horizontal: bool, clip: [i32; 4]) -> Option<text::Image> {
    let n = colours.len();
    if n == 0 || !(c.x1 > c.x0 && c.y1 > c.y0) {
        return None;
    }
    // The source image as AGG holds it, premultiplied.
    let pre: Vec<[u32; 4]> = colours
        .iter()
        .map(|&[r, g, b, a]| {
            let a = a as u32;
            if a == 255 {
                [r as u32, g as u32, b as u32, a]
            } else if a == 0 {
                [0; 4]
            } else {
                [mul8(r as u32, a), mul8(g as u32, a), mul8(b as u32, a), a]
            }
        })
        .collect();
    let (w, h) = if horizontal { (n, 1) } else { (1, n) };
    let at = |x: i64, y: i64| {
        let (x, y) = (x.clamp(0, w as i64 - 1) as usize, y.clamp(0, h as i64 - 1) as usize);
        if horizontal { pre[x] } else { pre[n - 1 - y] }
    };
    let (fx0, fx1, fy0, fy1) = (iround(c.x0 * 256.0), iround(c.x1 * 256.0), iround(c.y0 * 256.0), iround(c.y1 * 256.0));
    let (i0, i1) = ((fx0 >> 8).max(clip[0] as i64), ((fx1 + 255) >> 8).min(clip[2] as i64 + 1));
    let (j0, j1) = ((fy0 >> 8).max(clip[1] as i64), ((fy1 + 255) >> 8).min(clip[3] as i64 + 1));
    if i0 >= i1 || j0 >= j1 {
        return None;
    }
    let overlap = |i: i64, lo: i64, hi: i64| (hi.min((i + 1) * 256) - lo.max(i * 256)).clamp(0, 256);
    let (iw, ih) = ((i1 - i0) as usize, (j1 - j0) as usize);
    let (dw, dh) = (c.x1 - c.x0, c.y1 - c.y0);
    let mut px = vec![[0.0f32; 4]; iw * ih];
    for j in j0..j1 {
        let oy = overlap(j, fy0, fy1);
        // span_interpolator_linear: the pixel centre mapped into the image
        // in 1/256ths, less the filter's half pixel.
        let y_hr = iround((j as f64 + 0.5 - c.y0) * h as f64 / dh * 256.0) - 128;
        let (y_lr, yf) = (y_hr >> 8, (y_hr & 255) as u32);
        for i in i0..i1 {
            let cover = ((overlap(i, fx0, fx1) * oy) >> 8).min(255) as f32 / 255.0;
            if cover == 0.0 {
                continue;
            }
            let x_hr = iround((i as f64 + 0.5 - c.x0) * w as f64 / dw * 256.0) - 128;
            let (x_lr, xf) = (x_hr >> 8, (x_hr & 255) as u32);
            let weights = [(256 - xf) * (256 - yf), xf * (256 - yf), (256 - xf) * yf, xf * yf];
            let corners = [at(x_lr, y_lr), at(x_lr + 1, y_lr), at(x_lr, y_lr + 1), at(x_lr + 1, y_lr + 1)];
            let mut out = [0.0f32; 4];
            for ch in 0..4 {
                let sum: u32 = 32768 + (0..4).map(|k| weights[k] * corners[k][ch]).sum::<u32>();
                out[ch] = (sum >> 16) as f32 / 255.0 * cover;
            }
            px[(j - j0) as usize * iw + (i - i0) as usize] = out;
        }
    }
    Some(text::Image { x0: i0 as i32, y0: j0 as i32, w: iw, h: ih, px })
}

/// The strips of one side of a facet (`build_strip()` and
/// `assemble_strips()`, ggplot2 R/labeller.R): each strip a gtable of one
/// cell per facet variable, each cell the strip background under its text.
pub struct StripDraw {
    /// Top or bottom: the variables' cells stack down; left or right: they
    /// sit side by side.
    pub horizontal: bool,
    /// The cells' size across the strip (`max_height()` or `max_width()`
    /// of all the strips' text).
    pub size: f64,
    /// Each strip's text, one per cell in the strip gtable's order.
    pub strips: Vec<Vec<Title>>,
    /// `strip.background.x` or `.y`.
    pub bg: Option<RectEl>,
    /// `strip.clip` is "on".
    pub clip: bool,
}

impl StripDraw {
    /// Draws strip `i` in `cell`, its cells centred along the strip's
    /// depth as grid places a layout of absolute sizes.
    fn draw(&self, p: &mut Painter, i: usize, cell: &Rect) -> Option<()> {
        let texts = self.strips.get(i)?;
        let total = self.size * texts.len() as f64;
        for (j, text) in texts.iter().enumerate() {
            let off = j as f64 * self.size;
            let sub = if self.horizontal {
                let y0 = cell.y0 + (cell.y1 - cell.y0 - total) / 2.0 + off;
                Rect { x0: cell.x0, y0, x1: cell.x1, y1: y0 + self.size }
            } else {
                let x0 = cell.x0 + (cell.x1 - cell.x0 - total) / 2.0 + off;
                Rect { x0, y0: cell.y0, x1: x0 + self.size, y1: cell.y1 }
            };
            // The strip's gtable clips each cell's grobs to the cell: the
            // background to the cell, the text to ragg's clip box for it.
            if self.clip {
                p.push_clip(sub);
            }
            if let Some(bg) = &self.bg {
                p.rect(&sub, bg);
            }
            if self.clip {
                p.pop_clip();
            }
            let clip = if self.clip { p.text_clip_box(&sub) } else { p.page_clip() };
            text.draw_clipped(p, &sub, clip)?;
        }
        Some(())
    }
}

/// What a `facet_wrap()` or `facet_grid()` draws beyond its panels: the
/// axes and strips its table's cells name (`layout::Grob`).
pub struct FacetDraw {
    pub axes: Vec<Axis>,
    pub strips: Vec<StripDraw>,
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
    /// Panels by cell name ("panel", or "panel-<col>-<row>").
    pub panels: Vec<(String, Panel)>,
    /// Axes by cell name: "axis-t", "axis-l", "axis-r", "axis-b".
    pub axes: Vec<(String, Axis)>,
    pub facet: Option<FacetDraw>,
    /// Titles by cell name (axis titles, title, subtitle, caption, tag).
    pub titles: Vec<(String, Title)>,
    /// Legend boxes by cell name ("guide-box-right", ...); several for
    /// "guide-box-inside", drawn in order.
    pub legends: Vec<(String, LegendGroup)>,
    pub threads: usize,
}

fn rect_of(b: &Cell) -> Rect {
    Rect { x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1 }
}

/// Draws the page in gtable's order (R/plot-build.R, R/facet-null.R,
/// R/facet-.R): the background, the panels, the strips and axes
/// (`z` 2 and 3), then the labels, legends and titles in the order they
/// were added. `None` if something can't be drawn as ragg does.
pub fn draw_page(spec: &PageSpec, fonts: &[Font]) -> Option<DisplayList> {
    let mut p = Painter::new(fonts, spec.width, spec.height);
    p.threads = spec.threads;
    p.list.push(Item::Clear(spec.bg));
    let boxes = spec.table.solve(spec.width as f64, spec.height as f64);
    let find = |name: &str| boxes.iter().find(|b| b.name == name);
    if let (Some(el), Some(b)) = (&spec.background, find("background")) {
        p.rect(&rect_of(b), el);
    }
    for (name, panel) in &spec.panels {
        if let Some(b) = find(name) {
            panel.draw(&mut p, &rect_of(b))?;
        }
    }
    if let Some(f) = &spec.facet {
        // Strips (z = 2), then axes (z = 3), each in the order added.
        for (c, b) in spec.table.cells.iter().zip(&boxes) {
            if let Grob::Strip(k, i) = c.grob {
                f.strips.get(k)?.draw(&mut p, i, &rect_of(b))?;
            }
        }
        for (c, b) in spec.table.cells.iter().zip(&boxes) {
            if let Grob::Axis(i) = c.grob {
                f.axes.get(i)?.draw(&mut p, &rect_of(b))?;
            }
        }
    }
    for name in ["axis-t", "axis-l", "axis-r", "axis-b"] {
        if let (Some((_, axis)), Some(b)) = (spec.axes.iter().find(|(n, _)| n == name), find(name)) {
            axis.draw(&mut p, &rect_of(b))?;
        }
    }
    let early = ["background", "panel", "spacer", "axis-", "strip-"];
    for b in boxes.iter().filter(|b| !early.iter().any(|e| b.name.starts_with(e))) {
        if let Some((_, title)) = spec.titles.iter().find(|(n, _)| *n == b.name) {
            title.draw(&mut p, &rect_of(b))?;
        }
        for (_, legends) in spec.legends.iter().filter(|(n, _)| *n == b.name) {
            legends.draw(&mut p, &rect_of(b))?;
        }
    }
    Some(p.list)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CLIP: [i32; 4] = [0, 0, 99, 99];

    #[test]
    fn a_vertical_bar_has_its_last_colour_on_top_and_blends_between_the_ends() {
        let colours = [[0, 0, 0, 255], [200, 100, 50, 255]];
        let img = bar_image(&Rect { x0: 2.0, y0: 3.0, x1: 6.0, y1: 23.0 }, &colours, false, CLIP).unwrap();
        assert_eq!((img.x0, img.y0, img.w, img.h), (2, 3, 4, 20));
        let at = |j: usize| img.px[j * img.w][0] * 255.0;
        // Edge pixels clone the end colours; between the two image pixels'
        // centres (a quarter and three quarters down) the colour blends.
        assert!((at(0) - 200.0).abs() < 1.0, "{}", at(0));
        assert!(at(19) < 1.0, "{}", at(19));
        assert!((at(10) - 90.0).abs() < 2.0, "{}", at(10));
        assert!(at(5) > at(15));
    }

    #[test]
    fn a_horizontal_bar_runs_from_the_first_colour_to_the_last() {
        let colours = [[255, 0, 0, 255], [0, 0, 255, 255]];
        let img = bar_image(&Rect { x0: 0.0, y0: 0.0, x1: 20.0, y1: 4.0 }, &colours, true, CLIP).unwrap();
        assert!(img.px[0][0] > 0.99 && img.px[19][2] > 0.99);
    }

    #[test]
    fn fractional_edges_have_partial_coverage_and_the_page_clips() {
        let colours = [[10, 20, 30, 255]];
        let img = bar_image(&Rect { x0: 1.5, y0: 1.0, x1: 3.0, y1: 2.0 }, &colours, false, CLIP).unwrap();
        assert_eq!((img.x0, img.w), (1, 2));
        assert!((img.px[0][3] - 0.5).abs() < 0.01 && (img.px[1][3] - 1.0).abs() < 1e-6);
        let img = bar_image(&Rect { x0: 90.0, y0: 0.0, x1: 120.0, y1: 4.0 }, &colours, false, CLIP).unwrap();
        assert_eq!((img.x0, img.w), (90, 10));
        assert!(bar_image(&Rect { x0: 120.0, y0: 0.0, x1: 130.0, y1: 4.0 }, &colours, false, CLIP).is_none());
    }

    fn draw_rect(el: RectEl) -> Vec<u32> {
        let fonts: Vec<Font> = Vec::new();
        let mut p = Painter::new(&fonts, 40, 30);
        p.rect(&Rect { x0: 5.0, y0: 5.0, x1: 35.0, y1: 25.0 }, &el);
        crate::render::raster::render(&p.list, 40, 30, &crate::render::raster::Options { threads: 1, band_rows: 8 })
    }

    #[test]
    fn dashed_element_rects_start_at_the_bottom_left_and_keep_their_fill() {
        let solid = RectEl { fill: [0, 0, 255, 255], col: [255, 0, 0, 255], lwd: 1.0, lty: 0, join: Join::Round };
        let dashed = draw_rect(RectEl { lty: 0x44, ..solid });
        let solid = draw_rect(solid);
        // Inside, both are the fill.
        assert_eq!(dashed[15 * 40 + 20], solid[15 * 40 + 20]);
        // The dashed outline has gaps where the solid one has none; its
        // first dash runs up from the bottom-left corner (4 px on, 4 off).
        let red = |img: &[u32], x: usize, y: usize| img[y * 40 + x] & 0xFF;
        assert!((5..25).all(|y| red(&solid, 5, y) > 100));
        assert!(red(&dashed, 5, 23) > 100 && red(&dashed, 5, 19) < 100 && red(&dashed, 5, 15) > 100);
    }
}
