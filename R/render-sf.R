# geom_sf() polygons in the hybrid tier (task S3.2; SPATIAL.md,
# Architecture "sf geometry"). Mirrors Layer$draw_geom, Geom$draw_layer
# (ggplot2 R/layer.R, R/geom-.R) and GeomSf$draw_panel (R/geom-sf.R) for
# layers whose features are all POLYGON or MULTIPOLYGON: one lazy grob per
# panel. At draw time Rust reads the panel's sfc, rescales it as
# CoordSf$transform -> sf_rescale01() does (R/coord-sf.R), and draws what
# sf::st_as_grob() gives (one even-odd path per polygon, filled then
# stroked, in data order; alot-core/src/render/sf.rs) with GeomSf's gpar:
# col = colour, fill = fill_alpha(fill, alpha), lwd = linewidth * .pt,
# lty = linetype, and the layer's lineend, linejoin and linemitre. Lines
# and points (S3.3), and the full tier (S5), are not drawn here.

# "sf" if a geom draws as GeomSf does.
sf_kind <- function(geom) {
  geom <- drawn_geom(geom)
  same <- function(method) identical(environment(geom[[method]])$f, environment(ggplot2::GeomSf[[method]])$f)
  if (inherits(geom, "GeomSf") && same("draw_panel") && same("handle_na")) "sf"
}

# CoordSf's transform() as ggplot2 defines it.
is_coord_sf <- function(coord) {
  identical(class(coord), class(ggplot2::CoordSf)) &&
    identical(environment(coord$transform)$f, environment(ggplot2::CoordSf$transform)$f)
}

# The ranges CoordSf$transform() passes sf_rescale01(): the panel's
# x_range and y_range, reversed as `reverse` says.
sf_ranges <- function(pp) {
  reverse <- pp$reverse %||% "none"
  list(
    x = if (reverse %in% c("x", "xy")) rev(pp$x_range) else pp$x_range,
    y = if (reverse %in% c("y", "xy")) rev(pp$y_range) else pp$y_range
  )
}

# Why the hybrid tier draws a geom_sf() layer with ggplot2, or NULL, given
# its data after GeomSf$handle_na().
sf_decline <- function(layer, data, layout) {
  coord <- layout$coord
  if (!is_coord_sf(coord)) {
    return("coord is not coord_sf()")
  }
  if (!is.null(coord$get_default_crs())) {
    return("coord_sf() has a default_crs")
  }
  if (!identical(coord$clip, "on")) {
    return("clip is not \"on\"")
  }
  if (nrow(data) == 0) {
    return("no rows")
  }
  # A legend-only layer has a character geometry (LayerSf$compute_geom_2).
  if (!inherits(data$geometry, "sfc")) {
    return("geometry is not an sfc")
  }
  # CoordSf$transform() leaves the data untransformed (is_transform_immune()).
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  # One pass over the features: every one a non-empty XY POLYGON or
  # MULTIPOLYGON (codes 5 and 6), as the Rust reader takes them.
  walk <- rs_sfc_plain_xy(data$geometry)
  if (is.null(walk)) {
    return("geometry the sfc reader doesn't read")
  }
  if (!all(walk$types %in% 5:6)) {
    return("features other than polygons")
  }
  cols <- c("colour", "fill", "linewidth", "linetype", "alpha")
  if (!all(cols %in% names(data))) {
    return("missing polygon aesthetics")
  }
  params <- layer$computed_geom_params
  if (!is.null(params$arrow)) {
    return("arrows")
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill)) {
    return("colour or fill is not a colour vector")
  }
  if (!(is.double(data$alpha) || rs_all_na_logical(data$alpha))) {
    return("alpha is not numeric")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth)) {
    return("linewidth is NA or not numeric")
  }
  if (is.null(lty_code(data$linetype))) {
    return("unsupported linetype")
  }
  reason <- line_params_decline(params)
  if (!is.null(reason)) {
    return(reason)
  }
  ok <- vapply(layout$panel_params, function(pp) {
    r <- unlist(sf_ranges(pp))
    is.double(r) && length(r) == 4 && all(is.finite(r)) && r[1] != r[2] && r[3] != r[4]
  }, logical(1))
  if (!all(ok)) {
    return("panel range is not finite")
  }
  NULL
}

# Mirrors Layer$draw_geom and Geom$draw_layer for GeomSf: one lazy grob per
# panel drawing the panel's features in Rust.
draw_sf_layer <- function(data, layout, layer) {
  params <- layer$computed_geom_params
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- layer$geom$handle_na(data, params)
  ok <- is.null(sf_decline(layer, data, layout))
  colour <- if (ok) point_colours(as.character(data$colour), NA)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }
  codes <- lty_code(data$linetype)
  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(as.factor(data$PANEL))
  rows <- split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels)))
  shared <- list(
    geometry = data$geometry, rows = rows, n = nrow(data),
    colour = colour, fill = fill,
    lwd = as.double(ifelse(codes < 0, 0, data$linewidth * ggplot2::.pt)),
    lty = as.double(pmax(codes, 0)),
    style = c(
      match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L,
      match(params$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L
    ),
    mitre = as.double(params$linemitre %||% 10),
    data = data, panel = panel, coord = layout$coord, geom = layer$geom, params = params
  )
  lapply(seq_len(n_panels), function(i) {
    if (length(rows[[i]]) == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob("sf", shared, i, layout$panel_params[[i]], "geom_sf")
  })
}

# Draws a panel of an "sf" grob (drawDetails.alot_hybrid_layer) to a
# nativeRaster, or NULL where Rust declines it.
render_sf_panel <- function(x, rect, dims, res) {
  s <- x$shared
  rows <- s$rows[[x$panel]]
  all <- length(rows) == s$n
  pick <- function(v) if (all) v else v[rows]
  geometry <- if (all) s$geometry else unclass(s$geometry)[rows]
  r <- sf_ranges(x$panel_params)
  rs_render_sf_polygons(
    geometry, as.double(r$x), as.double(r$y), rect, dims,
    pick(s$colour), pick(s$fill), pick(s$lwd), pick(s$lty), s$style, s$mitre,
    res, render_threads()
  )
}
