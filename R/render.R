# Rendering to PNG (PHASE2.md). alot_png() picks the first tier that
# supports the plot:
#
# - hybrid: ggplot2's gtable and grid drawing on ragg::agg_capture(), except
#   that layers with a Rust drawer become lazy grobs that render their panel
#   to a pixel-aligned raster in Rust. The PNG is encoded in Rust.
# - ggplot2: ggplot_gtable() drawn on ragg::agg_png(), unchanged.
#
# hybrid_gtable() swaps each supported layer's draw_geom for one that
# returns a lazy "alot_hybrid_points" grob per panel instead of a
# pointsGrob. The grob holds the layer's columns; at draw time, on a raster
# (ragg) device, it renders the panel's points at device resolution. On any
# other device it draws ggplot2's own pointsGrob.

#' Render a plot to PNG with alot (experimental)
#'
#' Builds `plot` with [alot_build()] (unless it is already built) and draws
#' it with the first rendering tier that supports it (see
#' [alot_render_coverage()]). In the hybrid tier, ggplot2 lays the plot out
#' and layers with a Rust drawer are rasterised in Rust; the PNG is encoded
#' in Rust. Otherwise the plot is drawn by ggplot2 on [ragg::agg_png()].
#' If the hybrid tier hits an internal error, `alot_png()` warns and draws
#' with ggplot2.
#'
#' @param plot A ggplot or a built plot.
#' @param filename Output file.
#' @param width,height,units,res Passed to [ragg::agg_capture()] or
#'   [ragg::agg_png()].
#' @param ... Passed to [ragg::agg_capture()] or [ragg::agg_png()].
#' @return `filename`, invisibly, with attribute `"tier"` naming the tier
#'   that drew it (`"hybrid"` or `"ggplot2"`).
#' @export
alot_png <- function(plot, filename, width = 7, height = 5, units = "in", res = 96, ...) {
  built <- if (ggplot2::is_ggplot(plot)) alot_build(plot) else plot
  filename <- path.expand(filename)
  size <- list(width = width, height = height, units = units, res = res, ...)
  out <- render_raster(built, size)
  if (is.null(out$raster)) {
    render_ggplot2(built, filename, size)
  } else {
    rs_write_png(out$raster, filename)
  }
  invisible(structure(filename, tier = out$tier))
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
    hybrid_decline(layers[[i]], built@data[[i]], layout) %||% NA_character_
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
  cap <- do.call(ragg::agg_capture, size)
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev))
  gtable <- hybrid_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
  cap(native = TRUE)
}

render_ggplot2 <- function(built, filename, size) {
  do.call(ragg::agg_png, c(list(filename), size))
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev))
  gtable <- ggplot2::ggplot_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
}

# Closing a device after an error mid-draw warns "Killing locked device";
# the error itself is reported instead.
close_device <- function(dev) {
  withCallingHandlers(
    grDevices::dev.off(dev),
    warning = function(w) {
      if (grepl("locked device", conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
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
  if (!identical(layer$geom, ggplot2::GeomPoint)) {
    return(layer)
  }
  ggplot2::ggproto(NULL, layer,
    draw_geom = function(self, data, layout) draw_points_layer(data, layout, layer)
  )
}

# Why the hybrid tier draws a layer with ggplot2, or NULL if Rust draws it.
# draw_points_layer() makes the same check, so coverage and drawing agree.
hybrid_decline <- function(layer, data, layout) {
  if (!identical(layer$geom, ggplot2::GeomPoint)) {
    return("no Rust drawer for this geom")
  }
  coord <- layout$coord
  cols <- c("x", "y", "shape", "colour", "size", "stroke", "alpha")
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
  if (!all(cols %in% names(data))) {
    return("missing point aesthetics")
  }
  if (!is.double(data$x) || !is.double(data$y) || !is.character(data$colour)) {
    return("x, y or colour has an unsupported type")
  }
  # Coord$transform() leaves AsIs positions untransformed (transform_position
  # callers in ggplot2 R/coord-.R); the hybrid would rescale them.
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  if (anyNA(data$x) || anyNA(data$y) || anyNA(data$size) || anyNA(data$stroke) || anyNA(data$colour)) {
    return("NA in x, y, size, stroke or colour")
  }
  if (!rs_point_shapes_supported(data$shape)) {
    return("unsupported shape")
  }
  linear <- vapply(layout$panel_params, function(pp) {
    !is.null(linear_range(pp$x)) && !is.null(linear_range(pp$y))
  }, logical(1))
  if (!all(linear)) {
    return("position scale does not rescale linearly")
  }
  NULL
}

# Mirrors Layer$draw_geom and Geom$draw_layer (ggplot2 R/layer.R, R/geom-.R)
# for GeomPoint, without splitting the data: one lazy grob per panel.
draw_points_layer <- function(data, layout, layer) {
  colour <- if (is.null(hybrid_decline(layer, data, layout))) point_colours(data$colour, data$alpha)
  if (is.null(colour)) {
    return(layer$draw_geom(data, layout))
  }

  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)
  counts <- tabulate(panel, n_panels)
  shared <- list(
    x = data$x, y = data$y, panel = panel, shape = data$shape,
    size = data$size, stroke = data$stroke, colour = colour,
    data = data, coord = layout$coord
  )
  lapply(seq_len(n_panels), function(i) {
    if (counts[i] == 0) {
      return(ggplot2::zeroGrob())
    }
    grid::grob(
      shared = shared, panel = i, panel_params = layout$panel_params[[i]],
      name = grid::grobName(prefix = "geom_point"), cl = "alot_hybrid_points"
    )
  })
}

# Packed RGBA for rs_render_points(), as scales::alpha(colour, alpha). Rust
# parses hex; other colour specs (names) go through col2rgb() once per
# distinct value.
point_colours <- function(colour, alpha) {
  out <- rs_point_colours(colour, alpha)
  if (is.null(out)) {
    u <- unique(colour)
    rgba <- grDevices::col2rgb(u, alpha = TRUE)
    hex <- grDevices::rgb(rgba[1, ], rgba[2, ], rgba[3, ], rgba[4, ], maxColorValue = 255)
    out <- rs_point_colours(hex[match(colour, u)], alpha)
  }
  out
}

# Pixels per inch of the current device if it is a ragg raster device.
raster_device_res <- function() {
  if (!startsWith(names(grDevices::dev.cur()), "agg_")) {
    return(NULL)
  }
  grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1]
}

# Range a view scale rescales from, if it rescales linearly with
# scales::rescale (ScaleContinuous$rescale, ggplot2 R/scale-.R).
linear_range <- function(view) {
  range <- view$continuous_range
  ok <- inherits(view$scale, c("ScaleContinuousPosition", "ScaleDiscretePosition")) &&
    # `$` wraps ggproto fields that are functions; compare the inner one.
    identical(environment(view$scale$rescaler)$f, scales::rescale) &&
    is.numeric(range) && length(range) == 2 && all(is.finite(range)) && range[1] != range[2]
  if (ok) range
}

#' @exportS3Method grid::drawDetails
drawDetails.alot_hybrid_points <- function(x, recording) {
  res <- raster_device_res()
  tr <- grid::current.transform()
  x_range <- linear_range(x$panel_params$x)
  y_range <- linear_range(x$panel_params$y)
  if (is.null(res) || tr[1, 2] != 0 || tr[2, 1] != 0 || is.null(x_range) || is.null(y_range)) {
    return(grid::grid.draw(points_fallback_grob(x)))
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

  s <- x$shared
  img <- rs_render_points(
    s$x, s$y, s$panel, x$panel, x_range, y_range,
    c(left - x0, top - y0, right - left, bottom - top), as.integer(c(w, h)),
    s$shape, s$size, s$stroke, s$colour,
    c(ggplot2::.pt, ggplot2::.stroke, res)
  )
  if (is.null(img)) {
    return(grid::grid.draw(points_fallback_grob(x)))
  }
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

points_fallback_grob <- function(x) {
  s <- x$shared
  data <- vctrs::vec_slice(s$data, s$panel == x$panel)
  ggplot2::GeomPoint$draw_panel(data, x$panel_params, s$coord)
}
