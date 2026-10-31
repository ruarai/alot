//! Glue for the full tier's page (`alot_core::render::page`): reads the
//! page spec R builds (R/render-full.R) and renders it.

use alot_core::render::agg::{Cap, Join};
use alot_core::render::axis::{Axis, Side, Ticks};
use alot_core::render::layout::TitleGrob;
use alot_core::render::legend::{Bar, BarTicks, Bins, Body, Glyph, Guide, Keys, LegendGroup};
use alot_core::render::display::{DisplayList, Rect};
use alot_core::render::png::{render_png, PngOptions};
use alot_core::render::page::{draw_page, FacetDraw, LineStyle, PageSpec, Painter, RectEl, StripDraw, TextStyle};
use alot_core::render::layers::{Label, LabelLayer, PathLayer, RectLayer, TextLayer};
use alot_core::render::panel::{GridLines, Layer, Panel, PointLayer};
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
        lty: match field(l, "lty") {
            None => 0,
            Some(_) => num(l, "lty")? as u32,
        },
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
        shift: (0.0, 0.0),
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

/// One panel's dealt columns: `reals`, then the colours.
type Dealt<const K: usize> = (Vec<Vec<f64>>, [Vec<[u8; 4]>; K]);

/// Columns `reals` and packed colours `ints` dealt out to `n_panels` panels
/// by `panel` (1-based; every row to the first if `None`), keeping row
/// order. Each column is read once, in parallel chunks of rows that write
/// their own ranges of every panel's columns, so a million rows' fresh pages
/// are first touched in parallel. `None` if a panel is out of range or a
/// row fails `valid`.
fn deal<const K: usize>(
    n: usize,
    panel: Option<&[i32]>,
    n_panels: usize,
    valid: impl Fn(usize) -> bool + Sync,
    reals: &[&[f64]],
    ints: [&[i32]; K],
) -> Option<Vec<Dealt<K>>> {
    struct Dst<T>(*mut T);
    unsafe impl<T> Sync for Dst<T> {}
    let chunk = n.div_ceil(raster::default_threads()).max(1 << 15);
    let starts: Vec<usize> = (0..n).step_by(chunk).collect();
    let counts: Vec<Option<Vec<usize>>> = raster::par_map(starts.iter(), |&a| {
        let mut c = vec![0usize; n_panels];
        for i in a..(a + chunk).min(n) {
            let p = panel.map_or(1, |p| p[i]);
            if p < 1 || p as usize > n_panels || !valid(i) {
                return None;
            }
            c[p as usize - 1] += 1;
        }
        Some(c)
    });
    let counts: Vec<Vec<usize>> = counts.into_iter().collect::<Option<_>>()?;
    // Each chunk's first position in each panel's columns.
    let mut offsets = vec![vec![0usize; n_panels]; counts.len()];
    let mut totals = vec![0usize; n_panels];
    for (c, cnt) in counts.iter().enumerate() {
        for p in 0..n_panels {
            offsets[c][p] = totals[p];
            totals[p] += cnt[p];
        }
    }
    let mut out: Vec<Dealt<K>> = totals
        .iter()
        .map(|&m| (reals.iter().map(|_| Vec::with_capacity(m)).collect(), std::array::from_fn(|_| Vec::with_capacity(m))))
        .collect();
    let r_dst: Vec<Vec<Dst<f64>>> = out.iter_mut().map(|(r, _)| r.iter_mut().map(|v| Dst(v.as_mut_ptr())).collect()).collect();
    let c_dst: Vec<Vec<Dst<[u8; 4]>>> = out.iter_mut().map(|(_, c)| c.iter_mut().map(|v| Dst(v.as_mut_ptr())).collect()).collect();
    raster::par_map(starts.iter().zip(offsets), |(&a, mut at)| {
        for i in a..(a + chunk).min(n) {
            let p = panel.map_or(0, |p| p[i] as usize - 1);
            let k = at[p];
            at[p] += 1;
            // SAFETY: chunks write disjoint ranges of each panel's columns
            // (offsets above), within the capacity reserved for them.
            for (src, d) in reals.iter().zip(&r_dst[p]) {
                unsafe { d.0.add(k).write(src[i]) };
            }
            for (src, d) in ints.iter().zip(&c_dst[p]) {
                unsafe { d.0.add(k).write((src[i] as u32).to_le_bytes()) };
            }
        }
    });
    // SAFETY: every row of each panel was written above.
    for ((r, c), &m) in out.iter_mut().zip(&totals) {
        for v in r.iter_mut() {
            unsafe { v.set_len(m) };
        }
        for v in c.iter_mut() {
            unsafe { v.set_len(m) };
        }
    }
    Some(out)
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
    let (xr, yr) = (ranges(l, "x_range", n_panels)?, ranges(l, "y_range", n_panels)?);
    let [pt, stroke_scale, res] = nums(l, "consts")?[..] else { return None };
    let styles = [shape, size, stroke];
    // Columns of length 1 recycle; NA is declined (the long ones' rows as
    // they are dealt out).
    let recycles = |v: &[f64]| v.len() == n || (v.len() == 1 && !v[0].is_nan());
    if y.len() != n || col.len() != n || fill.len() != n || !styles.into_iter().all(recycles) {
        return None;
    }
    let panel_r = field(l, "panel");
    let panel = match &panel_r {
        Some(p) => Some(p.as_integer_slice()?).filter(|p| p.len() == n),
        None => None,
    };
    if panel_r.is_some() && panel.is_none() {
        return None;
    }
    let long: Vec<&[f64]> = [x, y, shape, size, stroke].into_iter().filter(|v| v.len() == n).collect();
    let checked: Vec<&[f64]> = styles.into_iter().filter(|v| v.len() == n).collect();
    let valid = |i: usize| !checked.iter().any(|v| v[i].is_nan());
    let dealt = deal(n, panel, if panel.is_some() { n_panels } else { 1 }, valid, &long, [col, fill])?;
    // One element per panel, empty ones as zero-point layers.
    Some(
        dealt
            .into_iter()
            .enumerate()
            .map(|(k, (reals, [col, fill]))| {
                let mut reals = reals.into_iter();
                let mut pick = |v: &[f64]| if v.len() == n { reals.next().unwrap() } else { v.to_vec() };
                let (x, y, shape, size, stroke) = (pick(x), pick(y), pick(shape), pick(size), pick(stroke));
                PointLayer { x, y, x_range: xr[k], y_range: yr[k], shape, size, stroke, col, fill, pt, stroke_scale, res }
            })
            .collect(),
    )
}

/// The 1-based rows of each panel in a rect, path or text layer's
/// `rows` (NULL for a panel without rows), as 0-based indices.
fn panel_rows(l: &List, n_panels: usize) -> Option<Vec<Option<Vec<usize>>>> {
    let rows = list_of(l, "rows")?;
    if rows.len() != n_panels {
        return None;
    }
    rows.iter()
        .map(|(_, r)| {
            if r.is_null() {
                return Some(None);
            }
            r.as_integer_slice()?.iter().map(|&i| (i >= 1).then(|| i as usize - 1)).collect::<Option<Vec<_>>>().map(Some)
        })
        .collect()
}

/// The named fields of `l`, borrowed (a million rows are not copied).
fn fields(l: &List, names: &[&str]) -> Option<Vec<Robj>> {
    names.iter().map(|n| field(l, n)).collect()
}

/// A layer's position ranges for each of `n_panels` panels: one pair for
/// all of them, or a pair per panel (free scales).
fn ranges(l: &List, name: &str, n_panels: usize) -> Option<Vec<[f64; 2]>> {
    let v = nums(l, name)?;
    match v.len() {
        2 => Some(vec![[v[0], v[1]]; n_panels.max(1)]),
        n if n == 2 * n_panels => Some(v.chunks(2).map(|p| [p[0], p[1]]).collect()),
        _ => None,
    }
}

fn join_of(code: f64, codes: [Join; 3]) -> Option<Join> {
    codes.get(code as usize).copied()
}

/// A rect layer dealt out to the panels: see `full_rects()` in
/// R/render-full.R.
fn rect_layers(l: &List, n_panels: usize) -> Option<Vec<Option<Layer>>> {
    let robjs = fields(l, &["xmin", "xmax", "ymin", "ymax", "lwd"])?;
    let cols: Vec<&[f64]> = robjs.iter().map(|r| r.as_real_slice()).collect::<Option<_>>()?;
    let (fill_r, col_r) = (field(l, "fill")?, field(l, "colour")?);
    let (fill, col) = (fill_r.as_integer_slice()?, col_r.as_integer_slice()?);
    let n = cols[0].len();
    if cols.iter().any(|c| c.len() != n) || fill.len() != n || col.len() != n {
        return None;
    }
    let (xr, yr) = (ranges(l, "x_range", n_panels)?, ranges(l, "y_range", n_panels)?);
    let join = join_of(num(l, "join")?, [Join::Miter, Join::Round, Join::Bevel])?;
    let res = num(l, "res")?;
    panel_rows(l, n_panels)?
        .into_iter()
        .enumerate()
        .map(|(k, rows)| {
            let Some(rows) = rows else { return Some(None) };
            let (x_range, y_range) = (xr[k], yr[k]);
            if rows.iter().any(|&i| i >= n) {
                return None;
            }
            let pick = |v: &[f64]| rows.iter().map(|&i| v[i]).collect::<Vec<_>>();
            let pick_c = |v: &[i32]| rows.iter().map(|&i| (v[i] as u32).to_le_bytes()).collect::<Vec<_>>();
            Some(Some(Layer::Rects(RectLayer {
                xmin: pick(cols[0]), xmax: pick(cols[1]), ymin: pick(cols[2]), ymax: pick(cols[3]),
                x_range, y_range, fill: pick_c(fill), col: pick_c(col), lwd: pick(cols[4]), join, res,
            })))
        })
        .collect()
}

/// A path layer dealt out to the panels: see `full_paths()` in
/// R/render-full.R. `rows` are in drawing order; `path_rows` gives each
/// one's path (0-based).
fn path_layers(l: &List, n_panels: usize) -> Option<Vec<Option<Layer>>> {
    let robjs = fields(l, &["x", "y", "lwd", "lty", "colour"])?;
    let (x, y) = (robjs[0].as_real_slice()?, robjs[1].as_real_slice()?);
    let (lwd, lty) = (robjs[2].as_real_slice()?, robjs[3].as_real_slice()?);
    let colour = robjs[4].as_integer_slice()?;
    let np = colour.len();
    if y.len() != x.len() || lwd.len() != np || lty.len() != np || lty.iter().any(|&t| !(t >= 0.0 && t <= u32::MAX as f64 && t.fract() == 0.0)) {
        return None;
    }
    let (xr, yr) = (ranges(l, "x_range", n_panels)?, ranges(l, "y_range", n_panels)?);
    let cap = [Cap::Round, Cap::Butt, Cap::Square].get(num(l, "cap")? as usize).copied()?;
    let join = join_of(num(l, "join")?, [Join::Round, Join::Miter, Join::Bevel])?;
    let (mitre, res) = (num(l, "mitre")?, num(l, "res")?);
    let path_rows = list_of(l, "path_rows")?;
    let rows = panel_rows(l, n_panels)?;
    // Ribbons: `closed` paths are polygons filled with `fill` (both per path).
    let fill: Vec<Option<[u8; 4]>> = match (field(l, "closed"), field(l, "fill")) {
        (Some(closed), Some(fill)) => {
            let (closed, fill) = (closed.as_integer_slice()?, fill.as_integer_slice()?);
            if closed.len() != np || fill.len() != np {
                return None;
            }
            closed.iter().zip(fill).map(|(&c, &f)| (c == 1).then(|| (f as u32).to_le_bytes())).collect()
        }
        _ => Vec::new(),
    };
    // Labels' boxes: per-row offsets in device pixels.
    let (dx_r, dy_r) = (field(l, "dx"), field(l, "dy"));
    let (dx, dy): (&[f64], &[f64]) = match (&dx_r, &dy_r) {
        (Some(a), Some(b)) => (a.as_real_slice()?, b.as_real_slice()?),
        _ => (&[], &[]),
    };
    if !dx.is_empty() && (dx.len() != x.len() || dy.len() != x.len()) {
        return None;
    }
    rows.into_iter()
        .zip(path_rows.iter())
        .enumerate()
        .map(|(k, (rows, (_, paths)))| {
            let Some(rows) = rows else { return Some(None) };
            let (x_range, y_range) = (xr[k], yr[k]);
            let paths = paths.as_integer_slice()?;
            if paths.len() != rows.len() || rows.iter().any(|&i| i >= x.len()) || paths.iter().any(|&p| p < 0 || p as usize >= np) {
                return None;
            }
            Some(Some(Layer::Paths(PathLayer {
                x: rows.iter().map(|&i| x[i]).collect(),
                y: rows.iter().map(|&i| y[i]).collect(),
                path: paths.to_vec(),
                x_range, y_range,
                col: colour.iter().map(|&c| (c as u32).to_le_bytes()).collect(),
                lwd: lwd.to_vec(),
                lty: lty.iter().map(|&t| t as u32).collect(),
                fill: fill.clone(),
                dx: if dx.is_empty() { Vec::new() } else { rows.iter().map(|&i| dx[i]).collect() },
                dy: if dy.is_empty() { Vec::new() } else { rows.iter().map(|&i| dy[i]).collect() },
                cap, join, mitre, res,
            })))
        })
        .collect()
}

/// A text layer dealt out to the panels: see `full_text()` in
/// R/render-full.R. Fonts are interned into the page's.
fn text_layers(l: &List, n_panels: usize, fonts: &mut Fonts) -> Option<Vec<Option<Layer>>> {
    let label_r = field(l, "label")?;
    let label = label_r.as_str_vector()?;
    let robjs = fields(l, &["x", "y", "hjust", "vjust", "rot", "size", "line"])?;
    let cols: Vec<&[f64]> = robjs.iter().map(|r| r.as_real_slice()).collect::<Option<_>>()?;
    let (font_r, colour_r) = (field(l, "font")?, field(l, "colour")?);
    let (font, colour) = (font_r.as_integer_slice()?, colour_r.as_integer_slice()?);
    let paths_r = field(l, "font_path")?;
    let paths = paths_r.as_str_vector()?;
    let indices_r = field(l, "font_index")?;
    let indices = indices_r.as_integer_slice()?;
    let n = label.len();
    if cols.iter().any(|c| c.len() != n) || font.len() != n || colour.len() != n || paths.len() != indices.len() {
        return None;
    }
    let ids: Vec<usize> = paths.iter().zip(indices).map(|(p, &i)| fonts.index(p.to_string(), i as u32)).collect();
    // Labels' text: per-row offsets in device pixels.
    let (dx_r, dy_r) = (field(l, "dx"), field(l, "dy"));
    let (dx, dy): (&[f64], &[f64]) = match (&dx_r, &dy_r) {
        (Some(a), Some(b)) => (a.as_real_slice()?, b.as_real_slice()?),
        _ => (&[], &[]),
    };
    if !dx.is_empty() && (dx.len() != n || dy.len() != n) {
        return None;
    }
    panel_rows(l, n_panels)?
        .into_iter()
        .map(|rows| {
            let Some(rows) = rows else { return Some(None) };
            let mut labels = Vec::with_capacity(rows.len());
            for i in rows {
                if i >= n || font[i] < 1 || font[i] as usize > ids.len() {
                    return None;
                }
                labels.push(Label {
                    x: cols[0][i], y: cols[1][i], hjust: cols[2][i], vjust: cols[3][i], rot: cols[4][i],
                    dx: dx.get(i).copied().unwrap_or(0.0), dy: dy.get(i).copied().unwrap_or(0.0),
                    text: label[i].to_string(),
                    style: TextStyle { font: ids[font[i] as usize - 1], size: cols[5][i], line: cols[6][i], colour: (colour[i] as u32).to_le_bytes() },
                });
            }
            Some(Some(Layer::Text(TextLayer { labels })))
        })
        .collect()
}

/// A label layer dealt out to the panels: see `full_labels()` in
/// R/render-labels.R. `boxes` is a path layer and `text` a text layer,
/// path `i` of a panel being the box of its label `i`.
fn label_layers(l: &List, n_panels: usize, fonts: &mut Fonts) -> Option<Vec<Option<Layer>>> {
    let boxes = path_layers(&List::try_from(field(l, "boxes")?).ok()?, n_panels)?;
    let text = text_layers(&List::try_from(field(l, "text")?).ok()?, n_panels, fonts)?;
    boxes
        .into_iter()
        .zip(text)
        .map(|(b, t)| match (b, t) {
            (Some(Layer::Paths(boxes)), Some(Layer::Text(text))) => Some(Some(Layer::Labels(LabelLayer { boxes, text }))),
            (None, None) => Some(None),
            _ => None,
        })
        .collect()
}

/// One layer of the spec dealt out to the panels: `None` for a panel with
/// nothing to draw.
fn layers(l: &List, n_panels: usize, fonts: &mut Fonts) -> Option<Vec<Option<Layer>>> {
    match field(l, "kind")?.as_str()? {
        "points" => Some(
            point_layers(l, n_panels)?.into_iter().map(|p| (!p.x.is_empty()).then_some(Layer::Points(p))).collect(),
        ),
        "rects" => rect_layers(l, n_panels),
        "paths" => path_layers(l, n_panels),
        "text" => text_layers(l, n_panels, fonts),
        "labels" => label_layers(l, n_panels, fonts),
        _ => None,
    }
}

fn panel(l: &List, layers: Vec<Layer>) -> Option<Panel> {
    let mut grid = Vec::new();
    for (_, g) in list_of(l, "grid")?.iter() {
        let g = List::try_from(g).ok()?;
        grid.push(GridLines { pos: nums(&g, "pos")?, horizontal: flag(&g, "horizontal")?, style: line_style(&list_of(&g, "style")?)? });
    }
    Some(Panel { clip: flag(l, "clip")?, ontop: flag(l, "ontop")?, background: opt(l, "background", rect_el)?, grid, layers, border: opt(l, "border", rect_el)? })
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

/// A key glyph: see `legend_glyph()` in R/render-legend.R.
fn glyph(l: &List, fonts: &mut Fonts) -> Option<Glyph> {
    match field(l, "type")?.as_str()? {
        "point" => Some(Glyph::Point(point_layer(l)?)),
        "rect" => {
            let fill = colours(l, "fill")?;
            let col = colours(l, "col")?;
            let el = RectEl {
                fill: *fill.first()?,
                col: *col.first()?,
                lwd: num(l, "lwd")?,
                lty: num(l, "lty")? as u32,
                join: [Join::Miter, Join::Round, Join::Bevel].get(num(l, "join")? as usize).copied()?,
            };
            let cap = [Cap::Round, Cap::Butt, Cap::Square].get(num(l, "cap")? as usize).copied()?;
            let frac = match field(l, "frac") {
                Some(_) => Some(pair(l, "frac")?),
                None => None,
            };
            Some(Glyph::Rect { inset: num(l, "inset")?, el, cap, frac })
        }
        "path" => {
            let (x, y) = (nums(l, "x")?, nums(l, "y")?);
            (x.len() == y.len() && x.len() >= 2).then_some(())?;
            Some(Glyph::Line { x, y, style: line_style(l)? })
        }
        "text" => Some(Glyph::Text(title(l, fonts)?)),
        "label" => match label_layers(l, 1, fonts)?.pop()? {
            Some(Layer::Labels(layer)) => Some(Glyph::Label(layer)),
            _ => None,
        },
        _ => None,
    }
}

/// Each key's glyphs (`marks`, NULL for a key without any).
fn glyph_lists(l: &List, fonts: &mut Fonts) -> Option<Vec<Vec<Glyph>>> {
    let mut marks = Vec::new();
    for (_, m) in list_of(l, "marks")?.iter() {
        let mut glyphs = Vec::new();
        if !m.is_null() {
            for (_, g) in List::try_from(m).ok()?.iter() {
                glyphs.push(glyph(&List::try_from(g).ok()?, fonts)?);
            }
        }
        marks.push(glyphs);
    }
    Some(marks)
}

/// A guide: see `legend_guide()` and `legend_bar()` in R/render-legend.R.
fn guide(l: &List, fonts: &mut Fonts) -> Option<Guide> {
    let body = match field(l, "kind")?.as_str()? {
        "legend" => {
            let dim = nums(l, "dim")?;
            let (key_w, key_h) = (nums(l, "key_w")?, nums(l, "key_h")?);
            let marks = glyph_lists(l, fonts)?;
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
                key_just: match field(l, "key_just") {
                    None => None,
                    Some(_) => Some(pair(l, "key_just")?),
                },
                labels,
                spacing: pair(l, "spacing")?,
            })
        }
        "bins" => {
            let marks = glyph_lists(l, fonts)?;
            let (key_w, key_h) = (nums(l, "key_w")?, nums(l, "key_h")?);
            if marks.is_empty() || key_w.len() != marks.len() || key_h.len() != marks.len() {
                return None;
            }
            Body::Bins(Bins {
                horizontal: flag(l, "horizontal")?,
                key_size: pair(l, "key_size")?,
                bg: opt(l, "key_bg", rect_el)?,
                marks,
                key_w,
                key_h,
                key_just: match field(l, "key_just") {
                    None => None,
                    Some(_) => Some(pair(l, "key_just")?),
                },
                axis: opt(l, "axis", line_style)?,
                ticks: opt(l, "ticks", |t| Some((nums(t, "pos")?, num(t, "len")?, line_style(&list_of(t, "style")?)?)))?,
                labels: opt(l, "bar_labels", |t| title(t, fonts))?,
            })
        }
        "bar" => Body::Bar(Bar {
            size: pair(l, "bar_size")?,
            horizontal: flag(l, "horizontal")?,
            image: colours(l, "image")?,
            rects: opt(l, "rects", |r| {
                let (lo, hi) = (nums(r, "lo")?, nums(r, "hi")?);
                (lo.len() == hi.len()).then(|| lo.into_iter().zip(hi).collect())
            })?,
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

/// A position's legend box: see `legend_box()` in R/render-legend.R. A
/// box background without a fill of its own takes `bg`, the device's
/// starting fill.
pub(crate) fn legend_group(l: &List, fonts: &mut Fonts, bg: [u8; 4]) -> Option<LegendGroup> {
    let mut guides = Vec::new();
    for (_, g) in list_of(l, "guides")?.iter() {
        guides.push(guide(&List::try_from(g).ok()?, fonts)?);
    }
    let background = opt(l, "background", |b| {
        let mut el = rect_el(b)?;
        if flag(b, "fill_bg")? {
            el.fill = bg;
        }
        Some(el)
    })?;
    Some(LegendGroup {
        horizontal: flag(l, "horizontal")?,
        spacing: num(l, "spacing")?,
        box_just: pair(l, "box_just")?,
        global_just: pair(l, "global_just")?,
        inside: match field(l, "inside") {
            None => None,
            Some(_) => Some(pair(l, "inside")?),
        },
        margin: nums(l, "margin")?.try_into().ok()?,
        background,
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
    let (list, w, h) = page_list(spec, threads)?;
    let (out, ptr) = crate::render::native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&list, w, h, &opts, pixels);
    Some(out)
}

/// `rs_render_page()` streamed to a PNG file at `path`, as `write_png()`
/// in R/render.R writes a page for background `bg` (RGBA) and `dpi` (0:
/// no pHYs chunk), without the page as a nativeRaster in between. `TRUE`,
/// or NULL (decline) as `rs_render_page()`.
/// @noRd
#[extendr(r_name = "rs_render_page_png")]
fn render_page_png(spec: List, threads: i32, path: &str, bg: &[i32], dpi: f64) -> extendr_api::Result<Robj> {
    let &[r, g, b, a] = bg else {
        return Err(Error::Other("expected an RGBA background".into()));
    };
    let Some((list, w, h)) = page_list(&spec, threads) else { return Ok(Robj::from(())) };
    let byte = |v: i32| v.clamp(0, 255) as u8;
    let png_opts = PngOptions::for_background([byte(r), byte(g), byte(b), byte(a)], (dpi > 0.0).then_some(dpi));
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    let file = std::fs::File::create(path).map_err(|e| Error::Other(e.to_string()))?;
    render_png(&list, w, h, &opts, &png_opts, std::io::BufWriter::new(file)).map_err(|e| Error::Other(e.to_string()))?;
    Ok(Robj::from(true))
}

/// The display list of a page spec, with its width and height.
fn page_list(spec: &List, threads: i32) -> Option<(DisplayList, usize, usize)> {
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
    // table_add_tag() (ggplot2 R/plot-build.R): `shift` multiplies the
    // tag grob's width and height (see layout_tag() in R/render-layout.R).
    let tag = opt(&layout, "tag", |t| {
        let mut tag = title(&list_of(t, "item")?, &mut fonts)?;
        let shift = nums(t, "shift")?;
        tag.shift = (*shift.first()? * tag.grob.width(), *shift.get(1)? * tag.grob.height());
        Some(tag)
    })?;
    if let Some(tag) = tag {
        titles.push(("tag".to_string(), tag));
    }
    let bg = rgba(spec, "bg")?;
    let mut legends = Vec::new();
    for (cell, name) in [
        ("legend_right", "guide-box-right"), ("legend_left", "guide-box-left"),
        ("legend_bottom", "guide-box-bottom"), ("legend_top", "guide-box-top"),
    ] {
        if let Some(l) = field(&layout, cell).and_then(|r| List::try_from(r).ok()) {
            legends.push((name.to_string(), legend_group(&l, &mut fonts, bg)?));
        }
    }
    // Inside legends, one box per position, drawn in the panel area.
    if let Some(inside) = field(&layout, "legend_inside") {
        for (_, l) in List::try_from(inside).ok()?.iter() {
            legends.push(("guide-box-inside".to_string(), legend_group(&List::try_from(l).ok()?, &mut fonts, bg)?));
        }
    }
    let mut axes = Vec::new();
    for (cell, name) in [("axis_t", "axis-t"), ("axis_b", "axis-b"), ("axis_l", "axis-l"), ("axis_r", "axis-r")] {
        if let Some(a) = opt(&layout, cell, |l| axis(l, &mut fonts))? {
            axes.push((name.to_string(), a));
        }
    }
    let facet_spec = crate::layout::facet(&layout)?;
    let mut panels = Vec::new();
    let n_panels = list_of(spec, "panels")?.len();
    let mut layers: Vec<std::vec::IntoIter<Option<Layer>>> = Vec::new();
    for (_, l) in list_of(spec, "layers")?.iter() {
        layers.push(self::layers(&List::try_from(l).ok()?, n_panels, &mut fonts)?.into_iter());
    }
    for (i, (_, pl)) in list_of(spec, "panels")?.iter().enumerate() {
        let name = match &facet_spec {
            Some(f) => {
                let (r, c) = *f.panels.get(i)?;
                format!("panel-{}-{}", c + 1, r + 1)
            }
            None => "panel".to_string(),
        };
        // With one panel the layer's `panel` is absent: its single element.
        let drawn = layers.iter_mut().filter_map(|it| it.next()).flatten().collect();
        panels.push((name, panel(&List::try_from(pl).ok()?, drawn)?));
    }
    let mut facet = None;
    if facet_spec.is_some() {
        let f = list_of(&layout, "facet")?;
        let mut axes = Vec::new();
        for (_, a) in list_of(&f, "axes")?.iter() {
            axes.push(axis(&List::try_from(a).ok()?, &mut fonts)?);
        }
        let mut strips = Vec::new();
        for (_, s) in list_of(&f, "strips")?.iter() {
            let s = List::try_from(s).ok()?;
            let (_, size) = crate::layout::strip_titles(&s)?;
            let mut texts = Vec::new();
            for (_, strip) in list_of(&s, "strips")?.iter() {
                let mut one = Vec::new();
                for (_, t) in List::try_from(strip).ok()?.iter() {
                    one.push(title(&List::try_from(t).ok()?, &mut fonts)?);
                }
                texts.push(one);
            }
            strips.push(StripDraw {
                horizontal: flag(&s, "horizontal")?,
                size,
                strips: texts,
                bg: opt(&s, "bg", rect_el)?,
                clip: flag(&s, "clip")?,
            });
        }
        facet = Some(FacetDraw { axes, strips });
    }
    let page = PageSpec {
        width: w,
        height: h,
        bg,
        table: build(&layout)?,
        background: opt(spec, "background", rect_el)?,
        panels,
        axes,
        facet,
        titles,
        legends,
        threads: threads.max(0) as usize,
    };
    let data: Vec<std::sync::Arc<Vec<u8>>> = fonts.keys.iter().map(|k| font_data(&k.0)).collect::<Option<_>>()?;
    let faces: Vec<Font> = data.iter().zip(&fonts.keys).map(|(d, k)| Font::new(d, k.1)).collect::<Option<_>>()?;
    Some((draw_page(&page, &faces)?, w, h))
}

/// One panel of the full tier's layer specs (`full_layer_specs()` in
/// R/render-full.R), for the hybrid tier's lazy grobs: the marks of panel
/// `panel` (1-based, of `n_panels`) drawn as `Panel::draw()` draws a page's
/// layers, clipped to the panel at `rect` (left, top, width, height in
/// pixels) on a transparent raster of `dims` (width, height). `NULL`
/// (decline) for a spec it doesn't read and for text, which needs fonts.
/// @noRd
#[extendr(r_name = "rs_render_panel_layers")]
fn render_panel_layers(layers: List, n_panels: i32, panel: i32, rect: &[f64], dims: &[i32], threads: i32) -> Robj {
    panel_layers(&layers, n_panels, panel, rect, dims, threads).unwrap_or_else(|| Robj::from(()))
}

fn panel_layers(specs: &List, n_panels: i32, panel: i32, rect: &[f64], dims: &[i32], threads: i32) -> Option<Robj> {
    let &[left, top, pw, ph] = rect else { return None };
    let &[w, h] = dims else { return None };
    if w < 1 || h < 1 || n_panels < 1 || panel < 1 || panel > n_panels {
        return None;
    }
    let (w, h) = (w as usize, h as usize);
    let mut fonts = Fonts::new();
    let mut drawn = Vec::new();
    for (_, l) in specs.iter() {
        let one = layers(&List::try_from(l).ok()?, n_panels as usize, &mut fonts)?;
        if let Some(layer) = one.into_iter().nth(panel as usize - 1)? {
            drawn.push(layer);
        }
    }
    if !fonts.keys.is_empty() {
        return None;
    }
    let p = Panel { clip: true, ontop: false, background: None, grid: Vec::new(), layers: drawn, border: None };
    let faces: Vec<Font> = Vec::new();
    let mut painter = Painter::new(&faces, w, h);
    painter.threads = threads.max(0) as usize;
    p.draw(&mut painter, &Rect { x0: left, y0: top, x1: left + pw, y1: top + ph })?;
    let (out, ptr) = crate::render::native_raster(w, h);
    let pixels = unsafe { std::slice::from_raw_parts_mut(ptr, w * h) };
    let opts = raster::Options { threads: threads.max(0) as usize, ..Default::default() };
    raster::render_into(&painter.list, w, h, &opts, pixels);
    Some(out)
}

extendr_module! {
    mod page;
    fn render_page;
    fn render_page_png;
    fn render_panel_layers;
}
