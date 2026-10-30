# Mirrors ScalesList$train_df and ScalesList$map_df (ggplot2 R/scales-.R) for
# the non-position scales, dispatching each scale's Scale$train_df and
# Scale$map_df through dispatch("np_train", ...) and dispatch("np_map", ...).
# A ScalesList whose train_df or map_df is not its own falls back whole.

uses_class_method <- function(scales, method) {
  class_method <- environment(gg("ScalesList")[[method]])$f
  identical(environment(scales[[method]])$f, class_method)
}

npscales_train_df <- function(scales, df) {
  if (!uses_class_method(scales, "train_df")) {
    record_trace("train_df", class(scales)[1], "ggplot2")
    return(scales$train_df(df))
  }
  if (gg_empty(df) || length(scales$scales) == 0) {
    return()
  }
  lapply(scales$scales, function(scale) {
    dispatch(
      "np_train", scale, list(scale = scale, df = df),
      function() scale$train_df(df = df)
    )
  })
}

npscales_map_df <- function(scales, df) {
  if (!uses_class_method(scales, "map_df")) {
    record_trace("map_df", class(scales)[1], "ggplot2")
    return(scales$map_df(df))
  }
  if (gg_empty(df) || length(scales$scales) == 0) {
    return(df)
  }

  mapped <- unlist(lapply(
    scales$scales,
    function(scale) {
      dispatch(
        "np_map", scale, list(scale = scale, df = df),
        function() scale$map_df(df = df)
      )
    }
  ), recursive = FALSE)

  df[names(mapped)] <- mapped
  df
}
