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

# Mirrors ggplot2:::build_ggplot (ggplot2 4.0.3, R/plot-build.R). Each step is
# wrapped in timed() (R/timing.R) for the benchmark suites.
build_plot <- function(plot) {
  plot <- gg_plot_clone(plot)
  if (length(plot@layers) == 0) {
    plot <- plot + ggplot2::geom_blank()
  }

  layers <- plot@layers
  data <- rep(list(NULL), length(layers))

  scales <- plot@scales

  data <- timed("layer_data", gg_by_layer(function(l, d) l$layer_data(plot@data), layers, data, "computing layer data"))
  data <- timed("setup_layer", gg_by_layer(function(l, d) l$setup_layer(d, plot), layers, data, "setting up layer"))

  layout <- timed("create_layout", gg_create_layout(plot@facet, plot@coordinates, plot@layout))
  data <- timed("layout_setup", layout$setup(data, plot@data, plot@plot_env))

  data <- timed("compute_aesthetics", gg_by_layer(function(l, d) l$compute_aesthetics(d, plot), layers, data, "computing aesthetics"))
  plot@labels <- timed("setup_plot_labels", gg_setup_plot_labels(plot, layers, data))

  data <- timed("ignore_data_1", gg_ignore_data(data))
  data <- timed("transform_df", lapply(data, function(d) scales_transform_df(scales, d)))

  scale_x <- function() scales$get_scales("x")
  scale_y <- function() scales$get_scales("y")

  timed("train_position_1", layout_train_position(layout, data, scale_x(), scale_y()))
  data <- timed("map_position_1", layout_map_position(layout, data))
  data <- timed("expose_data_1", gg_expose_data(data))

  data <- timed("compute_statistic", gg_by_layer(function(l, d) layer_compute_statistic(l, d, layout), layers, data, "computing stat"))
  data <- timed("map_statistic", gg_by_layer(function(l, d) l$map_statistic(d, plot), layers, data, "mapping stat to aesthetics"))

  timed("add_missing", plot@scales$add_missing(c("x", "y"), plot@plot_env))

  data <- timed("compute_geom_1", gg_by_layer(function(l, d) l$compute_geom_1(d), layers, data, "setting up geom"))
  data <- timed("compute_position", gg_by_layer(function(l, d) layer_compute_position(l, d, layout), layers, data, "computing position"))

  data <- timed("ignore_data_2", gg_ignore_data(data))
  timed("reset_scales", layout$reset_scales())
  timed("train_position_2", layout_train_position(layout, data, scale_x(), scale_y()))
  timed("setup_panel_params", layout$setup_panel_params())
  data <- timed("map_position_2", layout_map_position(layout, data))

  timed("setup_panel_guides", layout$setup_panel_guides(plot@guides, plot@layers))

  plot@theme <- timed("plot_theme", gg_plot_theme(plot))

  npscales <- scales$non_position_scales()
  if (npscales$n() > 0) {
    timed("set_palettes", npscales$set_palettes(plot@theme))
    timed("npscales_train", lapply(data, npscales$train_df))
    plot@guides <- timed("guides_build", plot@guides$build(npscales, plot@layers, plot@labels, data, plot@theme))
    data <- timed("npscales_map", lapply(data, npscales$map_df))
  } else {
    plot@guides <- timed("guides_build", plot@guides$get_custom())
  }
  data <- timed("expose_data_2", gg_expose_data(data))

  data <- timed("compute_geom_2", gg_by_layer(function(l, d) l$compute_geom_2(d, theme = plot@theme), layers, data, "setting up geom aesthetics"))
  data <- timed("finish_statistics", gg_by_layer(function(l, d) l$finish_statistics(d), layers, data, "finishing layer stat"))

  data <- timed("finish_data", layout$finish_data(data))

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

# Mirrors ScalesList$transform_df (ggplot2 R/scales-.R), dispatching each
# scale's Scale$transform_df. A ScalesList whose transform_df is not its
# own falls back whole.
scales_transform_df <- function(scales, df) {
  class_transform_df <- environment(gg("ScalesList")$transform_df)$f
  if (!identical(environment(scales$transform_df)$f, class_transform_df)) {
    record_trace("transform_df", class(scales)[1], "ggplot2")
    return(scales$transform_df(df))
  }
  if (gg_empty(df)) {
    return(df)
  }

  # If the scale contains to trans or trans is identity, there is no need
  # to transform anything
  idx_skip <- vapply(scales$scales, function(x) {
    transformation <- x$get_transformation()
    gg_has_default_transform(x) &&
      (is.null(transformation) || identical(transformation$transform, identity))
  }, logical(1L))
  scales <- scales$scales[!idx_skip]

  if (length(scales) == 0) {
    return(df)
  }

  transformed <- unlist(lapply(
    scales,
    function(scale) {
      dispatch(
        "scale_transform", scale, list(scale = scale, df = df),
        function() scale$transform_df(df = df)
      )
    }
  ), recursive = FALSE)

  df[names(transformed)] <- transformed
  df
}
