#' Build a ggplot with alot
#'
#' A step-for-step re-implementation of [ggplot2::ggplot_build()]. Pipeline
#' components that have an alot kernel run in Rust; all others call the
#' corresponding ggplot2 method, so the result is always a genuine
#' `ggplot_built` object identical to what ggplot2 produces.
#'
#' @param plot A ggplot object.
#' @return A `ggplot_built` object.
#' @export
alot_build <- function(plot) {
  if (inherits(plot, "ggplot_built")) {
    return(plot)
  }
  if (!inherits(plot, "ggplot")) {
    rlang::abort("`plot` must be a ggplot object.")
  }
  env <- gg_try_prop(plot, "plot_env")
  if (!is.null(env)) {
    gg_attach_plot_env(env)
  }
  build_plot(plot)
}

# Mirrors ggplot2:::build_ggplot (ggplot2 4.0.3, R/plot-build.R).
build_plot <- function(plot) {
  plot <- gg_plot_clone(plot)
  if (length(plot@layers) == 0) {
    plot <- plot + ggplot2::geom_blank()
  }

  layers <- plot@layers
  data <- rep(list(NULL), length(layers))

  scales <- plot@scales

  data <- gg_by_layer(function(l, d) l$layer_data(plot@data), layers, data, "computing layer data")
  data <- gg_by_layer(function(l, d) l$setup_layer(d, plot), layers, data, "setting up layer")

  layout <- gg_create_layout(plot@facet, plot@coordinates, plot@layout)
  data <- layout$setup(data, plot@data, plot@plot_env)

  data <- gg_by_layer(function(l, d) l$compute_aesthetics(d, plot), layers, data, "computing aesthetics")
  plot@labels <- gg_setup_plot_labels(plot, layers, data)

  data <- gg_ignore_data(data)
  data <- lapply(data, scales$transform_df)

  scale_x <- function() scales$get_scales("x")
  scale_y <- function() scales$get_scales("y")

  layout_train_position(layout, data, scale_x(), scale_y())
  data <- layout$map_position(data)
  data <- gg_expose_data(data)

  data <- gg_by_layer(function(l, d) layer_compute_statistic(l, d, layout), layers, data, "computing stat")
  data <- gg_by_layer(function(l, d) l$map_statistic(d, plot), layers, data, "mapping stat to aesthetics")

  plot@scales$add_missing(c("x", "y"), plot@plot_env)

  data <- gg_by_layer(function(l, d) l$compute_geom_1(d), layers, data, "setting up geom")
  data <- gg_by_layer(function(l, d) layer_compute_position(l, d, layout), layers, data, "computing position")

  data <- gg_ignore_data(data)
  layout$reset_scales()
  layout_train_position(layout, data, scale_x(), scale_y())
  layout$setup_panel_params()
  data <- layout$map_position(data)

  layout$setup_panel_guides(plot@guides, plot@layers)

  plot@theme <- gg_plot_theme(plot)

  npscales <- scales$non_position_scales()
  if (npscales$n() > 0) {
    npscales$set_palettes(plot@theme)
    lapply(data, npscales$train_df)
    plot@guides <- plot@guides$build(npscales, plot@layers, plot@labels, data, plot@theme)
    data <- lapply(data, npscales$map_df)
  } else {
    plot@guides <- plot@guides$get_custom()
  }
  data <- gg_expose_data(data)

  data <- gg_by_layer(function(l, d) l$compute_geom_2(d, theme = plot@theme), layers, data, "setting up geom aesthetics")
  data <- gg_by_layer(function(l, d) l$finish_statistics(d), layers, data, "finishing layer stat")

  data <- layout$finish_data(data)

  plot@labels$alt <- gg_get_alt_text(plot)

  build <- gg_class_ggplot_built(data = data, layout = layout, plot = plot)
  class(build) <- union(c("ggplot2::ggplot_built", "ggplot_built"), class(build))
  build
}

# Mirrors Layer$compute_statistic, dispatching stat$compute_layer.
layer_compute_statistic <- function(layer, data, layout) {
  if (gg_empty(data)) {
    return(gg_data_frame0())
  }
  ptype <- vctrs::vec_ptype(data)
  stat <- layer$stat
  layer$computed_stat_params <- stat$setup_params(data, layer$stat_params)
  params <- layer$computed_stat_params
  data <- stat$setup_data(data, params)
  data <- dispatch(
    "stat", stat, list(stat = stat, data = data, params = params, layout = layout),
    function() stat$compute_layer(data, params, layout)
  )
  gg_merge_attrs(data, ptype)
}

# Mirrors Layer$compute_position, dispatching position$compute_layer.
layer_compute_position <- function(layer, data, layout) {
  if (gg_empty(data)) {
    return(gg_data_frame0())
  }
  ptype <- vctrs::vec_ptype(data)
  position <- layer$position
  data <- position$use_defaults(data, layer$aes_params)
  params <- position$setup_params(data)
  data <- position$setup_data(data, params)
  data <- dispatch(
    "position", position, list(position = position, data = data, params = params, layout = layout),
    function() position$compute_layer(data, params, layout)
  )
  gg_merge_attrs(data, ptype)
}
