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
        if line.is_empty() {
            return Some(0.0);
        }
        if line.chars().any(is_rtl) {
            return None;
        }
        let x_scale = self.x_scale(size);
        // hb_ft_font_changed() sets the hb_font scale from x_scale; GPOS
        // values scale by em_mult() (HarfBuzz 2.7 hb-font.hh).
        let hb_scale = ((x_scale * self.upem + (1 << 15)) >> 16) as i64;
        let x_mult = (hb_scale << 16) / self.upem;
        let mut buffer = rustybuzz::UnicodeBuffer::new();
        buffer.push_str(line);
        buffer.guess_segment_properties();
        let shaped = rustybuzz::shape(&self.shaper, &[], buffer);
        let mut width: i64 = 0;
        for (info, pos) in shaped.glyph_infos().iter().zip(shaped.glyph_positions()) {
            if info.glyph_id == 0 {
                return None;
            }
            let units = self.shaper.glyph_hor_advance(GlyphId(info.glyph_id as u16))? as i64;
            if pos.x_advance == 0 {
                continue;
            }
            // hb_ft_get_glyph_h_advances(): FT_Get_Advance() unhinted is
            // FT_MulDiv(units, x_scale, 64) in 16.16, rounded to 26.6.
            let advance = (mul_div(units, x_scale, 64) + (1 << 9)) >> 10;
            let adjust = ((pos.x_advance as i64 - units) * x_mult) >> 16;
            width += advance + adjust;
        }
        Some(width as f64 / 64.0)
    }
}

/// Right-to-left scripts: textshaping splits these into bidi embeddings,
/// which isn't mirrored.
fn is_rtl(c: char) -> bool {
    matches!(c as u32, 0x0590..=0x08FF | 0xFB1D..=0xFDFF | 0xFE70..=0xFEFF | 0x10800..=0x10FFF | 0x1E800..=0x1EFFF)
}

/// Hinted glyph rows at one pixel size, cached per glyph.
pub struct Hinted<'f, 'a> {
    font: &'f Font<'a>,
    hinter: Option<HintingInstance>,
    /// `size / (floor(size * 64) / 64)`: ragg scales glyph bounds by the
    /// requested over the engine's 26.6 height.
    scale: f64,
    rows: HashMap<u32, Option<(i32, i32)>>,
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
        let ppem = (height >> 6).max(1);
        let hinter = HintingInstance::new(&font.outlines, Size::new(ppem as f32), LocationRef::default(), HintingOptions::default()).ok();
        Some(Hinted { font, hinter, scale: size / (height as f64 / 64.0), rows: HashMap::new() })
    }

    /// The topmost and bottommost pixel rows (y down, baseline between rows
    /// -1 and 0) of glyph `gid` as ragg's glyph cache records them, or
    /// `None` if it can't be hinted as FreeType would.
    fn glyph_rows(&mut self, gid: u32) -> Option<(i32, i32)> {
        if let Some(r) = self.rows.get(&gid) {
            return *r;
        }
        let r = self.compute_rows(gid);
        self.rows.insert(gid, r);
        r
    }

    fn compute_rows(&self, gid: u32) -> Option<(i32, i32)> {
        let glyph = self.font.outlines.get(skrifa::GlyphId::new(gid))?;
        let mut pen = FlatPen::default();
        glyph.draw(DrawSettings::hinted(self.hinter.as_ref()?, false), &mut pen).ok()?;
        pen.close();
        let cov = agg::rasterize(&pen.contours);
        if pen.cubic {
            return None;
        }
        // The engine's rasteriser maps alpha through gamma_power(1.6)
        // (ragg text_renderer.h); a row counts once any alpha survives.
        let lut = |a: u8| ((a as f64 / 255.0).powf(1.6) * 255.0 + 0.5) as u32;
        let lit = |j: usize| cov.alpha[j * cov.w..(j + 1) * cov.w].iter().any(|&a| lut(a) > 0);
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

/// Flattens a hinted outline as AGG's `conv_curve` does, flipping y.
#[derive(Default)]
struct FlatPen {
    contours: Vec<Vec<[f64; 2]>>,
    current: Vec<[f64; 2]>,
    cubic: bool,
}

impl OutlinePen for FlatPen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.close();
        self.current.push([x as f64, -y as f64]);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.current.push([x as f64, -y as f64]);
    }
    fn quad_to(&mut self, cx0: f32, cy0: f32, x: f32, y: f32) {
        let p1 = *self.current.last().unwrap_or(&[0.0, 0.0]);
        agg::curve3(p1, [cx0 as f64, -cy0 as f64], [x as f64, -y as f64], &mut self.current);
    }
    fn curve_to(&mut self, _: f32, _: f32, _: f32, _: f32, x: f32, y: f32) {
        // Only TrueType outlines reach here; they have no cubics.
        self.cubic = true;
        self.current.push([x as f64, -y as f64]);
    }
    fn close(&mut self) {
        if !self.current.is_empty() {
            self.contours.push(std::mem::take(&mut self.current));
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
