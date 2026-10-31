//! Glue for the full tier's page (`alot_core::render::page`): reads the
//! page spec R builds (R/render-full.R) and renders it.

use alot_core::render::agg::{Cap, Join};
use alot_core::render::axis::{Axis, Side, Ticks};
use alot_core::render::layout::TitleGrob;
use alot_core::render::page::{draw_page, LineStyle, PageSpec, RectEl, TextStyle};
use alot_core::render::panel::{GridLines, Panel, PointLayer};
use alot_core::render::raster;
use alot_core::render::text::Font;
use alot_core::render::title::Title;
use extendr_api::prelude::*;

use crate::layout::{build, field, flag, list_of, num, nums};
use crate::text::font_data;

fn rgba(l: &List, name: &str) -> Option<[u8; 4]> {
    let c = field(l, name)?.as_integer_slice()?.first().copied()? as u32;
    Some([c as u8, (c >> 8) as u8, (c >> 16) as u8, (c >> 24) as u8])
}

fn line_style(l: &List) -> Option<LineStyle> {
    Some(LineStyle {
        col: rgba(l, "col")?,
        lwd: num(l, "lwd")?,
        lty: num(l, "lty")? as u32,
        cap: [Cap::Round, Cap::Butt, Cap::Square].get(num(l, "cap")? as usize).copied()?,
        join: [Join::Round, Join::Miter, Join::Bevel].get(num(l, "join")? as usize).copied()?,
    })
}

fn rect_el(l: &List) -> Option<RectEl> {
    Some(RectEl {
        fill: rgba(l, "fill")?,
        col: rgba(l, "col")?,
        lwd: num(l, "lwd")?,
        join: [Join::Miter, Join::Round, Join::Bevel].get(num(l, "join")? as usize).copied()?,
    })
}

/// `None` for an absent field, `Some(None)` if malformed.
fn opt<T>(l: &List, name: &str, mut f: impl FnMut(&List) -> Option<T>) -> Option<Option<T>> {
    match field(l, name) {
        None => Some(None),
        Some(r) => Some(Some(f(&List::try_from(r).ok()?)?)),
    }
}

/// Font table entries are interned by (path, face index).
struct Fonts {
    keys: Vec<(String, u32)>,
}

impl Fonts {
    fn index(&mut self, path: String, index: u32) -> usize {
        match self.keys.iter().position(|k| k.0 == path && k.1 == index) {
            Some(i) => i,
            None => {
                self.keys.push((path, index));
                self.keys.len() - 1
            }
        }
    }
}

/// A title grob with what draws it: see `layout_title()` in
/// R/render-layout.R.
fn title(l: &List, fonts: &mut Fonts) -> Option<Title> {
    let grob: TitleGrob = crate::layout::title(l)?;
    let labels: Vec<String> = field(l, "label")?.as_str_vector()?.into_iter().map(String::from).collect();
    if labels.len() != grob.labels.len() {
        return None;
    }
    let just = nums(l, "just")?;
    let path = field(l, "font_path")?.as_str()?.to_string();
    let style = TextStyle {
        font: fonts.index(path, num(l, "font_index")? as u32),
        size: num(l, "size")?,
        line: num(l, "line")?,
        colour: rgba(l, "colour")?,
    };
    Some(Title {
        grob,
        labels,
        x: nums(l, "x"),
        y: nums(l, "y"),
        just: (*just.first()?, *just.get(1)?),
        style,
        check_overlap: flag(l, "check_overlap")?,
    })
}

fn ticks(l: &List) -> Option<Ticks> {
    Some(Ticks { pos: nums(l, "pos")?, len: num(l, "len")?, style: line_style(&list_of(l, "style")?)? })
}

fn axis(l: &List, fonts: &mut Fonts) -> Option<Axis> {
    let side = match field(l, "side")?.as_str()? {
        "top" => Side::Top,
        "right" => Side::Right,
        "bottom" => Side::Bottom,
        "left" => Side::Left,
        _ => return None,
    };
    let mut labels = Vec::new();
    for (_, item) in list_of(l, "items")?.iter() {
        labels.push(title(&List::try_from(item).ok()?, fonts)?);
    }
    Some(Axis {
        side,
        line: opt(l, "line", line_style)?,
        major_len: num(l, "major")?,
        minor_len: num(l, "minor"),
        ticks: opt(l, "ticks", ticks)?,
        minor_ticks: opt(l, "minor_ticks", ticks)?,
        labels,
        just: num(l, "just")?,
    })
}

/// A column of packed colours (`R | G << 8 | B << 16 | A << 24`).
fn colours(l: &List, name: &str) -> Option<Vec<[u8; 4]>> {
    let v = field(l, name)?.as_integer_slice()?.to_vec();
    Some(v.into_iter().map(|c| (c as u32).to_le_bytes()).collect())
}

/// A point layer: see `full_points()` in R/render-full.R. Columns of
/// length 1 or n recycle; NA is declined.
fn point_layer(l: &List) -> Option<PointLayer> {
    let x = nums(l, "x")?;
    let n = x.len();
    let y = nums(l, "y")?;
    let (shape, size, stroke) = (nums(l, "shape")?, nums(l, "size")?, nums(l, "stroke")?);
    let (col, fill) = (colours(l, "colour")?, colours(l, "fill")?);
    let recycles = |v: &Vec<f64>| (v.len() == 1 || v.len() == n) && !v.iter().any(|v| v.is_nan());
    let [x0, x1] = nums(l, "x_range")?[..] else { return None };
    let [y0, y1] = nums(l, "y_range")?[..] else { return None };
    let [pt, stroke_scale, res] = nums(l, "consts")?[..] else { return None };
    if y.len() != n || col.len() != n || fill.len() != n || ![&shape, &size, &stroke].into_iter().all(recycles) {
        return None;
    }
    Some(PointLayer { x, y, x_range: [x0, x1], y_range: [y0, y1], shape, size, stroke, col, fill, pt, stroke_scale, res })
}

fn panel(l: &List) -> Option<Panel> {
    let mut grid = Vec::new();
    for (_, g) in list_of(l, "grid")?.iter() {
        let g = List::try_from(g).ok()?;
        grid.push(GridLines { pos: nums(&g, "pos")?, horizontal: flag(&g, "horizontal")?, style: line_style(&list_of(&g, "style")?)? });
    }
    let mut points = Vec::new();
    for (_, p) in list_of(l, "points")?.iter() {
        points.push(point_layer(&List::try_from(p).ok()?)?);
    }
    Some(Panel { clip: flag(l, "clip")?, background: opt(l, "background", rect_el)?, grid, points, border: opt(l, "border", rect_el)? })
}

/// Draws a single-panel plot's page (see `page_spec()` in
/// R/render-full.R for the spec) to a nativeRaster, or returns NULL
/// (decline) where something isn't drawn as ragg does.
/// @noRd
#[extendr(r_name = "rs_render_page")]
fn render_page(spec: List, threads: i32) -> Robj {
    render(&spec, threads).unwrap_or_else(|| Robj::from(()))
}

fn render(spec: &List, threads: i32) -> Option<Robj> {
    let &[w, h] = field(spec, "page")?.as_integer_slice()? else { return None };
    let (w, h) = (w as usize, h as usize);
    let layout = list_of(spec, "layout")?;
    let mut fonts = Fonts { keys: Vec::new() };
    let mut titles = Vec::new();
    for (cell, name) in [
        ("xlab_t", "xlab-t"), ("xlab_b", "xlab-b"), ("ylab_l", "ylab-l"), ("ylab_r", "ylab-r"),
        ("title", "title"), ("subtitle", "subtitle"), ("caption", "caption"),
    ] {
        if let Some(t) = opt(&layout, cell, |l| title(l, &mut fonts))? {
            titles.push((name.to_string(), t));
        }
    }
    if let Some(tag) = opt(&layout, "tag", |t| title(&list_of(t, "item")?, &mut fonts))? {
        titles.push(("tag".to_string(), tag));
    }
    let mut axes = Vec::new();
    for (cell, name) in [("axis_t", "axis-t"), ("axis_l", "axis-l"), ("axis_r", "axis-r"), ("axis_b", "axis-b")] {
        if let Some(a) = opt(&layout, cell, |l| axis(l, &mut fonts))? {
            axes.push((name.to_string(), a));
        }
    }
    let page = PageSpec {
        width: w,
        height: h,
        bg: rgba(spec, "bg")?,
        table: build(&layout)?,
        background: opt(spec, "background", rect_el)?,
        panel: panel(&list_of(spec, "panel")?)?,
        axes,
        titles,
        threads: threads.max(0) as usize,
    };
    let data: Vec<std::sync::Arc<Vec<u8>>> = fonts.keys.iter().map(|k| font_data(&k.0)).collect::<Option<_>>()?;
    let faces: Vec<Font> = data.iter().zip(&fonts.keys).map(|(d, k)| Font::new(d, k.1)).collect::<Option<_>>()?;
    let list = draw_page(&page, &faces)?;
    let (out, ptr) = crate::render::native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&list, w, h, &opts, pixels);
    Some(out)
}

extendr_module! {
    mod page;
    fn render_page;
}
