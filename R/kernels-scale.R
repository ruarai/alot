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

# Discrete position training: ScaleDiscretePosition$train (ggplot2
# R/scale-discrete-.R) -> scales::train_discrete() for discrete values,
# scales::train_continuous() into `range_c` otherwise. Rust picks, per
# scale, the few rows that train it exactly as its whole slice would: the
# first row of each distinct value, or the rows of the extreme finite
# values. Each scale's own train() then runs on just those rows, so
# scales:::discrete_range's merging, sort(), `drop`, `na.rm` and the range's
# `factor` flag all stay in R. Like upstream, scales with no rows are still
# trained, on an empty slice.
kernel_train_discrete <- function(x, scale_id, scales) {
  class_train <- environment(ggplot2::ScaleDiscretePosition$train)$f
  plain_scale <- function(s) {
    class(s)[1] == "ScaleDiscretePosition" && class(s$range)[1] == "DiscreteRange" &&
      class(s$range_c)[1] == "ContinuousRange" && identical(environment(s$train)$f, class_train)
  }
  if (!all(vapply(scales, plain_scale, logical(1)))) return(NULL)
  if (!typeof(x) %in% c("double", "integer", "logical", "character")) return(NULL)
  plain_classes <- list("factor", c("ordered", "factor"), "Date", c("POSIXct", "POSIXt"),
    c("mapped_discrete", "numeric"))
  if (is.object(x) && !any(vapply(plain_classes, identical, logical(1), oldClass(x)))) return(NULL)
  if (!is.null(names(x))) return(NULL)

  out <- rs_train_discrete_rows(x, as.integer(scale_id), length(scales))
  if (is.null(out)) return(NULL)
  rows <- out$rows
  offsets <- out$offsets
  for (i in seq_along(scales)) {
    idx <- rows[seq.int(offsets[i] + 1L, length.out = offsets[i + 1L] - offsets[i])]
    scales[[i]]$train(vctrs::vec_slice(x, idx))
  }
  TRUE
}
