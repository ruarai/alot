//! Glue for the page layout (`alot_core::render::layout`).

use alot_core::render::layout::{self, AxisSet, FacetSpec, LegendBox, PlotSpec, StripSet, Tag, TagLocation, TitleGrob};
use extendr_api::prelude::*;

/// The element called exactly `name` (`List::dollar()` matches partially, so
/// `title` would find `title_plot`), NULL being absent.
pub(crate) fn field(l: &List, name: &str) -> Option<Robj> {
    let (_, r) = l.iter().find(|(n, _)| *n == name)?;
    if r.is_null() { None } else { Some(r) }
}

pub(crate) fn num(l: &List, name: &str) -> Option<f64> {
    field(l, name)?.as_real_slice()?.first().copied()
}

pub(crate) fn nums(l: &List, name: &str) -> Option<Vec<f64>> {
    Some(field(l, name)?.as_real_slice()?.to_vec())
}

pub(crate) fn flag(l: &List, name: &str) -> Option<bool> {
    Some(num(l, name)? != 0.0)
}

/// A `titleGrob()`: `w`, `h` (each label's width and height in pixels),
/// `descent`, `angle`, `hjust`, `vjust`, `margin` (top, right, bottom,
/// left) and whether the margins count in x and y (`mx`, `my`).
pub(crate) fn title(l: &List) -> Option<TitleGrob> {
    let (w, h) = (nums(l, "w")?, nums(l, "h")?);
    let margin: [f64; 4] = nums(l, "margin")?.try_into().ok()?;
    if w.len() != h.len() {
        return None;
    }
    Some(TitleGrob {
        labels: w.into_iter().zip(h).collect(),
        descent: num(l, "descent")?,
        angle: num(l, "angle")?,
        hjust: num(l, "hjust")?,
        vjust: num(l, "vjust")?,
        margin,
        margin_x: flag(l, "mx")?,
        margin_y: flag(l, "my")?,
    })
}

pub(crate) fn list_of(l: &List, name: &str) -> Option<List> {
    List::try_from(field(l, name)?).ok()
}

/// A title grob in `l$name`, `Some(None)` if absent (a `zeroGrob()`), and
/// `None` if malformed.
fn opt_title(l: &List, name: &str) -> Option<Option<TitleGrob>> {
    match field(l, name) {
        None => Some(None),
        Some(r) => Some(Some(title(&List::try_from(r).ok()?)?)),
    }
}

/// An axis: `major` and `minor` tick lengths (`minor` NULL if not drawn),
/// `vertical`, and the label grobs `items`.
fn axis(spec: &List, name: &str, vertical: bool) -> Option<f64> {
    let Some(a) = field(spec, name) else { return Some(0.0) };
    axis_size(&List::try_from(a).ok()?, vertical)
}

fn axis_size(a: &List, vertical: bool) -> Option<f64> {
    let mut labels = Vec::new();
    for (_, item) in list_of(a, "items")?.iter() {
        labels.push(title(&List::try_from(item).ok()?)?);
    }
    Some(layout::axis_size(num(a, "major")?, num(a, "minor"), &labels, vertical))
}

fn legend(spec: &List, name: &str) -> Option<Option<LegendBox>> {
    match field(spec, name) {
        None => Some(None),
        Some(r) => {
            // The sizes of a box grid laid out, or the box to lay out.
            if let Ok(l) = List::try_from(r.clone()) {
                let group = crate::page::legend_group(&l, &mut crate::page::Fonts::new())?;
                let (width, height) = group.size();
                return Some(Some(LegendBox { width, height }));
            }
            let v = r.as_real_slice()?;
            Some(Some(LegendBox { width: *v.first()?, height: *v.get(1)? }))
        }
    }
}

fn tag(spec: &List) -> Option<Option<Tag>> {
    let Some(r) = field(spec, "tag") else { return Some(None) };
    let t = List::try_from(r).ok()?;
    let g = title(&list_of(&t, "item")?)?;
    Some(Some(Tag {
        width: g.width(),
        height: g.height(),
        top: flag(&t, "top")?,
        left: flag(&t, "left")?,
        right: flag(&t, "right")?,
        bottom: flag(&t, "bottom")?,
        location: match num(&t, "location")? as i32 {
            0 => TagLocation::Margin,
            1 => TagLocation::Plot,
            _ => TagLocation::Panel,
        },
    }))
}

/// The boxes of the cells of a single-panel plot's table on a page of
/// `page` (width, height) pixels, as a list of `name`, `x0`, `y0`, `x1`,
/// `y1`, or NULL if `spec` is malformed. See R/render-layout.R for the
/// spec.
/// @noRd
#[extendr(r_name = "rs_layout")]
fn layout_boxes(spec: List, page: &[f64]) -> Robj {
    let Some(table) = build(&spec) else { return Robj::from(()) };
    let [w, h] = page else { return Robj::from(()) };
    let boxes = table.solve(*w, *h);
    let col = |f: fn(&layout::Box) -> f64| -> Robj { boxes.iter().map(f).collect::<Doubles>().into() };
    List::from_names_and_values(
        ["name", "x0", "y0", "x1", "y1"],
        [
            boxes.iter().map(|b| b.name.as_str()).collect::<Strings>().into(),
            col(|b| b.x0),
            col(|b| b.y0),
            col(|b| b.x1),
            col(|b| b.y1),
        ],
    )
    .unwrap()
    .into()
}

/// The text of each strip of a strip set (`strips`, a list of lists of
/// title grobs), and the size of one strip cell across the strip:
/// `max_height()` (horizontal) or `max_width()` of all of them.
pub(crate) fn strip_titles(set: &List) -> Option<(Vec<Vec<TitleGrob>>, f64)> {
    let horizontal = flag(set, "horizontal")?;
    let mut out = Vec::new();
    let mut size = 0.0f64;
    for (_, strip) in list_of(set, "strips")?.iter() {
        let mut texts = Vec::new();
        for (_, t) in List::try_from(strip).ok()?.iter() {
            let g = title(&List::try_from(t).ok()?)?;
            size = size.max(if horizontal { g.height() } else { g.width() });
            texts.push(g);
        }
        out.push(texts);
    }
    Some((out, size))
}

/// A facet: see `layout_facet()` in R/render-layout.R.
pub(crate) fn facet(spec: &List) -> Option<Option<FacetSpec>> {
    let Some(r) = field(spec, "facet") else { return Some(None) };
    let f = List::try_from(r).ok()?;
    let (nrow, ncol) = (num(&f, "nrow")? as usize, num(&f, "ncol")? as usize);
    let (rows, cols) = (nums(&f, "rows")?, nums(&f, "cols")?);
    if rows.len() != cols.len() || rows.iter().chain(&cols).any(|&v| v < 1.0) {
        return None;
    }
    let panels: Vec<(usize, usize)> = rows.iter().zip(&cols).map(|(r, c)| (*r as usize - 1, *c as usize - 1)).collect();
    if panels.iter().any(|&(r, c)| r >= nrow || c >= ncol) {
        return None;
    }
    let mut axis_sizes = Vec::new();
    for (_, a) in list_of(&f, "axes")?.iter() {
        let a = List::try_from(a).ok()?;
        let vertical = matches!(field(&a, "side")?.as_str()?, "left" | "right");
        axis_sizes.push(axis_size(&a, vertical)?);
    }
    let mut axes: [AxisSet; 4] = Default::default();
    for (k, name) in ["axis_t", "axis_b", "axis_l", "axis_r"].iter().enumerate() {
        let a = list_of(&f, name)?;
        let woven = flag(&a, "woven")?;
        let ids: Vec<usize> = nums(&a, "ids")?.iter().map(|&v| v as usize).collect();
        let n = if woven { nrow * ncol } else if k < 2 { ncol } else { nrow };
        if ids.len() != n || ids.iter().any(|&i| i > axis_sizes.len()) {
            return None;
        }
        axes[k] = AxisSet { woven, ids };
    }
    let mut strips = Vec::new();
    for (_, s) in list_of(&f, "strips")?.iter() {
        let s = List::try_from(s).ok()?;
        let (texts, size) = strip_titles(&s)?;
        strips.push(StripSet {
            side: num(&s, "side")? as usize,
            inside: flag(&s, "inside")?,
            padding: num(&s, "padding")?,
            sizes: texts.iter().map(|t| t.len() as f64 * size).collect(),
        });
    }
    let grid = flag(&f, "grid")?;
    for s in &strips {
        let n = if !grid { panels.len() } else if s.side < 2 { ncol } else { nrow };
        if s.side > 3 || s.sizes.len() != n {
            return None;
        }
    }
    let sp = nums(&f, "spacing")?;
    let (widths, heights) = (nums(&f, "widths")?, nums(&f, "heights")?);
    if widths.len() != ncol || heights.len() != nrow {
        return None;
    }
    Some(Some(FacetSpec {
        grid,
        nrow,
        ncol,
        panels,
        widths,
        heights,
        respect: flag(&f, "respect")?,
        spacing: (*sp.first()?, *sp.get(1)?),
        axes,
        axis_sizes,
        strips,
    }))
}

pub(crate) fn build(spec: &List) -> Option<layout::Table> {
    let s = PlotSpec {
        aspect: num(spec, "aspect").filter(|a| a.is_finite()),
        axis_l: axis(spec, "axis_l", true)?,
        axis_r: axis(spec, "axis_r", true)?,
        axis_t: axis(spec, "axis_t", false)?,
        axis_b: axis(spec, "axis_b", false)?,
        xlab_t: opt_title(spec, "xlab_t")?.map_or(0.0, |t| t.height()),
        xlab_b: opt_title(spec, "xlab_b")?.map_or(0.0, |t| t.height()),
        ylab_l: opt_title(spec, "ylab_l")?.map_or(0.0, |t| t.width()),
        ylab_r: opt_title(spec, "ylab_r")?.map_or(0.0, |t| t.width()),
        legend_right: legend(spec, "legend_right")?,
        legend_left: legend(spec, "legend_left")?,
        legend_bottom: legend(spec, "legend_bottom")?,
        legend_top: legend(spec, "legend_top")?,
        legend_inside: false,
        legend_spacing: num(spec, "legend_spacing")?,
        legend_plot: flag(spec, "legend_plot")?,
        title: opt_title(spec, "title")?.map_or(0.0, |t| t.height()),
        subtitle: opt_title(spec, "subtitle")?.map_or(0.0, |t| t.height()),
        caption: opt_title(spec, "caption")?.map_or(0.0, |t| t.height()),
        title_plot: flag(spec, "title_plot")?,
        caption_plot: flag(spec, "caption_plot")?,
        tag: tag(spec)?,
        margin: nums(spec, "margin")?.try_into().ok()?,
        background: flag(spec, "background")?,
        facet: facet(spec)?,
    };
    Some(layout::plot_table(&s))
}

extendr_module! {
    mod layout;
    fn layout_boxes;
}
