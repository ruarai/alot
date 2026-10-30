//! Glue for string metrics (`alot_core::render::text`).

use alot_core::render::text::{self, Font, Hinted};
use extendr_api::prelude::*;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

/// Font file bytes, read once per session per path.
fn font_data(path: &str) -> Option<Arc<Vec<u8>>> {
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
    let data = font_data(path);
    let font = data.as_ref().and_then(|d| Font::new(d, index.max(0) as u32));
    Logicals::from_values(text.iter().map(|s| s.is_na() || font.as_ref().is_some_and(|f| f.covers(&s))).collect::<Vec<_>>())
}

extendr_module! {
    mod text;
    fn text_metrics;
    fn text_covered;
}
