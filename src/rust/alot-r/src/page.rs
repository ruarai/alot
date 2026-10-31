//! Glue for the full tier's page (`alot_core::render::page`): reads the
//! page spec R builds (R/render-full.R) and renders it.

use alot_core::render::agg::{Cap, Join};
use alot_core::render::axis::{Axis, Side, Ticks};
use alot_core::render::layout::TitleGrob;
use alot_core::render::legend::{Bar, BarTicks, Body, Guide, Keys, LegendGroup};
use alot_core::render::page::{draw_page, LineStyle, PageSpec, RectEl, TextStyle, WrapDraw};
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
pub(crate) struct Fonts {
    pub(crate) keys: Vec<(String, u32)>,
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
    point_layers(l, 1)?.pop()
}

/// A point layer dealt out to `n_panels` panels by its `panel` column
/// (1-based; absent for one panel): a layer for each panel with rows.
fn point_layers(l: &List, n_panels: usize) -> Option<Vec<PointLayer>> {
    // Borrowed columns: a million rows are dealt out, not copied twice.
    let robj = |name: &str| field(l, name);
    let (xr, yr) = (robj("x")?, robj("y")?);
    let (shape_r, size_r, stroke_r) = (robj("shape")?, robj("size")?, robj("stroke")?);
    let (col_r, fill_r) = (robj("colour")?, robj("fill")?);
    let (x, y) = (xr.as_real_slice()?, yr.as_real_slice()?);
    let (shape, size, stroke) = (shape_r.as_real_slice()?, size_r.as_real_slice()?, stroke_r.as_real_slice()?);
    let (col, fill) = (col_r.as_integer_slice()?, fill_r.as_integer_slice()?);
    let n = x.len();
    let recycles = |v: &[f64]| (v.len() == 1 || v.len() == n) && !v.iter().any(|v| v.is_nan());
    let [x0, x1] = nums(l, "x_range")?[..] else { return None };
    let [y0, y1] = nums(l, "y_range")?[..] else { return None };
    let [pt, stroke_scale, res] = nums(l, "consts")?[..] else { return None };
    if y.len() != n || col.len() != n || fill.len() != n || ![shape, size, stroke].into_iter().all(recycles) {
        return None;
    }
    let make = |idx: Option<&[u32]>| {
        let pick = |v: &[f64]| match idx {
            Some(i) if v.len() == n => i.iter().map(|&k| v[k as usize]).collect(),
            _ => v.to_vec(),
        };
        let pick_c = |v: &[i32]| -> Vec<[u8; 4]> {
            match idx {
                Some(i) => i.iter().map(|&k| (v[k as usize] as u32).to_le_bytes()).collect(),
                None => v.iter().map(|&c| (c as u32).to_le_bytes()).collect(),
            }
        };
        PointLayer {
            x: pick(x), y: pick(y), x_range: [x0, x1], y_range: [y0, y1], shape: pick(shape), size: pick(size),
            stroke: pick(stroke), col: pick_c(col), fill: pick_c(fill), pt, stroke_scale, res,
        }
    };
    let Some(panel_r) = field(l, "panel") else {
        return Some(vec![make(None)]);
    };
    let panel = panel_r.as_integer_slice()?;
    if panel.len() != n || panel.iter().any(|&p| p < 1 || p as usize > n_panels) {
        return None;
    }
    let mut counts = vec![0usize; n_panels];
    for &p in panel {
        counts[p as usize - 1] += 1;
    }
    let mut rows: Vec<Vec<u32>> = counts.iter().map(|&c| Vec::with_capacity(c)).collect();
    for (i, &p) in panel.iter().enumerate() {
        rows[p as usize - 1].push(i as u32);
    }
    // One element per panel, empty ones as zero-point layers.
    Some(rows.iter().map(|r| make(Some(r))).collect())
}

fn panel(l: &List, points: Vec<PointLayer>) -> Option<Panel> {
    let mut grid = Vec::new();
    for (_, g) in list_of(l, "grid")?.iter() {
        let g = List::try_from(g).ok()?;
        grid.push(GridLines { pos: nums(&g, "pos")?, horizontal: flag(&g, "horizontal")?, style: line_style(&list_of(&g, "style")?)? });
    }
    Some(Panel { clip: flag(l, "clip")?, background: opt(l, "background", rect_el)?, grid, points, border: opt(l, "border", rect_el)? })
}

impl Fonts {
    pub(crate) fn new() -> Self {
        Fonts { keys: Vec::new() }
    }
}

fn side(l: &List, name: &str) -> Option<Side> {
    match field(l, name)?.as_str()? {
        "top" => Some(Side::Top),
        "right" => Some(Side::Right),
        "bottom" => Some(Side::Bottom),
        "left" => Some(Side::Left),
        _ => None,
    }
}

fn pair(l: &List, name: &str) -> Option<(f64, f64)> {
    let v = nums(l, name)?;
    Some((*v.first()?, *v.get(1)?))
}

/// A guide: see `legend_guide()` and `legend_bar()` in R/render-legend.R.
fn guide(l: &List, fonts: &mut Fonts) -> Option<Guide> {
    let body = match field(l, "kind")?.as_str()? {
        "legend" => {
            let dim = nums(l, "dim")?;
            let (key_w, key_h) = (nums(l, "key_w")?, nums(l, "key_h")?);
            let mut marks = Vec::new();
            for (_, m) in list_of(l, "marks")?.iter() {
                let mut layers = Vec::new();
                if !m.is_null() {
                    for (_, layer) in List::try_from(m).ok()?.iter() {
                        layers.push(point_layer(&List::try_from(layer).ok()?)?);
                    }
                }
                marks.push(layers);
            }
            let mut labels = Vec::new();
            for (_, t) in list_of(l, "labels")?.iter() {
                labels.push(title(&List::try_from(t).ok()?, fonts)?);
            }
            if key_w.len() != key_h.len() || marks.len() != key_w.len() || !(labels.is_empty() || labels.len() == key_w.len()) {
                return None;
            }
            Body::Keys(Keys {
                nrow: *dim.first()? as usize,
                ncol: *dim.get(1)? as usize,
                byrow: flag(l, "byrow")?,
                key_w,
                key_h,
                default: pair(l, "default")?,
                bg: opt(l, "key_bg", rect_el)?,
                marks,
                labels,
                spacing: pair(l, "spacing")?,
            })
        }
        "bar" => Body::Bar(Bar {
            size: pair(l, "bar_size")?,
            horizontal: flag(l, "horizontal")?,
            image: colours(l, "image")?,
            frame: opt(l, "frame", rect_el)?,
            ticks: opt(l, "ticks", |t| {
                let len = nums(t, "len")?;
                Some(BarTicks { pos: nums(t, "pos")?, len: [*len.first()?, *len.get(1)?], style: line_style(&list_of(t, "style")?)? })
            })?,
            labels: opt(l, "bar_labels", |t| title(t, fonts))?,
        }),
        _ => return None,
    };
    Some(Guide {
        body,
        title: opt(l, "title", |t| title(t, fonts))?,
        title_position: side(l, "title_position")?,
        title_just: pair(l, "title_just")?,
        text_position: side(l, "text_position")?,
        padding: nums(l, "padding")?.try_into().ok()?,
        background: opt(l, "background", rect_el)?,
    })
}

/// A position's legend box: see `legend_box()` in R/render-legend.R.
pub(crate) fn legend_group(l: &List, fonts: &mut Fonts) -> Option<LegendGroup> {
    let mut guides = Vec::new();
    for (_, g) in list_of(l, "guides")?.iter() {
        guides.push(guide(&List::try_from(g).ok()?, fonts)?);
    }
    Some(LegendGroup {
        horizontal: flag(l, "horizontal")?,
        spacing: num(l, "spacing")?,
        box_just: pair(l, "box_just")?,
        global_just: pair(l, "global_just")?,
        guides,
    })
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
    let mut legends = Vec::new();
    for (cell, name) in [
        ("legend_right", "guide-box-right"), ("legend_left", "guide-box-left"),
        ("legend_bottom", "guide-box-bottom"), ("legend_top", "guide-box-top"),
    ] {
        if let Some(l) = field(&layout, cell).and_then(|r| List::try_from(r).ok()) {
            legends.push((name.to_string(), legend_group(&l, &mut fonts)?));
        }
    }
    let is_wrap = field(&layout, "wrap").is_some();
    let mut axes = Vec::new();
    let mut by_side: [Option<alot_core::render::axis::Axis>; 4] = [None, None, None, None];
    for (cell, name, k) in [("axis_t", "axis-t", 0), ("axis_b", "axis-b", 1), ("axis_l", "axis-l", 2), ("axis_r", "axis-r", 3)] {
        if let Some(a) = opt(&layout, cell, |l| axis(l, &mut fonts))? {
            if is_wrap {
                by_side[k] = Some(a);
            } else {
                axes.push((name.to_string(), a));
            }
        }
    }
    let [axes_t, axes_b, axes_l, axes_r] = by_side;
    let wrap_spec = crate::layout::wrap(&layout)?;
    let mut panels = Vec::new();
    let n_panels = list_of(spec, "panels")?.len();
    let mut layers: Vec<std::vec::IntoIter<PointLayer>> = Vec::new();
    for (_, l) in list_of(spec, "points")?.iter() {
        layers.push(point_layers(&List::try_from(l).ok()?, n_panels)?.into_iter());
    }
    for (i, (_, pl)) in list_of(spec, "panels")?.iter().enumerate() {
        let name = match &wrap_spec {
            Some(w) => {
                let (r, c) = *w.panels.get(i)?;
                format!("panel-{}-{}", c + 1, r + 1)
            }
            None => "panel".to_string(),
        };
        // With one panel the layer's `panel` is absent: its single element.
        let points = layers.iter_mut().filter_map(|it| it.next()).filter(|p| !p.x.is_empty()).collect();
        panels.push((name, panel(&List::try_from(pl).ok()?, points)?));
    }
    let mut wrap = None;
    if let Some(spec_w) = wrap_spec {
        let w = list_of(&layout, "wrap")?;
        let mut strips = Vec::new();
        if let Some(s) = field(&w, "strips") {
            for (_, t) in List::try_from(s).ok()?.iter() {
                strips.push(title(&List::try_from(t).ok()?, &mut fonts)?);
            }
        }
        wrap = Some(WrapDraw {
            spec: spec_w,
            axes: [axes_t, axes_b, axes_l, axes_r],
            strips,
            strip_bg: opt(&w, "strip_bg", rect_el)?,
            strip_clip: flag(&w, "strip_clip")?,
        });
    }
    let page = PageSpec {
        width: w,
        height: h,
        bg: rgba(spec, "bg")?,
        table: build(&layout)?,
        background: opt(spec, "background", rect_el)?,
        panels,
        axes,
        wrap,
        titles,
        legends,
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
