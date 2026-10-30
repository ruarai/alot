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

# The oob functions the continuous map kernel handles, keyed by the code
# rs_map_continuous() takes. scales::censor, squish and squish_infinite are
# the same functions as oob_censor, oob_squish and oob_squish_infinite.
oob_kernels <- function() {
  list(
    list(fn = scales::oob_censor, code = 0L, only_finite = TRUE),
    list(fn = scales::oob_censor_any, code = 0L, only_finite = FALSE),
    list(fn = scales::oob_squish, code = 1L, only_finite = TRUE),
    list(fn = scales::oob_squish_any, code = 1L, only_finite = FALSE),
    list(fn = scales::oob_squish_infinite, code = 2L, only_finite = TRUE),
    list(fn = scales::oob_keep, code = 3L, only_finite = TRUE)
  )
}

# Continuous position mapping: ScaleContinuousPosition$map (ggplot2
# R/scale-continuous.R): the scale's `oob` against get_limits(), then every
# NA or NaN becomes `na.value`. get_limits() runs in R once per scale.
kernel_map_continuous <- function(x, scale_id, scales) {
  class_map <- environment(ggplot2::ScaleContinuousPosition$map)$f
  plain_scale <- function(s) {
    class(s)[1] == "ScaleContinuousPosition" && identical(environment(s$map)$f, class_map)
  }
  if (!all(vapply(scales, plain_scale, logical(1)))) return(NULL)
  if (!typeof(x) %in% c("double", "integer") || is.object(x)) return(NULL)

  oob_fn <- environment(scales[[1]]$oob)$f
  na_value <- scales[[1]]$na.value
  for (s in scales[-1]) {
    if (!identical(environment(s$oob)$f, oob_fn) || !identical(s$na.value, na_value)) return(NULL)
  }
  oob <- Find(function(k) identical(k$fn, oob_fn), oob_kernels())
  if (is.null(oob)) return(NULL)
  # vec_assign() casts na.value to double.
  if (!typeof(na_value) %in% c("logical", "integer", "double") || length(na_value) != 1 ||
      !is.null(attributes(na_value))) return(NULL)

  # oob_keep() never forces its range, so neither does upstream's map().
  limits <- if (oob$code == 3L) {
    rep(0, 2 * length(scales))
  } else {
    lims <- lapply(scales, function(s) s$get_limits())
    plain_limits <- function(l) {
      typeof(l) %in% c("double", "integer") && length(l) == 2 && !anyNA(l) && !is.object(l)
    }
    if (!all(vapply(lims, plain_limits, logical(1)))) return(NULL)
    as.double(unlist(lims))
  }
  rs_map_continuous(x, as.integer(scale_id), limits, oob$code, oob$only_finite, as.double(na_value))
}

# Discrete position mapping: ScaleDiscretePosition$map (ggplot2
# R/scale-discrete-.R). For discrete input, R matches the distinct values
# against each scale's limits and indexes its palette (O(distinct) per
# scale), giving a value table that Rust looks every row up in. Continuous
# input is only cast to mapped_discrete, which needs no split, so it stays
# in R. Palette errors (non-numeric or too short) fall back so that
# ggplot2 raises them.
kernel_map_discrete <- function(x, scale_id, scales) {
  class_map <- environment(ggplot2::ScaleDiscretePosition$map)$f
  plain_scale <- function(s) {
    class(s)[1] == "ScaleDiscretePosition" && identical(environment(s$map)$f, class_map)
  }
  if (!all(vapply(scales, plain_scale, logical(1)))) return(NULL)

  attrs <- attributes(x)
  if (typeof(x) %in% c("double", "integer") &&
      (is.null(attrs) || identical(attrs, list(class = c("mapped_discrete", "numeric"))))) {
    return(gg_mapped_discrete(x))
  }

  if (is.factor(x)) {
    if (!identical(oldClass(x), "factor") && !identical(oldClass(x), c("ordered", "factor"))) return(NULL)
    if (!identical(names(attrs), c("levels", "class")) && !identical(names(attrs), c("class", "levels"))) {
      return(NULL)
    }
    keys <- x
    labels <- c(levels(x), NA_character_)
  } else if (typeof(x) %in% c("logical", "character") && is.null(attrs)) {
    if (is.logical(x)) {
      keys <- x
      labels <- c("FALSE", "TRUE", NA_character_)
    } else {
      f <- rs_factorize_strings(x)
      keys <- f$codes
      labels <- x[f$rows]
    }
  } else {
    return(NULL)
  }

  # Logical data trains logical limits; match() compares them as character.
  limits <- lapply(scales, function(s) s$get_limits())
  plain_limits <- function(l) is.character(l) || (is.logical(l) && is.null(attributes(l)))
  if (!all(vapply(limits, plain_limits, logical(1)))) return(NULL)
  table <- matrix(NA_real_, nrow = length(labels), ncol = length(scales))
  for (i in seq_along(scales)) {
    values <- scales[[i]]$palette(length(limits[[i]]))
    if (!typeof(values) %in% c("integer", "double") || !is.null(attributes(values)) ||
        length(values) < length(limits[[i]])) return(NULL)
    table[, i] <- as.double(values[match(labels, limits[[i]])])
  }
  out <- rs_map_discrete(keys, as.integer(scale_id), as.vector(table), length(labels))
  if (is.null(out)) return(NULL)
  class(out) <- c("mapped_discrete", "numeric")
  out
}

# The transforms the transform kernel handles, keyed by the code
# rs_transform() takes. A transformation matches by name and by its
# transform function: the same closure as scales' own (body, formals and,
# for log, `base`), defined in the scales namespace. transform_identity()
# needs no kernel: scales_transform_df() skips it, as upstream does.
transform_kernels <- function() {
  list(
    list(ref = scales::transform_log10(), code = 0L),
    list(ref = scales::transform_sqrt(), code = 1L),
    list(ref = scales::transform_reverse(), code = 2L)
  )
}

transform_code <- function(transformation) {
  if (!inherits(transformation, "transform")) return(NULL)
  fn <- transformation$transform
  for (k in transform_kernels()) {
    ref <- k$ref$transform
    if (!identical(transformation$name, k$ref$name)) next
    if (is.primitive(ref)) {
      if (identical(fn, ref)) return(k$code)
      next
    }
    if (!is.function(fn) || is.primitive(fn)) next
    env <- environment(fn)
    if (!identical(fn, ref, ignore.environment = TRUE) ||
        !identical(topenv(env), asNamespace("scales")) ||
        !identical(env$base, environment(ref)$base)) next
    return(k$code)
  }
  NULL
}

# Replays a transform on the row Rust flagged, so R raises the "NaNs
# produced" warning as default_transform's call to it would. The warning's
# call depends on whether the caller is byte-compiled, as ggplot2 is, so
# this is compiled even under pkgload::load_all(). The caller passes the
# row twice: a scalar would take the bytecode's scalar path, which reports
# `log(x, base)` instead.
replay_transform <- compiler::cmpfun(function(transformation, x) {
  transformation$transform(x)
})

# Continuous scale transformation: Scale$transform_df (ggplot2 R/scale-.R)
# with ggplot2's default_transform: each aesthetic column through the
# transformation, then check_transformation(). Rust transforms the column
# and reports the first row at which R would warn, and R replays each
# warning on that row alone, in upstream's order. Only plain double and
# integer columns are handled. Single-row data falls back: R's scalar path differs from its vector path in NaN bits
# and in the warning's call.
kernel_transform <- function(scale, df) {
  if (nrow(df) < 2) return(NULL)
  if (!identical(environment(scale$transform_df)$f, environment(ggplot2::Scale$transform_df)$f) ||
      !identical(environment(scale$transform)$f, gg("default_transform"))) return(NULL)
  aesthetics <- intersect(scale$aesthetics, names(df))
  cols <- df[aesthetics]
  plain_column <- function(x) typeof(x) %in% c("double", "integer") && is.null(attributes(x))
  if (!all(vapply(cols, plain_column, logical(1)))) return(NULL)
  transformation <- scale$get_transformation()
  code <- transform_code(transformation)
  if (is.null(code)) return(NULL)

  lapply(cols, function(x) {
    out <- rs_transform(x, code)
    if (out$nan > 0L) replay_transform(transformation, x[c(out$nan, out$nan)])
    if (out$finite > 0L) {
      gg_check_transformation(x[out$finite], out$x[out$finite], transformation$name, call = scale$call)
    }
    out$x
  })
}
