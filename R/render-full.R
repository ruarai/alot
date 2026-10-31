# The full tier's page for plots of blank layers (PHASE2.md, Architecture;
# TASKS.md R4.2): everything ggplot_gtable() draws around the panel, drawn
# in Rust. page_spec() resolves the theme elements the drawers need once
# per plot into plain lists (colours packed, widths in pixels), on top of
# the layout spec of R/render-layout.R; rs_render_page()
# (alot-core/src/render/page.rs) lays the page out and draws it.
#
# Mirrors Coord$draw_panel(), Coord$render_bg()/render_fg() and
# guide_grid() (ggplot2 R/coord-.R, R/guides-grid.R), GuideAxis
# (R/guide-axis.R) and the plot background of ggplot_gtable()
# (R/plot-build.R). Layers other than geom_blank() are not drawn yet (R5),
# so such plots decline.

# Pixels of a page of `size` (agg_capture()'s arguments): ragg's get_dims()
# (ragg R/aaa.R).
page_px <- function(size) {
  per <- switch(size$units %||% "px", `in` = size$res, cm = size$res / 2.54, mm = size$res / 25.4, px = 1)
  as.integer(c(size$width, size$height) * per)
}

# A resolved element_line as the Rust drawers take it: packed colour, width
# in pixels (grid's lwd is linewidth * .pt; ragg's pixels are lwd * res /
# 96), R's line type code, and line end and join codes. NULL where the
# line draws nothing.
full_line <- function(el, res) {
  if (layout_blank(el)) {
    return(NULL)
  }
  if (!is.null(el$arrow) && !isFALSE(el$arrow)) {
    layout_decline("arrows")
  }
  lty <- lty_code(el$linetype %||% 1)
  colour <- point_colours(as.character(el$colour %||% NA), NA)
  if (is.null(lty) || is.null(colour) || length(lty) != 1 || length(colour) != 1) {
    layout_decline("a line type or colour alot doesn't draw")
  }
  cap <- as.numeric(match(el$lineend %||% "butt", c("round", "butt", "square")) - 1L)
  join <- as.numeric(match(el$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L)
  if (anyNA(c(cap, join))) {
    layout_decline("an unsupported line end or join")
  }
  if (lty < 0) {
    return(NULL)
  }
  list(col = colour, lwd = el$linewidth * ggplot2::.pt * res / 96, lty = lty, cap = cap, join = join)
}

# A resolved element_rect as rectGrob() draws it: fill, outline colour and
# width in pixels (0 for blank line types), and the join (0 mitre, 1 round,
# 2 bevel). `fill = NA` overrides the fill. NULL for a blank element.
full_rect <- function(el, res, fill = el$fill %||% NA) {
  if (layout_blank(el)) {
    return(NULL)
  }
  solid <- rect_linetype(el$linetype %||% 1)
  fill <- point_colours(as.character(fill), NA)
  colour <- point_colours(as.character(el$colour %||% NA), NA)
  join <- as.numeric(match(el$linejoin %||% "round", c("mitre", "round", "bevel")) - 1L)
  if (is.null(solid) || is.null(fill) || is.null(colour) || length(fill) != 1 || length(colour) != 1 || is.na(join)) {
    layout_decline("a rect alot doesn't draw")
  }
  list(fill = fill, col = colour, lwd = (el$linewidth %||% 0) * ggplot2::.pt * solid * res / 96, join = join)
}

# Coord$render_bg(), guide_grid() and Coord$render_fg() (ggplot2
# R/coord-.R, R/guides-grid.R) for the panel: the background, the grid
# lines (minor y, minor x, major y, major x) as break positions in npc, and
# the border.
full_panel <- function(built, ir, res) {
  layout <- built@layout
  pp <- layout$panel_params[[1]]
  coord <- layout$coord
  theme <- ir$theme
  x_major <- pp$x$mapped_breaks()
  y_major <- pp$y$mapped_breaks()
  breaks <- list(
    minor.y = setdiff(pp$y$mapped_breaks_minor(), y_major), minor.x = setdiff(pp$x$mapped_breaks_minor(), x_major),
    major.y = y_major, major.x = x_major
  )
  grid <- list()
  for (type in names(breaks)) {
    var <- breaks[[type]]
    style <- full_line(theme[[paste0("panel.grid.", type)]], res)
    if (length(var) < 1 || is.null(style)) next
    horizontal <- endsWith(type, ".y")
    df <- data.frame(var = rep(var, each = 2), alt = rep(c(-Inf, Inf), length(var)))
    names(df) <- if (horizontal) c("y", "x") else c("x", "y")
    df <- coord$transform(df, pp)
    pos <- if (horizontal) df$y else df$x
    grid[[length(grid) + 1L]] <- list(pos = as.numeric(pos[seq(1, length(pos), by = 2)]), horizontal = as.numeric(horizontal), style = style)
  }
  list(
    clip = as.numeric(identical(coord$clip, "on")),
    background = full_rect(theme[["panel.background"]], res), grid = grid,
    border = full_rect(theme[["panel.border"]], res, fill = NA)
  )
}

# Why the full tier can't draw `built`, or NULL: it draws no layers yet,
# and only the cartesian axes and guides above.
full_decline <- function(built, ir) {
  blank <- vapply(built@plot@layers, function(l) {
    ir_is_ggplot2(l$geom, "GeomBlank")
  }, logical(1))
  if (!all(blank)) {
    return("layers other than geom_blank()")
  }
  support <- ir$support
  support <- support[!(support$component == "layer" & support$name == "GeomBlank"), ]
  if (nrow(support) > 0) {
    return(support$reason[1])
  }
  if (!ir$coord$class %in% c("CoordCartesian", "CoordFixed") || !identical(ir$coord$reverse %||% "none", "none")) {
    return("coord not drawn yet")
  }
  caps <- vapply(ir$scales[[1]]$axes, function(a) !identical(a$cap %||% "none", "none"), logical(1))
  if (any(caps)) {
    return("axis cap")
  }
  NULL
}

# The spec of rs_render_page() for `built` on a page of `size`; declines
# with layout_decline().
page_spec <- function(built, ir, size) {
  res <- size$res
  if (!identical(as.numeric(size$scaling %||% 1), 1)) {
    layout_decline("scaling")
  }
  reason <- full_decline(built, ir)
  if (!is.null(reason)) {
    layout_decline(reason)
  }
  layout <- layout_spec(built, ir, res)
  if (inherits(layout, "alot_layout_declined")) {
    layout_decline(attr(layout, "reason"))
  }
  bg <- point_colours(as.character(size$bg %||% "white"), NA)
  if (is.null(bg)) {
    layout_decline("a background colour alot doesn't parse")
  }
  list(
    page = page_px(size), bg = bg, layout = layout,
    background = full_rect(ir$theme[["plot.background"]], res),
    panel = full_panel(built, ir, res)
  )
}

# Draws `built` in the full tier: a nativeRaster, or NULL with the reason
# as a "reason" attribute where the full tier declines the plot.
render_full <- function(built, size) {
  decline <- function(reason) structure(list(), reason = reason)
  spec <- tryCatch(page_spec(built, render_ir(built), size), alot_layout_decline = function(e) e)
  if (inherits(spec, "condition")) {
    return(decline(conditionMessage(spec)))
  }
  out <- rs_render_page(spec, render_threads())
  if (is.null(out)) decline("the page spec is not one the Rust drawer reads") else out
}
