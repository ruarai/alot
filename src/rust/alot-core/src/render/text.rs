//! String metrics as a ragg device reports them (PHASE2.md, Architecture
//! 4), for the font files R resolves with `systemfonts::match_fonts()`.
//!
//! - **Width** is textshaping's `ts_string_width()` (textshaping 1.0.5
//!   src/string_metrics.cpp), which ragg's `stringWidth()` calls with the
//!   size in pixels and a resolution of 72 (ragg 1.5.2 src/text_renderer.h,
//!   `get_text_width()`): HarfBuzz shaping (here `rustybuzz`) on a FreeType
//!   face set with `FT_Set_Char_Size(face, 0, size * 64, 72, 72)`, unhinted
//!   advances (`hb_ft_font_create_referenced()` loads with
//!   `FT_LOAD_NO_HINTING`), summed in 26.6 units.
//! - **Ascent and descent** are ragg's `charMetric()`: the pixel rows of
//!   the glyph as AGG's FreeType engine renders it in gray8, hinted
//!   (`FT_LOAD_DEFAULT`) at `FT_Set_Pixel_Sizes(face, 0, floor(size))`,
//!   through AGG's rasteriser with gamma 1.6, scaled by `size /
//!   (floor(size * 64) / 64)` (agg_font_freetype.cpp, `prepare_glyph()`
//!   for `glyph_ren_agg_gray8`). `skrifa`'s TrueType interpreter hints the
//!   outline as FreeType's v40 interpreter does. A blank glyph (a space)
//!   has ascent and descent of one pixel: ragg's AGG keeps scanline bounds
//!   in `long` and the glyph cache in `int`, so the empty bounds
//!   `LONG_MAX`/`LONG_MIN` truncate to -1 and 1.
//! - **Strings** follow R's graphics engine (R 4.6.1 src/main/engine.c):
//!   `GEStrWidth()` takes the widest line, `GEStrMetric()` the largest
//!   ascent of the first line and descent of the last, and `GEStrHeight()`
//!   adds `n` line heights to the ascent of "M".
//!
//! Anything ragg would resolve through font fallback (a glyph missing from
//! the font) or that this module doesn't mirror (bitmap, CFF or variable
//! fonts, right-to-left text) returns `None`, and the caller keeps the
//! plot out of the full tier.

use std::collections::HashMap;

use rustybuzz::ttf_parser::{GlyphId, Tag};
use skrifa::instance::{LocationRef, Size};
use skrifa::outline::{DrawSettings, HintingInstance, HintingOptions, OutlineGlyphCollection, OutlinePen};
use skrifa::MetadataProvider;

use crate::render::agg;

/// One string's metrics in device pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Metrics {
    /// `GEStrWidth()`.
    pub width: f64,
    /// `GEStrMetric()` ascent and descent.
    pub ascent: f64,
    pub descent: f64,
    /// `GEStrHeight()`.
    pub height: f64,
}

/// `FT_DivFix()` for non-negative arguments.
fn div_fix(a: i64, b: i64) -> i64 {
    ((a << 16) + (b >> 1)) / b
}

/// `FT_MulDiv()` with rounding, for any signs.
fn mul_div(a: i64, b: i64, c: i64) -> i64 {
    let s = a.signum() * b.signum() * c.signum();
    let (a, b, c) = (a.abs(), b.abs(), c.abs());
    s * ((a * b + (c >> 1)) / c)
}

/// A font file parsed for shaping and hinting.
pub struct Font<'a> {
    shaper: rustybuzz::Face<'a>,
    outlines: OutlineGlyphCollection<'a>,
    upem: i64,
}

impl<'a> Font<'a> {
    /// Parses face `index` of `data`, or `None` for fonts this module
    /// doesn't mirror: bitmap-only, CFF and variable fonts.
    pub fn new(data: &'a [u8], index: u32) -> Option<Font<'a>> {
        let shaper = rustybuzz::Face::from_slice(data, index)?;
        let glyf = Tag::from_bytes(b"glyf");
        if shaper.raw_face().table(glyf).is_none() || shaper.is_variable() {
            return None;
        }
        let font = skrifa::FontRef::from_index(data, index).ok()?;
        let upem = shaper.units_per_em() as i64;
        Some(Font { shaper, outlines: font.outline_glyphs(), upem })
    }

    /// The face's `x_scale` (16.16) after `FT_Set_Char_Size(face, 0, size *
    /// 64, 72, 72)` (FreeType `FT_Request_Metrics()`).
    fn x_scale(&self, size: f64) -> i64 {
        // `size * 64` is converted to FT_F26Dot6 by truncation; at 72 dpi
        // FT_REQUEST_WIDTH() gives it back unchanged.
        div_fix((size * 64.0) as i64, self.upem)
    }

    /// Whether every character of `text` (other than line breaks) has a
    /// glyph and none is right-to-left: a cheap check that ragg would draw
    /// it from this font alone.
    pub fn covers(&self, text: &str) -> bool {
        text.chars().all(|c| c == '\n' || (!is_rtl(c) && self.shaper.glyph_index(c).is_some_and(|g| g.0 != 0)))
    }

    /// textshaping's width of one line, or `None` if a glyph is missing or
    /// the text has right-to-left characters.
    pub fn line_width(&self, line: &str, size: f64) -> Option<f64> {
        Some(self.shape(line, size)?.1)
    }

    /// textshaping's `ts_string_shape()` of one line: each glyph's id and
    /// position (pen position plus offset, pixels, y as HarfBuzz gives it),
    /// and the line's width. `None` if a glyph is missing or the text has
    /// right-to-left characters.
    pub fn shape(&self, line: &str, size: f64) -> Option<(Vec<(u32, f64, f64)>, f64)> {
        if line.is_empty() {
            return Some((Vec::new(), 0.0));
        }
        if line.chars().any(is_rtl) {
            return None;
        }
        let x_scale = self.x_scale(size);
        // hb_ft_font_changed() sets the hb_font scale from x_scale; GPOS
        // values scale by em_mult() (HarfBuzz 2.7 hb-font.hh).
        let hb_scale = (x_scale * self.upem + (1 << 15)) >> 16;
        let x_mult = (hb_scale << 16) / self.upem;
        let em = |v: i32| (v as i64 * x_mult) >> 16;
        let mut buffer = rustybuzz::UnicodeBuffer::new();
        buffer.push_str(line);
        buffer.guess_segment_properties();
        let shaped = rustybuzz::shape(&self.shaper, &[], buffer);
        let mut glyphs = Vec::with_capacity(shaped.len());
        let mut x: i64 = 0;
        for (info, pos) in shaped.glyph_infos().iter().zip(shaped.glyph_positions()) {
            if info.glyph_id == 0 {
                return None;
            }
            glyphs.push((info.glyph_id, (x + em(pos.x_offset)) as f64 / 64.0, em(pos.y_offset) as f64 / 64.0));
            let units = self.shaper.glyph_hor_advance(GlyphId(info.glyph_id as u16))? as i64;
            if pos.x_advance == 0 {
                continue;
            }
            // hb_ft_get_glyph_h_advances(): FT_Get_Advance() unhinted is
            // FT_MulDiv(units, x_scale, 64) in 16.16, rounded to 26.6.
            let advance = (mul_div(units, x_scale, 64) + (1 << 9)) >> 10;
            x += advance + em(pos.x_advance - units as i32);
        }
        Some((glyphs, x as f64 / 64.0))
    }
}

/// Right-to-left scripts: textshaping splits these into bidi embeddings,
/// which isn't mirrored.
fn is_rtl(c: char) -> bool {
    matches!(c as u32, 0x0590..=0x08FF | 0xFB1D..=0xFDFF | 0xFE70..=0xFEFF | 0x10800..=0x10FFF | 0x1E800..=0x1EFFF)
}

/// AGG's `gamma_power(1.6)` table (`rasterizer_scanline_aa::gamma()`), which
/// ragg sets on the font engine's rasteriser (ragg text_renderer.h).
fn gamma(a: u8) -> u8 {
    ((a as f64 / 255.0).powf(1.6) * 255.0 + 0.5) as u8
}

/// A hinted outline in 26.6 units as FreeType hands it to ragg: contours
/// of a start point and line or quadratic segments.
type Outline = Vec<([i64; 2], Vec<Seg>)>;

#[derive(Clone, Copy)]
enum Seg {
    Line([i64; 2]),
    Quad([i64; 2], [i64; 2]),
}

/// Hinted glyphs at one pixel size: outlines, rendered masks and their rows,
/// cached per glyph.
pub struct Hinted<'f, 'a> {
    font: &'f Font<'a>,
    hinter: Option<HintingInstance>,
    /// `size / (floor(size * 64) / 64)`: ragg scales glyph bounds by the
    /// requested over the engine's 26.6 height.
    scale: f64,
    outlines: HashMap<u32, Option<std::rc::Rc<Outline>>>,
    masks: HashMap<(u32, u64), Option<std::rc::Rc<agg::Coverage>>>,
}

impl<'f, 'a> Hinted<'f, 'a> {
    /// Hinting for `size` pixels, or `None` if the size is out of range.
    pub fn new(font: &'f Font<'a>, size: f64) -> Option<Self> {
        if !(size.is_finite() && size > 0.0 && size < 1e5) {
            return None;
        }
        let height = (size * 64.0) as i64;
        if height == 0 {
            return None;
        }
        // FT_Set_Pixel_Sizes(face, 0, height >> 6); FreeType raises 0 to 1.
        // Glyphs are hinted and drawn at this integer ppem, while textshaping
        // positions them at the fractional size.
        let ppem = (height >> 6).max(1);
        let hinter = HintingInstance::new(&font.outlines, Size::new(ppem as f32), LocationRef::default(), HintingOptions::default()).ok();
        Some(Hinted { font, hinter, scale: size / (height as f64 / 64.0), outlines: HashMap::new(), masks: HashMap::new() })
    }

    /// Glyph `gid`'s hinted outline, or `None` if it can't be hinted as
    /// FreeType would.
    fn outline(&mut self, gid: u32) -> Option<std::rc::Rc<Outline>> {
        if let Some(o) = self.outlines.get(&gid) {
            return o.clone();
        }
        let o = self.load_outline(gid).map(std::rc::Rc::new);
        self.outlines.insert(gid, o.clone());
        o
    }

    fn load_outline(&self, gid: u32) -> Option<Outline> {
        let glyph = self.font.outlines.get(skrifa::GlyphId::new(gid))?;
        let mut pen = RawPen::default();
        glyph.draw(DrawSettings::hinted(self.hinter.as_ref()?, false), &mut pen).ok()?;
        pen.close();
        (!pen.cubic).then_some(pen.contours)
    }

    /// Glyph `gid` at `rot` degrees as ragg's glyph cache renders it in
    /// gray8 at the origin (y down): coverage through gamma 1.6.
    fn mask(&mut self, gid: u32, rot: f64) -> Option<std::rc::Rc<agg::Coverage>> {
        let key = (gid, rot.to_bits());
        if let Some(m) = self.masks.get(&key) {
            return m.clone();
        }
        let m = self.outline(gid).map(|o| {
            // The engine flattens curves at approximation scale 4
            // (agg_font_freetype.cpp, font_engine_freetype_base()).
            let mut cov = agg::rasterize(&flatten(&o, rotation(rot), 4.0, [0.0, 0.0]));
            for a in cov.alpha.iter_mut() {
                *a = gamma(*a);
            }
            std::rc::Rc::new(cov)
        });
        self.masks.insert(key, m.clone());
        m
    }

    /// The topmost and bottommost pixel rows (y down, baseline between rows
    /// -1 and 0) of glyph `gid` as ragg's glyph cache records them, or
    /// `None` if it can't be hinted as FreeType would. A blank glyph gives
    /// (-1, 0) (see the module notes).
    fn glyph_rows(&mut self, gid: u32) -> Option<(i32, i32)> {
        let cov = self.mask(gid, 0.0)?;
        let lit = |j: usize| cov.alpha[j * cov.w..(j + 1) * cov.w].iter().any(|&a| a > 0);
        let Some(top) = (0..cov.h).find(|&j| lit(j)) else { return Some((-1, 0)) };
        let bottom = (0..cov.h).rev().find(|&j| lit(j)).unwrap();
        Some((cov.y0 + top as i32, cov.y0 + bottom as i32))
    }

    /// ragg's `charMetric()` ascent and descent of character `c`, `None` if
    /// the font lacks it.
    fn char_metric(&mut self, c: char) -> Option<(f64, f64)> {
        let gid = self.font.shaper.glyph_index(c)?.0 as u32;
        if gid == 0 {
            return None;
        }
        let (top, bottom) = self.glyph_rows(gid)?;
        Some((self.scale * -top as f64, self.scale * (bottom + 1) as f64))
    }

    /// Largest ascent (`descent = false`) or descent over a line's
    /// characters, starting from 0 as `GEStrMetric()` does.
    fn line_extent(&mut self, line: &str, descent: bool) -> Option<f64> {
        let mut best: f64 = 0.0;
        for c in line.chars() {
            let (a, d) = self.char_metric(c)?;
            best = best.max(if descent { d } else { a });
        }
        Some(best)
    }
}

/// `agg::trans_affine_rotation(deg2rad(-rot))` as (sx, shx, shy, sy), which
/// ragg sets on the font engine for rotated text.
fn rotation(rot: f64) -> [f64; 4] {
    if rot == 0.0 {
        return [1.0, 0.0, 0.0, 1.0];
    }
    let a = (-rot).to_radians();
    [a.cos(), -a.sin(), a.sin(), a.cos()]
}

/// A hinted outline as AGG's FreeType engine stores and flattens it
/// (agg_font_freetype.cpp, `decompose_ft_outline()`): y flipped, `m`
/// applied, rounded with `dbl_to_int26p6()` (which truncates `p * 64 +
/// 0.5`, so negative coordinates move up by 1/64), offset by `(dx, dy)` (the
/// glyph adaptor's position), then curves flattened by `conv_curve` at
/// approximation scale `scale`.
fn flatten(outline: &Outline, m: [f64; 4], scale: f64, [dx, dy]: [f64; 2]) -> Vec<Vec<[f64; 2]>> {
    let map = |[x, y]: [i64; 2]| {
        let (x, y) = (x as f64 / 64.0, -(y as f64) / 64.0);
        let r = |p: f64| ((p * 64.0 + 0.5) as i32) as f64 / 64.0;
        [dx + r(x * m[0] + y * m[1]), dy + r(x * m[2] + y * m[3])]
    };
    outline
        .iter()
        .map(|(start, segs)| {
            let mut pts = vec![map(*start)];
            for seg in segs {
                match *seg {
                    Seg::Line(p) => pts.push(map(p)),
                    Seg::Quad(c, p) => {
                        let p1 = *pts.last().unwrap();
                        agg::curve3(p1, map(c), map(p), scale, &mut pts);
                    }
                }
            }
            pts
        })
        .collect()
}

/// Records a hinted outline in 26.6 units. FreeType's decomposition puts
/// an implied on-curve point between two off-curve points at their
/// integer-divided midpoint (`(a + b) / 2`, truncating); skrifa gives the
/// exact midpoint, which only differs at half units, so those truncate.
#[derive(Default)]
struct RawPen {
    contours: Outline,
    start: Option<[i64; 2]>,
    segs: Vec<Seg>,
    cubic: bool,
}

fn fix26(x: f32, y: f32) -> [i64; 2] {
    [(x as f64 * 64.0).trunc() as i64, (y as f64 * 64.0).trunc() as i64]
}

impl OutlinePen for RawPen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.close();
        self.start = Some(fix26(x, y));
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.segs.push(Seg::Line(fix26(x, y)));
    }
    fn quad_to(&mut self, cx0: f32, cy0: f32, x: f32, y: f32) {
        self.segs.push(Seg::Quad(fix26(cx0, cy0), fix26(x, y)));
    }
    fn curve_to(&mut self, _: f32, _: f32, _: f32, _: f32, x: f32, y: f32) {
        // Only TrueType outlines reach here; they have no cubics.
        self.cubic = true;
        self.segs.push(Seg::Line(fix26(x, y)));
    }
    fn close(&mut self) {
        if let Some(start) = self.start.take() {
            self.contours.push((start, std::mem::take(&mut self.segs)));
        }
    }
}

/// Metrics of `text` (lines separated by `\n`) at `size` pixels with line
/// height `line` pixels (`lineheight * cex * cra[1] * ps / startps`).
pub fn string_metrics(font: &Font, hinted: &mut Hinted, text: &str, size: f64, line: f64) -> Option<Metrics> {
    let lines: Vec<&str> = text.split('\n').collect();
    let mut width: f64 = 0.0;
    for l in &lines {
        width = width.max(font.line_width(l, size)?);
    }
    let n = (lines.len() - 1) as f64;
    let ascent = hinted.line_extent(lines[0], false)? + n * line;
    let descent = hinted.line_extent(lines[lines.len() - 1], true)?;
    // GEStrHeight() uses the ascent of "M" (GEMetricInfo('M')).
    let (m_ascent, _) = hinted.char_metric('M')?;
    Some(Metrics { width, ascent, descent, height: n * line + m_ascent })
}

/// One string as grid hands it to `GEText()`: anchor in device pixels (y
/// down), justification and rotation in degrees.
pub struct Run<'s> {
    pub x: f64,
    pub y: f64,
    pub hjust: f64,
    pub vjust: f64,
    pub rot: f64,
    pub text: &'s str,
}

/// Premultiplied RGBA over pixels `[x0, x0 + w) x [y0, y0 + h)`.
pub struct Image {
    pub x0: i32,
    pub y0: i32,
    pub w: usize,
    pub h: usize,
    pub px: Vec<[f32; 4]>,
}

/// `agg::iround()`.
fn iround(v: f64) -> i32 {
    (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i32
}

/// Draws `runs` in `colour` (non-premultiplied RGBA) at `size` pixels with
/// line height `line` pixels, as R's graphics engine and ragg do:
///
/// - `GEText()` (R src/main/engine.c) splits lines, offsets each by
///   `(1 - vjust) * (n - 1) - i` line heights, and moves the anchor down by
///   `vjust` times the ascent of "M" (`GEStrHeight()` of one line); ragg
///   takes `hjust` itself (`canHAdj = 2`).
/// - ragg's `plot_text()` (ragg src/text_renderer.h) moves the anchor left
///   by `hjust` times the line's width, rounds y for upright text (and, as
///   it compares the angle in radians with 180, for any positive angle),
///   and draws each shaped glyph: at multiples of 90 degrees from the gray8
///   glyph cache (gamma 1.6, placed at the rounded glyph position);
///   otherwise the outline at its exact position, flattened at
///   approximation scale 2, without gamma.
///
/// Pixels outside `clip` (x0, y0, x1, y1, inclusive) are dropped, as ragg's
/// renderer clip box (AGG `renderer_base::clip_box()`) drops them.
///
/// `None` if a string can't be drawn as ragg would (a glyph missing from
/// the font, right-to-left text); `Some(None)` if nothing is visible.
pub fn draw_runs(font: &Font, hinted: &mut Hinted, size: f64, line: f64, runs: &[Run], colour: [u8; 4], clip: [i32; 4]) -> Option<Option<Image>> {
    let mut marks: Vec<(std::rc::Rc<agg::Coverage>, i32, i32)> = Vec::new();
    let m_ascent = hinted.char_metric('M')?.0;
    for run in runs {
        let lines: Vec<&str> = run.text.split('\n').collect();
        let n = lines.len();
        let (xc, yc) = (run.hjust, run.vjust);
        let rad = run.rot.to_radians();
        let (sin_r, cos_r) = (rad.sin(), rad.cos());
        for (i, l) in lines.iter().enumerate() {
            // GEText() works with y up.
            let (mut xo, mut yo) = (run.x, -run.y);
            if n > 1 {
                let d = ((1.0 - yc) * (n - 1) as f64 - i as f64) * line;
                xo += -d * sin_r;
                yo += d * cos_r;
            }
            let (xl, yb, hadj) = if xc != 0.0 || yc != 0.0 {
                (xo + yc * m_ascent * sin_r, yo - yc * m_ascent * cos_r, xc)
            } else {
                (xo, yo, 0.0)
            };
            let (glyphs, width) = font.shape(l, size)?;
            if width == 0.0 {
                continue;
            }
            let r = if run.rot != 0.0 { (-run.rot).to_radians() } else { 0.0 };
            let (c, s) = (r.cos(), r.sin());
            let (mut x, mut y) = (xl - width * hadj * c, -yb - width * hadj * s);
            if r % 180.0 < 1e-6 {
                y = y.round();
            } else if (r + 90.0) % 180.0 < 1e-6 {
                x = x.round();
            }
            let cached = run.rot % 90.0 == 0.0;
            for (gid, lx, ly) in glyphs {
                let (gx, gy) = (x + lx * c + ly * s, y + ly * c + lx * s);
                if cached {
                    if let Some(m) = hinted.mask(gid, run.rot) {
                        marks.push((m, iround(gx), iround(gy)));
                    }
                } else if let Some(o) = hinted.outline(gid) {
                    let contours = flatten(&o, rotation(run.rot), 2.0, [gx, gy]);
                    marks.push((std::rc::Rc::new(agg::rasterize(&contours)), 0, 0));
                }
            }
        }
    }
    let marks: Vec<_> = marks.into_iter().filter(|(m, _, _)| m.w > 0 && m.h > 0).collect();
    if marks.is_empty() || colour[3] == 0 {
        return Some(None);
    }
    let x0 = marks.iter().map(|(m, dx, _)| m.x0 + dx).min().unwrap().max(clip[0]);
    let y0 = marks.iter().map(|(m, _, dy)| m.y0 + dy).min().unwrap().max(clip[1]);
    let x1 = marks.iter().map(|(m, dx, _)| m.x0 + dx + m.w as i32).max().unwrap().min(clip[2] + 1);
    let y1 = marks.iter().map(|(m, _, dy)| m.y0 + dy + m.h as i32).max().unwrap().min(clip[3] + 1);
    if x1 <= x0 || y1 <= y0 {
        return Some(None);
    }
    let (w, h) = ((x1 - x0) as usize, (y1 - y0) as usize);
    let mut px = vec![[0f32; 4]; w * h];
    let a = colour[3] as f32 / 255.0;
    let src = [colour[0] as f32 / 255.0 * a, colour[1] as f32 / 255.0 * a, colour[2] as f32 / 255.0 * a, a];
    for (m, dx, dy) in &marks {
        let (ox, oy) = (m.x0 + dx - x0, m.y0 + dy - y0);
        for j in 0..m.h {
            let py = oy + j as i32;
            if py < 0 || py >= h as i32 {
                continue;
            }
            for i in 0..m.w {
                let pxi = ox + i as i32;
                let cov = m.alpha[j * m.w + i] as f32 / 255.0;
                if cov == 0.0 || pxi < 0 || pxi >= w as i32 {
                    continue;
                }
                let d = &mut px[py as usize * w + pxi as usize];
                for k in 0..4 {
                    d[k] = src[k] * cov + d[k] * (1.0 - src[3] * cov);
                }
            }
        }
    }
    Some(Some(Image { x0, y0, w, h, px }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SANS: &str = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";

    fn load(path: &str) -> Option<Vec<u8>> {
        std::fs::read(path).ok()
    }

    #[test]
    fn fixed_point_helpers_match_freetype() {
        assert_eq!(div_fix(46 << 6, 2048), 94208);
        assert_eq!(mul_div(1303, 94208, 64), 1918016);
        assert_eq!(div_fix(563, 2048), 18016);
        assert_eq!(mul_div(-3, 5, 2), -8);
    }

    #[test]
    fn widths_match_textshaping() {
        let Some(data) = load(SANS) else { return };
        let font = Font::new(&data, 0).unwrap();
        // grid's stringWidth() on ragg: "M" at 5.5 pt and 13.2 pt, 72 dpi.
        assert_eq!(font.line_width("M", 5.5), Some(4.75));
        assert_eq!(font.line_width("M", 13.2), Some(11.375));
        assert_eq!(font.line_width("", 12.0), Some(0.0));
    }

    #[test]
    fn missing_glyphs_and_rtl_decline() {
        let Some(data) = load(SANS) else { return };
        let font = Font::new(&data, 0).unwrap();
        assert!(font.line_width("漢字", 12.0).is_none());
        assert!(font.line_width("a🦀", 12.0).is_none());
        assert!(font.line_width("שלום", 12.0).is_none());
        let mut h = Hinted::new(&font, 12.0).unwrap();
        assert!(string_metrics(&font, &mut h, "漢", 12.0, 14.4).is_none());
        assert!(font.covers("Two\nlines é"));
        assert!(!font.covers("漢") && !font.covers("שלום"));
    }

    #[test]
    fn hinted_rows_sit_on_the_baseline() {
        let Some(data) = load(SANS) else { return };
        let font = Font::new(&data, 0).unwrap();
        let mut h = Hinted::new(&font, 11.0).unwrap();
        // Values from grid's strascent/strdescent on ragg at 72 dpi.
        assert_eq!(h.char_metric('M'), Some((8.0, 0.0)));
        assert_eq!(h.char_metric('g'), Some((6.0, 2.0)));
        assert_eq!(h.char_metric(' '), Some((1.0, 1.0)));
        let m = string_metrics(&font, &mut h, "g\nM", 11.0, 13.2).unwrap();
        assert_eq!(m.height, 13.2 + 8.0);
        assert_eq!(m.ascent, 6.0 + 13.2);
        assert_eq!(m.descent, 0.0);
    }
}
