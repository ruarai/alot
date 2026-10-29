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
        match_id <- match(layer_data$PANEL, panels$PANEL)
        scales_train(layer_data, x_vars, panels$SCALE_X[match_id], x_scales)
      }
    }

    if (!is.null(y_scales)) {
      y_vars <- intersect(y_scales[[1]]$aesthetics, names(layer_data))
      if (length(y_vars) > 0) {
        if (is.null(match_id)) {
          match_id <- match(layer_data$PANEL, panels$PANEL)
        }
        scales_train(layer_data, y_vars, panels$SCALE_Y[match_id], y_scales)
      }
    }
  }
}

# Mirrors scale_apply(method = "train") (ggplot2 R/layout.R): train each of
# `scales` on the rows of `data` routed to it by `scale_id`.
scales_train <- function(data, vars, scale_id, scales) {
  if (length(vars) == 0 || nrow(data) == 0) return(invisible())
  if (anyNA(scale_id)) {
    rlang::abort("`scale_id` must not contain any NA.")
  }
  for (var in vars) {
    x <- data[[var]]
    dispatch(
      "scale_train", scales[[1]],
      list(x = x, scale_id = scale_id, scales = scales),
      function() {
        index <- split(seq_along(scale_id), factor(scale_id, levels = seq_along(scales)))
        for (i in seq_along(scales)) {
          scales[[i]]$train(vctrs::vec_slice(x, index[[i]]))
        }
      }
    )
  }
  invisible()
}
