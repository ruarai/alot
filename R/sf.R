# Mirrors the build steps that sf layers and coord_sf() add: LayerSf's
# setup_layer, compute_geom_1 and compute_geom_2 (ggplot2 R/layer-sf.R),
# StatSf's compute_layer and compute_panel (R/stat-sf.R), and CoordSf's
# setup_params, setup_data, record_bbox and setup_panel_params
# (R/coord-sf.R). Each runs as a kernel through dispatch(), so
# alot_coverage() reports it, and declines when the object's method is not
# the class's own. sf::st_transform(), sf::sf_project() and
# sf::st_graticule() are called as ggplot2 calls them, except that
# CoordSf$setup_data skips st_transform() for a geometry column it would
# return unchanged (sfc_transform_is_noop()).

same_method <- function(obj, class, name) {
  identical(environment(obj[[name]])$f, environment(class[[name]])$f)
}

# Mirrors LayerSf$setup_layer.
kernel_layer_sf_setup_layer <- function(layer, data, plot) {
  if (!same_method(layer, gg("LayerSf"), "setup_layer")) {
    return(NULL)
  }
  # process generic layer setup first
  data <- ggplot2::ggproto_parent(gg("Layer"), layer)$setup_layer(data, plot)

  # automatically determine the name of the geometry column
  # and add the mapping if it doesn't exist
  if (is.null(layer$computed_mapping$geometry) && gg_is_sf(data)) {
    geometry_col <- attr(data, "sf_column")
    layer$computed_mapping$geometry <- rlang::sym(geometry_col)
  }
  data
}

# Mirrors LayerSf$compute_geom_1.
kernel_layer_sf_compute_geom_1 <- function(layer, data) {
  if (!same_method(layer, gg("LayerSf"), "compute_geom_1")) {
    return(NULL)
  }
  data <- ggplot2::ggproto_parent(gg("Layer"), layer)$compute_geom_1(data)

  # Determine the legend type
  legend_type <- layer$legend_key_type
  if (is.null(legend_type)) {
    legend_type <- switch(
      detect_sf_type(data$geometry),
      point = "point", line = "line", "other"
    )
  }

  # Add legend type after computed_geom_params has been calculated
  layer$computed_geom_params$legend <- legend_type
  data
}

# Mirrors LayerSf$compute_geom_2, called as build_ggplot calls it.
kernel_layer_sf_compute_geom_2 <- function(layer, data, theme) {
  if (!same_method(layer, gg("LayerSf"), "compute_geom_2")) {
    return(NULL)
  }
  if (gg_empty(data)) return(data)
  data$geometry <- data$geometry %||% layer$computed_geom_params$legend
  ggplot2::ggproto_parent(gg("Layer"), layer)$compute_geom_2(data, layer$aes_params, theme = theme)
}

# Mirrors detect_sf_type (ggplot2 R/layer-sf.R).
detect_sf_type <- function(sf) {
  if (is.null(sf)) {
    return("other")
  }
  geometry_type <- gg_unique0(as.character(sf::st_geometry_type(sf)))
  if (length(geometry_type) != 1)  geometry_type <- "GEOMETRY"
  gg("sf_types")[geometry_type]
}

# Mirrors StatSf$compute_layer and, through it, Stat$compute_layer
# (ggplot2 R/stat-.R), calling the StatSf$compute_panel mirror per panel.
kernel_stat_sf <- function(stat, data, params, layout) {
  if (!same_method(stat, ggplot2::StatSf, "compute_layer") ||
      !same_method(stat, ggplot2::StatSf, "compute_panel")) {
    return(NULL)
  }
  # add coord to the params, so it can be forwarded to compute_group()
  params$coord <- layout$coord

  gg_check_required_aesthetics(
    stat$required_aes,
    c(names(data), names(params)),
    gg_snake_class(stat)
  )
  required_aes <- intersect(
    names(data),
    unlist(strsplit(stat$required_aes, "|", fixed = TRUE))
  )
  data <- ggplot2::remove_missing(data, params$na.rm,
    c(required_aes, stat$non_missing_aes),
    gg_snake_class(stat),
    finite = TRUE
  )

  # Trim off extra parameters
  params <- params[intersect(names(params), stat$parameters())]

  gg_dapply(data, "PANEL", function(data) {
    scales <- layout$get_scales(data$PANEL[1])
    rlang::try_fetch(
      rlang::inject(stat_sf_compute_panel(data = data, scales = scales, !!!params)),
      error = function(cnd) {
        cli::cli_warn("Computation failed in {.fn {gg_snake_class(stat)}}.", parent = cnd)
        gg_data_frame0()
      }
    )
  })
}

# Mirrors StatSf$compute_panel.
stat_sf_compute_panel <- function(data, scales, coord) {
  geometry_data <- data[[ gg_geom_column(data) ]]
  geometry_crs <- sf::st_crs(geometry_data)

  bbox <- sf::st_bbox(geometry_data)

  if (inherits(coord, "CoordSf")) {
    # if the coord derives from CoordSf, then it
    # needs to know about bounding boxes of geometry data
    coord_record_bbox(
      coord,
      xmin = bbox[["xmin"]], xmax = bbox[["xmax"]],
      ymin = bbox[["ymin"]], ymax = bbox[["ymax"]]
    )

    # to represent the location of the geometry in default coordinates,
    # we take the mid-point along each side of the bounding box and
    # backtransform
    bbox_trans <- ggplot2::sf_transform_xy(
      list(
        x = c(rep(0.5*(bbox[["xmin"]] + bbox[["xmax"]]), 2), bbox[["xmin"]], bbox[["xmax"]]),
        y = c(bbox[["ymin"]], bbox[["ymax"]], rep(0.5*(bbox[["ymin"]] + bbox[["ymax"]]), 2))
      ),
      coord$get_default_crs(),
      geometry_crs
    )

    # record as xmin, xmax, ymin, ymax so regular scales
    # have some indication of where shapes lie
    data$xmin <- min(bbox_trans$x)
    data$xmax <- max(bbox_trans$x)
    data$ymin <- min(bbox_trans$y)
    data$ymax <- max(bbox_trans$y)
  } else {
    # for all other coords, we record the full extent of the
    # geometry object
    data$xmin <- bbox[["xmin"]]
    data$xmax <- bbox[["xmax"]]
    data$ymin <- bbox[["ymin"]]
    data$ymax <- bbox[["ymax"]]
  }

  data
}

coord_record_bbox <- function(coord, xmin, xmax, ymin, ymax) {
  dispatch(
    "coord_record_bbox", coord,
    list(coord = coord, xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    function() coord$record_bbox(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)
  )
}

# Mirrors CoordSf$record_bbox.
kernel_coord_sf_record_bbox <- function(coord, xmin, xmax, ymin, ymax) {
  if (!same_method(coord, ggplot2::CoordSf, "record_bbox")) {
    return(NULL)
  }
  bbox <- coord$params$bbox
  bbox$xmin <- min(bbox$xmin, xmin)
  bbox$xmax <- max(bbox$xmax, xmax)
  bbox$ymin <- min(bbox$ymin, ymin)
  bbox$ymax <- max(bbox$ymax, ymax)
  coord$params$bbox <- bbox
}

# Mirrors CoordSf$setup_params and CoordSf$determine_crs.
kernel_coord_sf_setup_params <- function(coord, data) {
  if (!same_method(coord, ggplot2::CoordSf, "setup_params") ||
      !same_method(coord, ggplot2::CoordSf, "determine_crs")) {
    return(NULL)
  }
  params <- ggplot2::ggproto_parent(ggplot2::Coord, coord)$setup_params(data)

  params$crs <- coord_sf_determine_crs(coord, data)
  params$default_crs <- coord$default_crs
  coord$params <- params

  params
}

coord_sf_determine_crs <- function(coord, data) {
  if (!is.null(coord$crs)) {
    return(coord$crs)
  }

  for (layer_data in data) {
    if (gg_is_sf(layer_data)) {
      geometry <- sf::st_geometry(layer_data)
    } else
      next

    crs <- sf::st_crs(geometry)
    if (is.na(crs))
      next

    return(crs)
  }

  NULL
}

# Mirrors CoordSf$setup_data: transform all layers to common CRS (if
# provided). A geometry column that sfc_transform_is_noop() shows is
# already in that CRS is kept as it is, which is what st_transform() would
# return (S2.1; SPATIAL.md, Decisions).
kernel_coord_sf_setup_data <- function(coord, data, params) {
  if (!same_method(coord, ggplot2::CoordSf, "setup_data")) {
    return(NULL)
  }
  if (is.null(params$crs))
    return(data)

  target <- sf_noop_target(params$crs)
  transform <- function(x) {
    if (sfc_transform_is_noop(x, target)) x else sf::st_transform(x, crs = params$crs)
  }
  lapply(data, function(layer_data) {
    if (! gg_is_sf(layer_data)) {
      return(layer_data)
    }

    idx <- vapply(layer_data, inherits, what = "sfc", FUN.VALUE = logical(1L))
    layer_data[idx] <- lapply(layer_data[idx], transform)
    layer_data
  })
}

# The crs object that sf::st_transform(x, crs = crs) gives its result, for
# a `crs` whose conversion is certain: a crs, or one finite EPSG code
# (st_crs() and st_transform()'s make_crs() both read it as "EPSG:<code>").
# NULL otherwise, and for NA and geocentric CRSs (st_transform() adds a Z
# dimension to XY input for those).
sf_noop_target <- function(crs) {
  if (!inherits(crs, "crs")) {
    if (!(is.numeric(crs) && length(crs) == 1 && is.finite(crs))) {
      return(NULL)
    }
    crs <- sf::st_crs(crs)
  }
  if (is.na(crs) || !isFALSE(crs$is_geocentric)) {
    return(NULL)
  }
  crs
}

sfg_types <- c("POINT", "MULTIPOINT", "LINESTRING", "MULTILINESTRING", "POLYGON", "MULTIPOLYGON")

# TRUE if sf::st_transform() of the sfc `x` to the crs `target` returns `x`
# unchanged. st_transform.sfc (sf R/transform.R) always projects with
# CPL_transform() and rebuilds the result with st_sfc(), so `x` must be
# what that rebuild gives: already in `target` (identical crs objects),
# plain XY sfgs as CPL_transform() writes them (rs_sfc_plain_xy()), and
# exactly the sfc attributes st_sfc() recomputes (class, classes, bbox,
# n_empty, precision 0). A projection from a CRS to itself leaves finite
# coordinates as they are.
sfc_transform_is_noop <- function(x, target) {
  if (is.null(target) || !identical(attr(x, "crs"), target)) {
    return(FALSE)
  }
  known <- c("class", "precision", "bbox", "crs", "n_empty", "classes")
  if (!all(names(attributes(x)) %in% known) ||
      !identical(attr(x, "precision"), 0) ||
      !identical(attr(x, "n_empty"), 0L)) {
    return(FALSE)
  }
  walk <- rs_sfc_plain_xy(x)
  if (is.null(walk)) {
    return(FALSE)
  }
  types <- sfg_types[walk$types]
  single <- all(walk$types == walk$types[1])
  bbox <- structure(walk$bbox, names = c("xmin", "ymin", "xmax", "ymax"), class = "bbox")
  identical(class(x), c(if (single) paste0("sfc_", types[1]) else "sfc_GEOMETRY", "sfc")) &&
    identical(attr(x, "classes"), if (!single) types) &&
    identical(attr(x, "bbox"), bbox)
}

# Mirrors Layout$setup_panel_params (ggplot2 R/layout.R) with
# CoordSf$setup_panel_params.
kernel_coord_sf_panel_params <- function(layout, coord) {
  if (!same_method(coord, ggplot2::CoordSf, "setup_panel_params")) {
    return(NULL)
  }
  # Fudge for CoordFlip and CoordPolar - in place modification of
  # scales is not elegant, but it is pragmatic
  coord$modify_scales(layout$panel_scales_x, layout$panel_scales_y)

  # We only need to setup panel params once for unique combinations of x/y
  # scales. These will be repeated for duplicated combinations.
  index <- vctrs::vec_unique_loc(layout$layout$COORD)
  order <- vctrs::vec_match(layout$layout$COORD, layout$layout$COORD[index])

  scales_x <- layout$panel_scales_x[layout$layout$SCALE_X[index]]
  scales_y <- layout$panel_scales_y[layout$layout$SCALE_Y[index]]

  panel_params <- Map(
    function(scale_x, scale_y, params) coord_sf_panel_params(coord, scale_x, scale_y, params),
    scales_x, scales_y,
    MoreArgs = list(params = layout$coord_params)
  )[order] # `[order]` does the repeating

  # Let Facet modify `panel_params` for each panel
  layout$panel_params <- layout$facet$setup_panel_params(panel_params, coord)
  TRUE
}

# Mirrors CoordSf$setup_panel_params; `self` is the coord.
coord_sf_panel_params <- function(self, scale_x, scale_y, params = list()) {
  # expansion factors for scale limits
  expansion_x <- gg_default_expansion(scale_x, expand = params$expand[c(4, 2)])
  expansion_y <- gg_default_expansion(scale_y, expand = params$expand[c(3, 1)])

  # get scale limits and coord limits and merge together
  # coord limits take precedence over scale limits
  scale_xlim <- scale_x$get_limits()
  scale_ylim <- scale_y$get_limits()
  coord_xlim <- self$limits$x %||% c(NA_real_, NA_real_)
  coord_ylim <- self$limits$y %||% c(NA_real_, NA_real_)

  scale_xlim <- ifelse(is.na(coord_xlim), scale_xlim, coord_xlim)
  scale_ylim <- ifelse(is.na(coord_ylim), scale_ylim, coord_ylim)

  # now, transform limits to common crs
  # note: return value is not a true bounding box, but a
  # list of x and y values whose max/mins are the bounding
  # box
  scales_bbox <- gg_calc_limits_bbox(
    self$lims_method,
    scale_xlim, scale_ylim,
    params$crs, params$default_crs
  )

  # merge coord bbox into scale limits if scale limits not explicitly set
  if (is.null(self$limits$x) && is.null(self$limits$y) &&
      is.null(scale_x$limits) && is.null(scale_y$limits)) {
    coord_bbox <- self$params$bbox
    scales_xrange <- range(scales_bbox$x, coord_bbox$xmin, coord_bbox$xmax, na.rm = TRUE)
    scales_yrange <- range(scales_bbox$y, coord_bbox$ymin, coord_bbox$ymax, na.rm = TRUE)
  } else if (any(!is.finite(scales_bbox$x) | !is.finite(scales_bbox$y))) {
    if (self$lims_method != "geometry_bbox") {
      cli::cli_warn(c(
              "Projection of {.field x} or {.field y} limits failed in {.fn coord_sf}.",
        "i" = "Consider setting {.code lims_method = {.val geometry_bbox}} or {.code default_crs = NULL}."
      ))
    }
    coord_bbox <- self$params$bbox
    scales_xrange <- c(coord_bbox$xmin, coord_bbox$xmax) %||% c(0, 0)
    scales_yrange <- c(coord_bbox$ymin, coord_bbox$ymax) %||% c(0, 0)
  } else {
    scales_xrange <- range(scales_bbox$x, na.rm = TRUE)
    scales_yrange <- range(scales_bbox$y, na.rm = TRUE)
  }

  # apply coordinate expansion
  x_range <- gg_expand_limits_continuous(scales_xrange, expansion_x)
  y_range <- gg_expand_limits_continuous(scales_yrange, expansion_y)
  bbox <- c(
    x_range[1], y_range[1],
    x_range[2], y_range[2]
  )

  breaks <- gg_sf_breaks(scale_x, scale_y, bbox, params$crs)

  # Generate graticule and rescale to plot coords
  graticule <- sf::st_graticule(
    bbox,
    crs = params$crs,
    lat = breaks$y %|W|% NULL,
    lon = breaks$x %|W|% NULL,
    datum = self$datum,
    ndiscr = self$ndiscr
  )

  if (is.null(breaks$x)) {
    graticule <- vctrs::vec_slice(graticule, graticule$type != "E")
  }
  if (is.null(breaks$y)) {
    graticule <- vctrs::vec_slice(graticule, graticule$type != "N")
  }

  # override graticule labels provided by sf::st_graticule() if necessary
  graticule <- self$fixup_graticule_labels(graticule, scale_x, scale_y, params)

  # Convert graticule to viewscales for axis guides
  viewscales <- Map(
    gg_view_scales_from_graticule,
    scale = list(x = scale_x, y = scale_y, x.sec = scale_x, y.sec = scale_y),
    aesthetic = c("x", "y", "x.sec", "y.sec"),
    label = self$label_axes[c("bottom", "left", "top", "right")],
    MoreArgs = list(
      graticule = graticule,
      bbox = bbox,
      label_graticule = self$label_graticule
    )
  )

  panel_params <- rlang::list2(
    x_range = x_range,
    y_range = y_range,
    crs = params$crs,
    default_crs = params$default_crs,
    !!!viewscales,
    reverse = self$reverse %||% "none"
  )

  # Rescale graticule for panel grid
  panel_params$graticule <- self$transform(graticule, panel_params)
  panel_params
}
