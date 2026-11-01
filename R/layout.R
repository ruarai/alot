# Mirrors Layout$setup (ggplot2 R/layout.R), dispatching
# facet$compute_layout and, per layer, facet$map_data. A layout whose setup
# is not Layout's own falls back to it whole.
layout_setup <- function(layout, data, plot_data, plot_env) {
  class_setup <- environment(ggplot2::Layout$setup)$f
  if (!identical(environment(layout$setup)$f, class_setup)) {
    record_trace("layout_setup", class(layout)[1], "ggplot2")
    return(layout$setup(data, plot_data, plot_env))
  }
  data <- c(list(plot_data), data)

  # Setup facets
  facet <- layout$facet
  layout$facet_params <- facet$setup_params(data, facet$params)
  layout$facet_params$plot_env <- plot_env
  data <- facet$setup_data(data, layout$facet_params)

  # Setup coords
  layout$coord_params <- coord_setup_params(layout$coord, data)
  data <- coord_setup_data(layout$coord, data, layout$coord_params)

  # Generate panel layout
  params <- layout$facet_params
  layout$layout <- dispatch(
    "facet_compute_layout", facet, list(facet = facet, data = data, params = params),
    function() facet$compute_layout(data, params)
  )
  layout$layout <- layout$coord$setup_layout(layout$layout, layout$coord_params)
  gg_check_layout(layout$layout)

  # Add panel coordinates to the data for each layer
  panels <- layout$layout
  lapply(data[-1], function(layer_data) {
    dispatch(
      "facet_map_data", facet,
      list(facet = facet, data = layer_data, layout = panels, params = params),
      function() facet$map_data(layer_data, layout = panels, params = params)
    )
  })
}

# Coord$setup_params and Coord$setup_data. Only CoordSf's are mirrored
# (R/sf.R).
coord_setup_params <- function(coord, data) {
  if (!inherits(coord, "CoordSf")) {
    return(coord$setup_params(data))
  }
  dispatch(
    "coord_setup_params", coord, list(coord = coord, data = data),
    function() coord$setup_params(data)
  )
}

coord_setup_data <- function(coord, data, params) {
  if (!inherits(coord, "CoordSf")) {
    return(coord$setup_data(data, params))
  }
  dispatch(
    "coord_setup_data", coord, list(coord = coord, data = data, params = params),
    function() coord$setup_data(data, params)
  )
}

# Mirrors Layout$train_position (ggplot2 R/layout.R).
layout_train_position <- function(layout, data, x_scale, y_scale) {
  panels <- layout$layout
  if (is.null(layout$panel_scales_x)) {
    layout$panel_scales_x <- layout$facet$init_scales(panels, x_scale = x_scale,
      params = layout$facet_params)$x
  }
  if (is.null(layout$panel_scales_y)) {
    layout$panel_scales_y <- layout$facet$init_scales(panels, y_scale = y_scale,
      params = layout$facet_params)$y
  }

  facet <- layout$facet
  if (class(facet)[1] %in% c("FacetNull", "FacetWrap", "FacetGrid")) {
    facet_train_scales(layout$panel_scales_x, layout$panel_scales_y, panels, data)
  } else {
    record_trace("facet_train", class(facet)[1], "ggplot2")
    facet$train_scales(layout$panel_scales_x, layout$panel_scales_y, panels,
      data, layout$facet_params)
  }
}

# Mirrors Facet$train_scales (ggplot2 R/facet-.R), which the built-in facets
# inherit unchanged.
facet_train_scales <- function(x_scales, y_scales, panels, data) {
  for (layer_data in data) {
    match_id <- NULL

    if (!is.null(x_scales)) {
      x_vars <- intersect(x_scales[[1]]$aesthetics, names(layer_data))
      if (length(x_vars) > 0) {
        match_id <- match_panel(layer_data$PANEL, panels$PANEL)
        scales_train(layer_data, x_vars, panels$SCALE_X[match_id], x_scales)
      }
    }

    if (!is.null(y_scales)) {
      y_vars <- intersect(y_scales[[1]]$aesthetics, names(layer_data))
      if (length(y_vars) > 0) {
        if (is.null(match_id)) {
          match_id <- match_panel(layer_data$PANEL, panels$PANEL)
        }
        scales_train(layer_data, y_vars, panels$SCALE_Y[match_id], y_scales)
      }
    }
  }
}

# Mirrors scale_apply(method = "train") (ggplot2 R/layout.R): train each of
# `scales` on the rows of `data` routed to it by `scale_id`. The fallback
# splits rows with split_with_index() as upstream does, once per call, so
# kernels-off timings (inst/bench/step-profile.R) match ggplot2's.
scales_train <- function(data, vars, scale_id, scales) {
  if (length(vars) == 0 || nrow(data) == 0) return(invisible())
  if (anyNA(scale_id)) {
    rlang::abort("`scale_id` must not contain any NA.")
  }
  scale_index <- NULL
  for (var in vars) {
    x <- data[[var]]
    dispatch(
      "scale_train", scales[[1]],
      list(x = x, scale_id = scale_id, scales = scales),
      function() {
        if (is.null(scale_index)) {
          scale_index <<- gg_split_with_index(seq_along(scale_id), scale_id, length(scales))
        }
        for (i in seq_along(scales)) {
          scales[[i]]$train(vctrs::vec_slice(x, scale_index[[i]]))
        }
      }
    )
  }
  invisible()
}

# Mirrors Layout$map_position (ggplot2 R/layout.R). A layout whose
# map_position is not Layout's own falls back to it whole.
layout_map_position <- function(layout, data) {
  class_map <- environment(ggplot2::Layout$map_position)$f
  if (!identical(environment(layout$map_position)$f, class_map)) {
    record_trace("map_position", class(layout)[1], "ggplot2")
    return(layout$map_position(data))
  }
  panels <- layout$layout

  lapply(data, function(layer_data) {
    match_id <- NULL

    x_vars <- intersect(layout$panel_scales_x[[1]]$aesthetics, names(layer_data))
    if (length(x_vars) > 0) {
      match_id <- match_panel(layer_data$PANEL, panels$PANEL)
      names(x_vars) <- x_vars
      SCALE_X <- panels$SCALE_X[match_id]
      new_x <- scales_map(layer_data, x_vars, SCALE_X, layout$panel_scales_x)
      layer_data[, x_vars] <- new_x
    }

    y_vars <- intersect(layout$panel_scales_y[[1]]$aesthetics, names(layer_data))
    if (length(y_vars) > 0) {
      if (is.null(match_id)) {
        match_id <- match_panel(layer_data$PANEL, panels$PANEL)
      }
      names(y_vars) <- y_vars
      SCALE_Y <- panels$SCALE_Y[match_id]
      new_y <- scales_map(layer_data, y_vars, SCALE_Y, layout$panel_scales_y)
      layer_data[, y_vars] <- new_y
    }

    layer_data
  })
}

# Mirrors scale_apply(method = "map") (ggplot2 R/layout.R): map each of
# `vars` through the scale its rows are routed to by `scale_id`, returning
# one vector per var in row order. As in scales_train(), the fallback splits
# rows once per call, and only if a var needs it.
scales_map <- function(data, vars, scale_id, scales) {
  if (length(vars) == 0) return()
  if (nrow(data) == 0) return()
  if (anyNA(scale_id)) {
    rlang::abort("`scale_id` must not contain any NA.")
  }
  scale_index <- NULL
  lapply(vars, function(var) {
    x <- data[[var]]
    dispatch(
      "scale_map", scales[[1]],
      list(x = x, scale_id = scale_id, scales = scales),
      function() {
        if (is.null(scale_index)) {
          scale_index <<- gg_split_with_index(seq_along(scale_id), scale_id, length(scales))
        }
        pieces <- lapply(seq_along(scales), function(i) {
          scales[[i]]$map(vctrs::vec_slice(x, scale_index[[i]]))
        })
        # Remove empty vectors to avoid coercion issues with vctrs
        pieces[lengths(pieces) == 0] <- NULL
        o <- order(unlist(scale_index))[seq_len(sum(lengths(pieces)))]
        vctrs::vec_c(!!!pieces)[o]
      }
    )
  })
}

# match(x, table) for the PANEL columns of Layout$train_position and
# map_position (ggplot2 R/layout.R). match() on a factor converts all of its
# 1e6 values to strings, so for a factor the levels are matched instead and
# indexed by the codes. NA codes stay NA, as long as `table` holds no NA.
match_panel <- function(x, table) {
  if (!is.factor(x) || anyNA(table)) {
    return(match(x, table))
  }
  match(levels(x), as.character(table))[as.integer(x)]
}
