# geom_sf() layers in the hybrid tier (tasks S3.2, S3.3; SPATIAL.md,
# Architecture "sf geometry"). Mirrors Layer$draw_geom, Geom$draw_layer
# (ggplot2 R/layer.R, R/geom-.R) and GeomSf$draw_panel (R/geom-sf.R) for
# layers of POINT, LINESTRING and POLYGON features and their MULTI
# variants: one lazy grob per panel. At draw time Rust reads the panel's
# sfc, rescales it as CoordSf$transform -> sf_rescale01() does
# (R/coord-sf.R), and draws what sf::st_as_grob() gives, in data order
# (alot-core/src/render/sf.rs): one even-odd path per polygon, filled then
# stroked; one polyline per linestring; one point symbol per point. Each
# feature has GeomSf's gpar (sf_gpar()) and the layer's lineend, linejoin
# and linemitre. The full tier (S5) is not drawn here.

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
sf_decline <- function(layer, data, layout) sf_check(layer, data, layout)$reason

# sf_decline()'s checks. Returns list(reason = <why ggplot2 draws it, or
# NULL>, types = <each feature's code into Kind::ALL: 1-2 points, 3-4
# lines, 5-6 polygons>, shape = <the translated shapes>).
sf_check <- function(layer, data, layout) {
  no <- function(reason) list(reason = reason)
  coord <- layout$coord
  if (!is_coord_sf(coord)) {
    return(no("coord is not coord_sf()"))
  }
  if (!is.null(coord$get_default_crs())) {
    return(no("coord_sf() has a default_crs"))
  }
  if (!identical(coord$clip, "on")) {
    return(no("clip is not \"on\""))
  }
  if (nrow(data) == 0) {
    return(no("no rows"))
  }
  # A legend-only layer has a character geometry (LayerSf$compute_geom_2).
  if (!inherits(data$geometry, "sfc")) {
    return(no("geometry is not an sfc"))
  }
  # CoordSf$transform() leaves the data untransformed (is_transform_immune()).
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return(no("x or y is AsIs"))
  }
  # One pass over the features: every one a non-empty XY POINT, LINESTRING
  # or POLYGON or a MULTI variant, as the Rust reader takes them, with
  # double or integer coordinates (GEOMETRYCOLLECTION declines).
  types <- rs_sfc_render_types(data$geometry)
  if (is.null(types)) {
    return(no("geometry the sfc reader doesn't read"))
  }
  point <- types <= 2
  # The columns GeomSf$draw_panel() reads for each kind of feature (the
  # others it replaces with defaults that are never drawn).
  cols <- c(
    "colour", "alpha",
    if (any(point)) c("shape", "size", "stroke"),
    if (any(!point)) c("linewidth", "linetype"),
    if (any(types >= 5)) "fill"
  )
  if (!all(cols %in% names(data))) {
    return(no("missing aesthetics"))
  }
  params <- layer$computed_geom_params
  if (!is.null(params$arrow)) {
    return(no("arrows"))
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill %||% NA)) {
    return(no("colour or fill is not a colour vector"))
  }
  if (!(is.double(data$alpha) || rs_all_na_logical(data$alpha))) {
    return(no("alpha is not numeric"))
  }
  if (any(!point) && (!is.numeric(data$linewidth) || anyNA(data$linewidth[!point]))) {
    return(no("linewidth is NA or not numeric"))
  }
  codes <- if (is.null(data$linetype)) 0 else lty_code(data$linetype)
  if (is.null(codes)) {
    return(no("unsupported linetype"))
  }
  shape <- NULL
  if (any(point)) {
    # GeomSf$draw_panel() translates shape names for every feature.
    shape <- tryCatch(gg_translate_shape_string(data$shape), error = function(e) NULL)
    if (is.null(shape) || is.character(shape)) {
      return(no("character or unknown pch"))
    }
    if (!rs_point_shapes_supported(shape[point])) {
      return(no("unsupported shape"))
    }
    if (!is.numeric(data$size) || !is.numeric(data$stroke) || anyNA(data$size[point]) || anyNA(data$stroke[point])) {
      return(no("NA in size or stroke"))
    }
    # ragg strokes symbols with the gc's line type; the sprites are solid.
    if (any(rep_len(codes, nrow(data))[point] != 0)) {
      return(no("points with a line type other than solid"))
    }
  }
  reason <- line_params_decline(params)
  if (!is.null(reason)) {
    return(no(reason))
  }
  ok <- vapply(layout$panel_params, function(pp) {
    r <- unlist(sf_ranges(pp))
    is.double(r) && length(r) == 4 && all(is.finite(r)) && r[1] != r[2] && r[3] != r[4]
  }, logical(1))
  if (!all(ok)) {
    return(no("panel range is not finite"))
  }
  list(reason = NULL, types = types, shape = shape, codes = rep_len(codes, nrow(data)))
}

# GeomSf$draw_panel()'s gpar (ggplot2 R/geom-sf.R) per feature, for
# rs_render_sf(), or NULL where a colour isn't parsed: col =
# alpha(colour, alpha) for points and lines and colour for polygons; fill =
# fill_alpha(fill, alpha); for points the stroke, stroke * .stroke / 2, as
# lwd and size * .pt + stroke as fontsize; otherwise lwd = linewidth * .pt
# (0 for a blank line type).
sf_gpar <- function(data, check) {
  n <- nrow(data)
  types <- check$types
  point <- types <= 2
  alpha <- data$alpha
  # A polygon's outline keeps its colour's own alpha (NA alpha).
  col_alpha <- if (is.double(alpha) && any(types >= 5)) replace(alpha, types >= 5, NA) else alpha
  colour <- point_colours(as.character(data$colour), col_alpha)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill %||% rep(NA, n)), alpha)
  if (is.null(fill)) {
    return(NULL)
  }
  codes <- check$codes
  lwd <- rep(0, n)
  size <- rep(0, n)
  shape <- rep(0L, n)
  if (any(!point)) {
    lwd[!point] <- ifelse(codes[!point] < 0, 0, data$linewidth[!point] * ggplot2::.pt)
  }
  if (any(point)) {
    stroke <- data$stroke[point] * ggplot2::.stroke / 2
    lwd[point] <- stroke
    size[point] <- data$size[point] * ggplot2::.pt + stroke
    shape[point] <- as.integer(check$shape[point])
  }
  list(colour = colour, fill = fill, lwd = as.double(lwd), lty = as.double(pmax(codes, 0)), shape = shape, size = as.double(size))
}

# Mirrors Layer$draw_geom and Geom$draw_layer for GeomSf: one lazy grob per
# panel drawing the panel's features in Rust.
draw_sf_layer <- function(data, layout, layer) {
  params <- layer$computed_geom_params
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- layer$geom$handle_na(data, params)
  check <- sf_check(layer, data, layout)
  gp <- if (is.null(check$reason)) sf_gpar(data, check)
  if (is.null(gp)) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }
  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(as.factor(data$PANEL))
  rows <- split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels)))
  shared <- c(gp, list(
    geometry = data$geometry, rows = rows, n = nrow(data),
    style = c(
      match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L,
      match(params$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L
    ),
    mitre = as.double(params$linemitre %||% 10),
    data = data, panel = panel, coord = layout$coord, geom = layer$geom, params = params
  ))
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
  rs_render_sf(
    geometry, as.double(r$x), as.double(r$y), rect, dims,
    pick(s$colour), pick(s$fill), pick(s$lwd), pick(s$lty), pick(s$shape), pick(s$size),
    s$style, s$mitre, res, render_threads()
  )
}
