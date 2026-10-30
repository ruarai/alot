# Rendering to PNG (PHASE2.md). alot_png() picks the first tier that
# supports the plot:
#
# - hybrid: ggplot2's gtable and grid drawing on ragg::agg_capture(), except
#   that layers with a Rust drawer become lazy grobs that render their panel
#   to a pixel-aligned raster in Rust. The PNG is encoded in Rust.
# - ggplot2: ggplot_gtable() drawn on ragg::agg_png(), unchanged.
#
# hybrid_gtable() swaps each supported layer's draw_geom (GeomPoint, and
# GeomRect and the geoms inheriting its draw_panel) for one that returns a
# lazy "alot_hybrid_layer" grob per panel. The grob holds the layer's
# columns; at draw time, on a raster (ragg) device, it renders the panel's
# marks at device resolution. On any other device it draws ggplot2's own
# grob.

#' Render a plot to PNG with alot (experimental)
#'
#' Builds `plot` with [alot_build()] (unless it is already built) and draws
#' it with the first rendering tier that supports it (see
#' [alot_render_coverage()]). In the hybrid tier, ggplot2 lays the plot out
#' and layers with a Rust drawer are rasterised in Rust; the PNG is encoded
#' in Rust. Otherwise the plot is drawn by ggplot2 on [ragg::agg_png()].
#' If the hybrid tier hits an internal error, `alot_png()` warns and draws
#' with ggplot2. The arguments follow [ggplot2::ggsave()]'s, and the file
#' has the size, resolution and colour type `ggsave()` gives with ragg.
#'
#' @param plot A ggplot or a built plot.
#' @param filename Output file.
#' @param width,height Plot size in `units`.
#' @param units One of `"in"`, `"cm"`, `"mm"` or `"px"`.
#' @param dpi Resolution: a number, or `"screen"`, `"print"` or `"retina"`.
#' @param bg Background colour. If `NULL`, the plot theme's
#'   `plot.background` fill, as in [ggplot2::ggsave()].
#' @param scaling Scaling factor for line widths and text, as in
#'   [ragg::agg_png()].
#' @param ... Passed to the ragg device ([ragg::agg_capture()] or
#'   [ragg::agg_png()]).
#' @return `filename`, invisibly, with attribute `"tier"` naming the tier
#'   that drew it (`"hybrid"` or `"ggplot2"`).
#' @seealso [alot_ggsave()]
#' @export
alot_png <- function(plot, filename, width = 7, height = 7, units = c("in", "cm", "mm", "px"),
                     dpi = 300, bg = NULL, scaling = 1, ...) {
  built <- if (ggplot2::is_ggplot(plot)) alot_build(plot) else plot
  filename <- path.expand(filename)
  dpi <- gg_parse_dpi(dpi)
  dim <- gg_plot_dim(c(width, height), units = units[1], limitsize = FALSE, dpi = dpi)
  bg <- gg_get_plot_background(built@plot, bg)
  size <- list(width = dim[1], height = dim[2], units = "in", res = dpi, bg = bg, scaling = scaling, ...)
  out <- render_raster(built, size)
  if (is.null(out$raster)) {
    render_ggplot2(built, filename, size)
  } else {
    write_png(out$raster, filename, bg, dpi)
  }
  invisible(structure(filename, tier = out$tier))
}

# Writes a nativeRaster as ragg's agg_png() would for this background and
# resolution: RGBA only if `bg` is not opaque (ragg src/png_dev.cpp), and a
# pHYs chunk from `dpi` unless it is NA.
write_png <- function(raster, filename, bg = "white", dpi = NA) {
  alpha <- grDevices::col2rgb(bg, alpha = TRUE)[4, 1] < 255
  rs_write_png(raster, filename, alpha, if (is.na(dpi)) 0 else as.double(dpi))
}

# Draws a built plot with the first tier that supports it. Returns the
# `tier` and, for alot's tiers, the page as a nativeRaster; for the ggplot2
# tier, `raster` is NULL and the caller draws with ggplot2. An internal
# error in alot's tier warns (class "alot_render_fallback") and drops to
# ggplot2.
render_raster <- function(built, size) {
  tier <- render_coverage(built)$tier
  if (tier == "ggplot2") {
    cli::cli_inform(
      c("i" = "alot can't render any layer of this plot; drawing with ggplot2.",
        "i" = "See {.fn alot_render_coverage} for why."),
      .frequency = "once", .frequency_id = "alot_render_ggplot2"
    )
    return(list(tier = "ggplot2", raster = NULL))
  }
  tryCatch(
    list(tier = tier, raster = render_hybrid(built, size)),
    error = function(e) {
      cli::cli_warn(
        c("alot's {tier} renderer failed; drawing with ggplot2 instead.",
          "x" = conditionMessage(e)),
        class = "alot_render_fallback"
      )
      list(tier = "ggplot2", raster = NULL)
    }
  )
}

#' Report how alot would render a plot
#'
#' @param plot A ggplot or a built plot.
#' @return A list with `tier`, the tier [alot_png()] would use (`"hybrid"` or
#'   `"ggplot2"`), and `layers`, a data frame with one row per layer: its
#'   `geom`, the `engine` that draws it (`"rust"` or `"ggplot2"`) and, for
#'   `"ggplot2"`, the `reason`.
#' @export
alot_render_coverage <- function(plot) {
  built <- if (ggplot2::is_ggplot(plot)) alot_build(plot) else plot
  render_coverage(built)
}

render_coverage <- function(built) {
  layers <- built@plot@layers
  layout <- built@layout
  reason <- vapply(seq_along(layers), function(i) {
    data <- suppressWarnings(hybrid_data(layers[[i]], built@data[[i]]))
    hybrid_decline(layers[[i]], data, layout) %||% NA_character_
  }, character(1))
  geom <- vapply(layers, function(l) class(l$geom)[1], character(1))
  engine <- ifelse(is.na(reason), "rust", "ggplot2")
  list(
    tier = if (any(engine == "rust")) "hybrid" else "ggplot2",
    layers = data.frame(geom = geom, engine = engine, reason = reason)
  )
}

# The gtable is built with the device open, as print.ggplot() does:
# ggplot_gtable() measures text on the current device.
render_hybrid <- function(built, size) {
  old <- grDevices::dev.cur()
  cap <- do.call(ragg::agg_capture, size)
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev, old))
  gtable <- hybrid_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
  cap(native = TRUE)
}

render_ggplot2 <- function(built, filename, size) {
  old <- grDevices::dev.cur()
  do.call(ragg::agg_png, c(list(filename), size))
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev, old))
  gtable <- ggplot2::ggplot_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
}

# Closes `dev` and makes `old` current again, as ggsave() does. Closing a
# device after an error mid-draw warns "Killing locked device"; the error
# itself is reported instead.
close_device <- function(dev, old = 1L) {
  withCallingHandlers(
    grDevices::dev.off(dev),
    warning = function(w) {
      if (grepl("locked device", conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
  if (old > 1 && old %in% grDevices::dev.list()) grDevices::dev.set(old)
}

# Like ggplot2::ggplot_gtable(), but layers with a Rust drawer become grobs
# that draw as a raster rendered in Rust when the device is a ragg device.
hybrid_gtable <- function(data) {
  plot <- data@plot
  plot@layers <- lapply(plot@layers, hybrid_layer)
  data@plot <- plot
  ggplot2::ggplot_gtable(data)
}

hybrid_layer <- function(layer) {
  draw <- switch(hybrid_kind(layer) %||% "",
    points = draw_points_layer,
    rects = draw_rects_layer,
    NULL
  )
  if (is.null(draw)) {
    return(layer)
  }
  ggplot2::ggproto(NULL, layer,
    draw_geom = function(self, data, layout) draw(data, layout, layer)
  )
}

# Which Rust drawer a layer's geom has: GeomPoint's draw_panel, or
# GeomRect's (inherited by GeomTile, GeomBar and GeomCol).
hybrid_kind <- function(layer) {
  geom <- layer$geom
  if (identical(geom, ggplot2::GeomPoint)) {
    return("points")
  }
  rect_geoms <- c("GeomRect", "GeomTile", "GeomBar", "GeomCol")
  same_draw <- identical(environment(geom$draw_panel)$f, environment(ggplot2::GeomRect$draw_panel)$f)
  if (class(geom)[1] %in% rect_geoms && same_draw) {
    return("rects")
  }
  NULL
}

# A layer's data as its geom draws it: Layer$draw_geom() removes missing
# values first (ggplot2 R/layer.R), and GeomPoint$draw_panel() translates
# shape names (R/geom-point.R).
hybrid_data <- function(layer, data) {
  kind <- hybrid_kind(layer)
  if (is.null(kind) || gg_empty(data)) {
    return(data)
  }
  data <- point_handle_na(layer, data)
  if (kind == "points") {
    data$shape <- gg_translate_shape_string(data$shape)
  }
  data
}

# Geom$handle_na(), skipped when nothing is missing: remove_missing()
# (ggplot2 R/utilities.R) then returns the data unchanged, and scanning 1e6
# rows for it costs more than drawing them.
point_handle_na <- function(layer, data) {
  geom <- layer$geom
  vars <- intersect(c(geom$required_aes, geom$non_missing_aes), names(data))
  complete <- all(vapply(data[vars], function(v) is.atomic(v) && !anyNA(v), logical(1)))
  if (complete) data else geom$handle_na(data, layer$computed_geom_params)
}

# Why the hybrid tier draws a layer with ggplot2, or NULL if Rust draws it,
# given the layer's data from hybrid_data(). draw_points_layer() makes the
# same check, so coverage and drawing agree.
hybrid_decline <- function(layer, data, layout) {
  kind <- hybrid_kind(layer)
  if (is.null(kind)) {
    return("no Rust drawer for this geom")
  }
  coord <- layout$coord
  if (!identical(class(coord), class(ggplot2::coord_cartesian())) ||
    !identical(coord$reverse %||% "none", "none")) {
    return("coord is not an unreversed coord_cartesian()")
  }
  if (!identical(coord$clip, "on")) {
    return("clip is not \"on\"")
  }
  if (nrow(data) == 0) {
    return("no rows")
  }
  reason <- switch(kind,
    points = points_decline(data),
    rects = rects_decline(data, layer$computed_geom_params)
  )
  if (!is.null(reason)) {
    return(reason)
  }
  linear <- vapply(layout$panel_params, function(pp) {
    !is.null(linear_range(pp$x)) && !is.null(linear_range(pp$y))
  }, logical(1))
  if (!all(linear)) {
    return("position scale does not rescale linearly")
  }
  NULL
}

is_colour_vector <- function(x) is.character(x) || (is.logical(x) && all(is.na(x)))

points_decline <- function(data) {
  cols <- c("x", "y", "shape", "colour", "fill", "size", "stroke", "alpha")
  if (!all(cols %in% names(data))) {
    return("missing point aesthetics")
  }
  if (!is.double(data$x) || !is.double(data$y) || !is.character(data$colour)) {
    return("x, y or colour has an unsupported type")
  }
  if (!is_colour_vector(data$fill)) {
    return("fill is not a colour vector")
  }
  # Coord$transform() leaves AsIs positions untransformed (transform_position
  # callers in ggplot2 R/coord-.R); the hybrid would rescale them.
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  if (anyNA(data$x) || anyNA(data$y) || anyNA(data$size) || anyNA(data$stroke)) {
    return("NA in x, y, size or stroke")
  }
  if (is.character(data$shape)) {
    return("character pch")
  }
  if (!rs_point_shapes_supported(data$shape)) {
    return("unsupported shape")
  }
  NULL
}

# Line types the rect drawer handles: solid, and blank (no stroke).
rect_linetype <- function(lty) {
  solid <- (is.numeric(lty) & lty %in% 1) | (is.character(lty) & lty %in% c("solid", "1"))
  blank <- is.na(lty) | (is.numeric(lty) & lty %in% 0) | (is.character(lty) & lty %in% c("blank", "0"))
  if (all(solid | blank)) !blank
}

rects_decline <- function(data, params) {
  cols <- c("xmin", "xmax", "ymin", "ymax", "colour", "fill", "linewidth", "linetype", "alpha")
  if (!all(cols %in% names(data))) {
    return("missing rect aesthetics")
  }
  pos <- data[c("xmin", "xmax", "ymin", "ymax")]
  if (!all(vapply(pos, is.double, logical(1)))) {
    return("xmin, xmax, ymin or ymax is not double")
  }
  if (any(vapply(pos, inherits, logical(1), "AsIs"))) {
    return("x or y is AsIs")
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill)) {
    return("colour or fill is not a colour vector")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth)) {
    return("linewidth is NA or not numeric")
  }
  if (is.null(rect_linetype(data$linetype))) {
    return("linetype is not solid or blank")
  }
  if (!(params$linejoin %||% "mitre") %in% c("mitre", "round", "bevel")) {
    return("unsupported linejoin")
  }
  NULL
}

# Mirrors Layer$draw_geom and Geom$draw_layer (ggplot2 R/layer.R, R/geom-.R)
# for GeomPoint, without splitting the data: one lazy grob per panel.
draw_points_layer <- function(data, layout, layer) {
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- point_handle_na(layer, data)
  data$shape <- gg_translate_shape_string(data$shape)
  ok <- is.null(hybrid_decline(layer, data, layout))
  colour <- if (ok) point_colours(data$colour, data$alpha)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    return(layer$geom$draw_layer(data, layer$computed_geom_params, layout, layout$coord))
  }

  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)
  counts <- tabulate(panel, n_panels)
  shared <- list(
    x = data$x, y = data$y, panel = panel,
    rows = split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels))),
    shape = data$shape,
    size = data$size, stroke = data$stroke, colour = colour, fill = fill,
    data = data, coord = layout$coord
  )
  lapply(seq_len(n_panels), function(i) {
    if (counts[i] == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob("points", shared, i, layout$panel_params[[i]], "geom_point")
  })
}

# A lazy grob drawing one panel of a layer in Rust at draw time (see
# drawDetails.alot_hybrid_layer).
hybrid_grob <- function(kind, shared, panel, panel_params, prefix) {
  grid::grob(
    kind = kind, shared = shared, panel = panel, panel_params = panel_params,
    name = grid::grobName(prefix = prefix), cl = "alot_hybrid_layer"
  )
}

# Mirrors Layer$draw_geom, Geom$draw_layer and GeomRect$draw_panel (ggplot2
# R/layer.R, R/geom-.R, R/geom-rect.R) for coord_cartesian: one lazy grob
# per panel drawing the layer's rectGrob in Rust.
draw_rects_layer <- function(data, layout, layer) {
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- point_handle_na(layer, data)
  params <- layer$computed_geom_params
  ok <- is.null(hybrid_decline(layer, data, layout))
  # rectGrob(col = colour, fill = fill_alpha(fill, alpha)): the outline
  # keeps its colour's own alpha.
  colour <- if (ok) point_colours(as.character(data$colour), NA)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }

  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)
  counts <- tabulate(panel, n_panels)
  # gg_par(lwd = linewidth) is linewidth * .pt; blank line types draw no
  # stroke.
  lwd <- data$linewidth * ggplot2::.pt * rect_linetype(data$linetype)
  shared <- list(
    xmin = data$xmin, xmax = data$xmax, ymin = data$ymin, ymax = data$ymax,
    panel = panel, rows = split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels))),
    colour = colour, fill = fill, lwd = as.double(lwd),
    join = match(params$linejoin %||% "mitre", c("mitre", "round", "bevel")) - 1L,
    data = data, coord = layout$coord, geom = layer$geom, params = params
  )
  lapply(seq_len(n_panels), function(i) {
    if (counts[i] == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob("rects", shared, i, layout$panel_params[[i]], "geom_rect")
  })
}

# Packed RGBA for rs_render_points(), as scales::alpha(colour, alpha). Rust
# parses hex; other colour specs (names) go through col2rgb() once per
# distinct value. NA stays NA, which Rust packs as transparent.
point_colours <- function(colour, alpha) {
  out <- rs_point_colours(colour, alpha)
  if (is.null(out)) {
    u <- unique(colour[!is.na(colour)])
    rgba <- grDevices::col2rgb(u, alpha = TRUE)
    hex <- grDevices::rgb(rgba[1, ], rgba[2, ], rgba[3, ], rgba[4, ], maxColorValue = 255)
    out <- rs_point_colours(hex[match(colour, u)], alpha)
  }
  out
}

# Worker threads for Rust rendering (PHASE2.md, User API):
# options(alot.threads), then ALOT_THREADS, else the available cores capped
# at 8 (0, resolved in Rust), or 2 under R CMD check's _R_CHECK_LIMIT_CORES_.
render_threads <- function() {
  n <- getOption("alot.threads", Sys.getenv("ALOT_THREADS"))
  if (is.character(n) && !nzchar(n)) {
    limit <- Sys.getenv("_R_CHECK_LIMIT_CORES_")
    return(if (nzchar(limit) && !identical(toupper(limit), "FALSE")) 2L else 0L)
  }
  n <- suppressWarnings(as.integer(n))
  if (length(n) != 1 || is.na(n) || n < 1) {
    cli::cli_abort("{.code alot.threads} / {.envvar ALOT_THREADS} must be a positive integer.")
  }
  n
}

# Pixels per inch of the current device if it is a ragg raster device.
raster_device_res <- function() {
  if (!startsWith(names(grDevices::dev.cur()), "agg_")) {
    return(NULL)
  }
  grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1]
}

# Range a view scale rescales from, if it rescales positions linearly with
# scales::rescale: ScaleContinuous$rescale with the default rescaler, or
# ScaleDiscretePosition$rescale, whose map() passes mapped (numeric)
# positions through (ggplot2 R/scale-.R, R/scale-discrete-.R).
linear_range <- function(view) {
  range <- view$continuous_range
  scale <- view$scale
  # `$` wraps ggproto fields that are functions; compare the inner one.
  inner <- function(f) environment(f)$f
  continuous <- inherits(scale, "ScaleContinuousPosition") &&
    identical(inner(scale$rescale), inner(ggplot2::ScaleContinuous$rescale)) &&
    identical(inner(scale$rescaler), scales::rescale)
  discrete <- inherits(scale, "ScaleDiscretePosition") &&
    identical(inner(scale$rescale), inner(ggplot2::ScaleDiscretePosition$rescale)) &&
    identical(inner(scale$map), inner(ggplot2::ScaleDiscretePosition$map))
  ok <- (continuous || discrete) &&
    is.numeric(range) && length(range) == 2 && all(is.finite(range)) && range[1] != range[2]
  if (ok) range
}

#' @exportS3Method grid::drawDetails
drawDetails.alot_hybrid_layer <- function(x, recording) {
  res <- raster_device_res()
  tr <- grid::current.transform()
  x_range <- linear_range(x$panel_params$x)
  y_range <- linear_range(x$panel_params$y)
  if (is.null(res) || tr[1, 2] != 0 || tr[2, 1] != 0 || is.null(x_range) || is.null(y_range)) {
    return(grid::grid.draw(hybrid_fallback_grob(x)))
  }

  # Panel corners in device pixels, from the top-left.
  lo <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  hi <- grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
  dev_h <- grDevices::dev.size("in")[2]
  left <- lo$x * res
  right <- hi$x * res
  top <- (dev_h - hi$y) * res
  bottom <- (dev_h - lo$y) * res
  # Render to the pixel-aligned box around the panel so the raster maps 1:1.
  x0 <- floor(left)
  y0 <- floor(top)
  w <- ceiling(right) - x0
  h <- ceiling(bottom) - y0
  rect <- c(left - x0, top - y0, right - left, bottom - top)
  dims <- as.integer(c(w, h))

  s <- x$shared
  rows <- s$rows[[x$panel]]
  img <- switch(x$kind,
    points = rs_render_points(
      s$x, s$y, rows, x_range, y_range, rect, dims,
      s$shape, s$size, s$stroke, s$colour, s$fill,
      c(ggplot2::.pt, ggplot2::.stroke, res),
      render_threads()
    ),
    rects = rs_render_rects(
      s$xmin, s$xmax, s$ymin, s$ymax, rows, x_range, y_range, rect, dims,
      s$colour, s$fill, s$lwd, s$join, res, render_threads()
    )
  )
  if (is.null(img)) {
    return(grid::grid.draw(hybrid_fallback_grob(x)))
  }
  # Rust clipped each mark to the panel, as ragg does; clipping the raster
  # again would cut the edge pixels twice.
  grid::pushViewport(grid::viewport(clip = "off"))
  on.exit(grid::popViewport())
  grid::grid.raster(
    img,
    x = grid::unit(x0 / res - lo$x, "in"),
    y = grid::unit(dev_h - (y0 + h) / res - lo$y, "in"),
    width = grid::unit(w / res, "in"),
    height = grid::unit(h / res, "in"),
    just = c("left", "bottom"),
    interpolate = FALSE
  )
}

# ggplot2's own grob for the panel, for devices and viewports the Rust
# drawers don't handle.
hybrid_fallback_grob <- function(x) {
  s <- x$shared
  data <- vctrs::vec_slice(s$data, s$panel == x$panel)
  switch(x$kind,
    points = ggplot2::GeomPoint$draw_panel(data, x$panel_params, s$coord),
    rects = s$geom$draw_panel(
      data, x$panel_params, s$coord,
      lineend = s$params$lineend %||% "butt", linejoin = s$params$linejoin %||% "mitre"
    )
  )
}
