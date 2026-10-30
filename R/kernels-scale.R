# Continuous range training: ScaleContinuous$train -> scales::train_continuous().
kernel_train_continuous <- function(x, scale_id, scales) {
  # An instance can override `train` without changing its class, as
  # ViewScale$make_fixed_copy() does (ggplot2 R/scale-view.R).
  class_train <- environment(ggplot2::ScaleContinuousPosition$train)$f
  plain_scale <- function(s) {
    class(s)[1] == "ScaleContinuousPosition" && class(s$range)[1] == "ContinuousRange" &&
      identical(environment(s$train)$f, class_train)
  }
  if (!all(vapply(scales, plain_scale, logical(1)))) return(NULL)
  if (!typeof(x) %in% c("double", "integer") || is.factor(x)) return(NULL)
  if (is.object(x) && !inherits(x, c("Date", "POSIXct", "mapped_discrete"))) return(NULL)

  existing <- unlist(lapply(scales, function(s) s$range$range %||% c(NaN, NaN)))
  out <- rs_train_continuous_grouped(x, as.integer(scale_id), as.double(existing))
  for (i in seq_along(scales)) {
    r <- out[c(2 * i - 1, 2 * i)]
    if (!is.na(r[1])) scales[[i]]$range$range <- r
  }
  TRUE
}
