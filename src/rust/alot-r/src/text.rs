//! Glue for string metrics (`alot_core::render::text`).

use alot_core::render::raster::unpremultiply;
use alot_core::render::text::{self, Font, Hinted, Run};
use extendr_api::prelude::*;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

/// Font file bytes, read once per session per path.
pub(crate) fn font_data(path: &str) -> Option<Arc<Vec<u8>>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Arc<Vec<u8>>>>> = OnceLock::new();
    let mut cache = CACHE.get_or_init(Default::default).lock().ok()?;
    if let Some(d) = cache.get(path) {
        return Some(d.clone());
    }
    let d = Arc::new(std::fs::read(path).ok()?);
    cache.insert(path.to_string(), d.clone());
    Some(d)
}

/// Metrics in device pixels of each UTF-8 string `text[i]` in font
/// `font[i]` (1-based into the files `path` with face `index`) at `size[i]`
/// pixels and line height `line[i]` pixels: a list of `width`, `ascent`,
/// `descent` and `height` (`GEStrWidth()`, `GEStrMetric()`,
/// `GEStrHeight()` on a ragg device). Entries are NA where alot doesn't
/// mirror ragg: an NA string, an unreadable or unsupported font, or a
/// glyph the font lacks (ragg would use a fallback font).
/// @noRd
#[extendr(r_name = "rs_text_metrics")]
fn text_metrics(text: Strings, font: &[i32], path: Strings, index: &[i32], size: &[f64], line: &[f64]) -> List {
    let n = text.len();
    if n == 0 {
        let empty = || -> Robj { Doubles::new(0).into() };
        return List::from_names_and_values(["width", "ascent", "descent", "height"], [empty(), empty(), empty(), empty()]).unwrap();
    }
    let mut out = vec![[f64::NAN; 4]; n];
    let data: Vec<Option<Arc<Vec<u8>>>> = path.iter().map(|p| if p.is_na() { None } else { font_data(&p) }).collect();
    let fonts: Vec<Option<Font>> = data
        .iter()
        .zip(index)
        .map(|(d, &i)| d.as_ref().and_then(|d| Font::new(d, i.max(0) as u32)))
        .collect();
    // Strings by (font, size), so each gets one hinting instance.
    let mut groups: HashMap<(usize, u64), Vec<usize>> = HashMap::new();
    for i in 0..n {
        let f = font[i];
        if f >= 1 && (f as usize) <= fonts.len() {
            groups.entry((f as usize - 1, size[i].to_bits())).or_default().push(i);
        }
    }
    for ((f, bits), rows) in groups {
        let Some(font) = fonts[f].as_ref() else { continue };
        let size = f64::from_bits(bits);
        let Some(mut hinted) = Hinted::new(font, size) else { continue };
        for i in rows {
            let s = text.elt(i);
            if s.is_na() {
                continue;
            }
            if let Some(m) = text::string_metrics(font, &mut hinted, &s, size, line[i]) {
                out[i] = [m.width, m.ascent, m.descent, m.height];
            }
        }
    }
    let col = |k: usize| -> Robj { Doubles::from_values(out.iter().map(|m| if m[k].is_nan() { Rfloat::na() } else { Rfloat::from(m[k]) })).into() };
    List::from_names_and_values(["width", "ascent", "descent", "height"], [col(0), col(1), col(2), col(3)]).unwrap()
}

/// Whether each string `text[i]` can be drawn from font file `path` (face
/// `index`) alone: every character has a glyph and none is right-to-left.
/// All `FALSE` if the font can't be read or isn't one alot mirrors; NA
/// strings are `TRUE`.
/// @noRd
#[extendr(r_name = "rs_text_covered")]
fn text_covered(text: Strings, path: &str, index: i32) -> Logicals {
    // A zero-length vector's data pointer isn't aligned; don't slice it.
    if text.is_empty() {
        return Logicals::new(0);
    }
    let data = font_data(path);
    let font = data.as_ref().and_then(|d| Font::new(d, index.max(0) as u32));
    Logicals::from_values(text.iter().map(|s| s.is_na() || font.as_ref().is_some_and(|f| f.covers(&s))).collect::<Vec<_>>())
}

/// Draws strings `text` (UTF-8) as grid's text on a ragg device does:
/// anchors (`x`, `y`, device pixels from the top left), `hjust`, `vjust` and
/// `rot` (degrees) recycled per string, in one font (file `path`, face
/// `index`) at `size` pixels with line height `line` pixels, in `colour`
/// (packed RGBA as from `rs_point_colours()`), clipped to `clip` (x0, y0,
/// x1, y1: ragg's inclusive integer clip box). Returns a list of `x0`, `y0`
/// (the image's top-left pixel) and `raster` (a nativeRaster), a list with
/// `raster = NULL` if nothing is visible, or `NULL` (decline) where ragg
/// would use a fallback font or alot doesn't mirror the font.
/// @noRd
#[extendr(r_name = "rs_render_text")]
#[allow(clippy::too_many_arguments)]
fn render_text(text: Strings, x: &[f64], y: &[f64], hjust: &[f64], vjust: &[f64], rot: &[f64], path: &str, index: i32, size: f64, line: f64, colour: i32, clip: &[i32]) -> Robj {
    let decline = || Robj::from(());
    let Some(data) = font_data(path) else { return decline() };
    let Some(font) = Font::new(&data, index.max(0) as u32) else { return decline() };
    let Some(mut hinted) = Hinted::new(&font, size) else { return decline() };
    let at = |v: &[f64], i: usize| if v.len() == 1 { v[0] } else { v[i] };
    let n = text.len();
    if n == 0 {
        return List::from_names_and_values(["x0", "y0", "raster"], [Robj::from(0), Robj::from(0), Robj::from(())]).unwrap().into();
    }
    if [x.len(), y.len(), hjust.len(), vjust.len(), rot.len()].iter().any(|&l| l != 1 && l != n) {
        return decline();
    }
    // grid draws an NA label as "NA" (CHAR(NA_STRING)).
    let strings: Vec<String> = text.iter().map(|s| if s.is_na() { "NA".to_string() } else { s.to_string() }).collect();
    let runs: Vec<Run> = (0..n)
        .filter_map(|i| {
            let t = strings[i].as_str();
            let (xi, yi) = (at(x, i), at(y, i));
            (xi.is_finite() && yi.is_finite()).then_some(Run { x: xi, y: yi, hjust: at(hjust, i), vjust: at(vjust, i), rot: at(rot, i), text: t })
        })
        .collect();
    let c = colour as u32;
    let rgba = [c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8];
    let Ok(clip) = <[i32; 4]>::try_from(clip) else { return decline() };
    let Some(image) = text::draw_runs(&font, &mut hinted, size, line, &runs, rgba, clip) else { return decline() };
    let Some(image) = image else {
        return List::from_names_and_values(["x0", "y0", "raster"], [Robj::from(0), Robj::from(0), Robj::from(())]).unwrap().into();
    };
    let (raster, ptr) = super::render::native_raster(image.w, image.h);
    let out = unsafe { std::slice::from_raw_parts_mut(ptr, image.w * image.h) };
    for (d, &[r, g, b, a]) in out.iter_mut().zip(&image.px) {
        *d = unpremultiply(r, g, b, a);
    }
    List::from_names_and_values(["x0", "y0", "raster"], [Robj::from(image.x0), Robj::from(image.y0), raster]).unwrap().into()
}

extendr_module! {
    mod text;
    fn render_text;
    fn text_metrics;
    fn text_covered;
}
