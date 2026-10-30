# Continuous non-position scales: Scale$train_df and Scale$map_df (ggplot2
# R/scale-.R) for ScaleContinuous, training through ScaleContinuous$train
# and mapping through ScaleContinuous$map with a scales::pal_gradient_n()
# colour palette (gradient, gradient2, gradientn, distiller, viridis_c and
# the default continuous colour scale). Discrete non-position scales
# (ScaleDiscrete: hue, brewer, grey, viridis_d, manual, shape, linetype, ...)
# train through ScaleDiscrete$train and map through ScaleDiscrete$map.

# The function a (possibly nested) ggproto method wraps. Scale$map_df
# assigns `self$palette` back, so a palette can be wrapped twice.
unwrap_method <- function(f) {
  while (inherits(f, "ggproto_method")) f <- environment(f)$f
  f
}

# Whether closure `f` has the same formals and body as `ref` and is defined
# in the same package namespace.
same_closure <- function(f, ref) {
  is.function(f) && !is.primitive(f) &&
    identical(formals(f), formals(ref)) && identical(body(f), body(ref)) &&
    identical(topenv(environment(f)), topenv(environment(ref)))
}

# The knots of a linear stats::approxfun() as rs_map_colour() takes them:
# list(x, y, yleft, yright), or NULL for any other function.
approx_knots <- function(f) {
  if (!same_closure(f, stats::approxfun(1:2, 1:2))) return(NULL)
  env <- environment(f)
  if (!identical(env$method, 1L) || !isTRUE(env$na.rm)) return(NULL)
  ends <- list(env$yleft, env$yright)
  plain_end <- function(v) length(v) == 1 && typeof(v) %in% c("logical", "integer", "double")
  if (!all(vapply(ends, plain_end, logical(1)))) return(NULL)
  if (!is.double(env$x) || !is.double(env$y) || length(env$x) != length(env$y) || length(env$x) < 2) {
    return(NULL)
  }
  list(x = env$x, y = env$y, yleft = as.double(env$yleft), yright = as.double(env$yright))
}

# The interpolators of a pal_gradient_n() palette (scales R/pal-gradient.R)
# and its colour_ramp() (scales R/colour-ramp.R), as rs_map_colour()'s
# `ramp`: list(values, l, a, b, alpha). NULL for any other palette, a
# one-colour ramp, a non-NA `na.color`, or `values` that would warn or
# error in approxfun().
gradient_ramp <- function(palette) {
  fun <- unwrap_method(palette)
  if (!same_closure(fun, scales::pal_gradient_n(c("black", "white")))) return(NULL)
  ramp <- environment(fun)$ramp
  if (!same_closure(ramp, scales::colour_ramp(c("black", "white")))) return(NULL)
  env <- environment(ramp)
  if (!identical(env$na.color, NA)) return(NULL)

  lab <- lapply(list(l = env$l_interp, a = env$u_interp, b = env$v_interp), approx_knots)
  if (any(vapply(lab, is.null, logical(1)))) return(NULL)
  alpha <- env$alpha_interp
  if (!identical(formals(alpha), formals(function(x) NULL)) || !is.null(body(alpha))) {
    alpha <- approx_knots(alpha)
    if (is.null(alpha)) return(NULL)
  } else {
    alpha <- NULL
  }

  # pal_gradient_n() builds this approxfun on every call.
  values <- environment(fun)$values
  if (!is.null(values)) {
    if (!typeof(values) %in% c("integer", "double") || is.object(values) || length(values) < 2 ||
        anyNA(values) || anyDuplicated(values)) return(NULL)
    xs <- seq(0, 1, length.out = length(values))
    values <- approx_knots(stats::approxfun(values, xs))
    if (is.null(values)) return(NULL)
  }
  c(list(values = values), lab, list(alpha = alpha))
}

# The scale's rescaler as rs_map_colour()'s `rescale` code and parameters:
# scales::rescale(), or the rescale_mid() closure of ggplot2's
# mid_rescaler() (R/scale-gradient.R). NULL for any other rescaler.
rescaler_code <- function(scale, limits) {
  fn <- unwrap_method(scale$rescaler)
  if (identical(fn, scales::rescale)) {
    par <- double()
    code <- 0L
  } else if (same_closure(fn, gg("mid_rescaler")(0))) {
    mid <- environment(fn)$trans_mid
    if (!typeof(mid) %in% c("integer", "double") || length(mid) != 1 || !is.finite(mid) ||
        !is.null(attributes(mid))) return(NULL)
    # rescale_mid.numeric (scales R/bounds.R).
    par <- as.double(c(mid, 2 * max(abs(limits - mid))))
    code <- 1L
  } else {
    return(NULL)
  }
  if (scales::zero_range(limits)) code <- 2L
  list(code = code, par = par)
}

# Continuous training: Scale$train_df -> ScaleContinuous$train ->
# ContinuousRange$train -> scales::train_continuous(), per aesthetic.
kernel_np_train_continuous <- function(scale, df) {
  if (!identical(environment(scale$train_df)$f, environment(ggplot2::Scale$train_df)$f) ||
      !identical(environment(scale$train)$f, environment(ggplot2::ScaleContinuous$train)$f) ||
      class(scale$range)[1] != "ContinuousRange") return(NULL)
  if (gg_empty(df)) return(NULL)
  aesthetics <- intersect(scale$aesthetics, names(df))
  plain <- function(x) typeof(x) %in% c("double", "integer") && !is.object(x)
  if (!all(vapply(df[aesthetics], plain, logical(1)))) return(NULL)

  for (aesthetic in aesthetics) {
    x <- df[[aesthetic]]
    # ScaleContinuous$train skips empty input.
    if (length(x) == 0) next
    scale$range$range <- rs_train_continuous(x, scale$range$range %||% c(NaN, NaN))
  }
  TRUE
}

# Continuous colour mapping: Scale$map_df -> ScaleContinuous$map: `oob`
# against get_limits(), the rescaler, the palette on the result and
# `na.value` for NA. R recognises the palette and pulls out its knots
# (O(colours)); Rust does the rest per row. The palette and limits are
# resolved once, as upstream's per-aesthetic calls would resolve them alike.
kernel_np_map_continuous <- function(scale, df) {
  if (!identical(environment(scale$map_df)$f, environment(ggplot2::Scale$map_df)$f) ||
      !identical(environment(scale$map)$f, environment(ggplot2::ScaleContinuous$map)$f) ||
      !identical(environment(scale$rescale)$f, environment(ggplot2::ScaleContinuous$rescale)$f)) {
    return(NULL)
  }
  if (gg_empty(df)) return(NULL)
  aesthetics <- intersect(scale$aesthetics, names(df))
  names(aesthetics) <- aesthetics
  if (length(aesthetics) == 0) return(NULL)
  plain <- function(x) typeof(x) %in% c("double", "integer") && is.null(attributes(x))
  if (!all(vapply(df[aesthetics], plain, logical(1)))) return(NULL)

  palette <- scale$palette %||% gg_fetch_ggproto(scale, "fallback_palette")
  ramp <- gradient_ramp(palette)
  if (is.null(ramp)) return(NULL)
  oob_fn <- environment(scale$oob)$f
  oob <- Find(function(k) identical(k$fn, oob_fn), oob_kernels())
  if (is.null(oob)) return(NULL)
  # vec_assign() casts na.value to character.
  na_value <- scale$na.value
  if (identical(na_value, NA)) {
    na_value <- NA_character_
  } else if (!is.character(na_value) || length(na_value) != 1 || !is.null(attributes(na_value))) {
    return(NULL)
  }
  limits <- scale$get_limits()
  if (!typeof(limits) %in% c("double", "integer") || length(limits) != 2 || anyNA(limits) ||
      is.object(limits)) return(NULL)
  rescale <- rescaler_code(scale, limits)
  if (is.null(rescale)) return(NULL)

  scale$palette <- palette
  lapply(aesthetics, function(j) {
    rs_map_colour(df[[j]], as.double(limits), oob$code, oob$only_finite, rescale$code, rescale$par,
                  ramp, na_value)
  })
}

# A plain discrete column: an unclassed character or logical vector, or a
# factor or ordered factor with no attributes but its levels and class.
plain_discrete <- function(x) {
  attrs <- attributes(x)
  if (is.factor(x)) {
    (identical(oldClass(x), "factor") || identical(oldClass(x), c("ordered", "factor"))) &&
      setequal(names(attrs), c("levels", "class")) && length(attrs) == 2
  } else {
    typeof(x) %in% c("character", "logical") && is.null(attrs)
  }
}

# Discrete training: Scale$train_df -> ScaleDiscrete$train ->
# DiscreteRange$train -> scales::train_discrete(), per aesthetic. As for
# discrete position scales (kernel_train_discrete), Rust picks the first row
# of each distinct value and the scale's own train() runs on just those, so
# `drop`, `na.translate`, sorting and the range's `factor` flag stay in R.
kernel_np_train_discrete <- function(scale, df) {
  if (!identical(environment(scale$train_df)$f, environment(ggplot2::Scale$train_df)$f) ||
      !identical(environment(scale$train)$f, environment(ggplot2::ScaleDiscrete$train)$f) ||
      class(scale$range)[1] != "DiscreteRange") return(NULL)
  if (gg_empty(df)) return(NULL)
  aesthetics <- intersect(scale$aesthetics, names(df))
  cols <- df[aesthetics]
  # Continuous input errors in train_discrete(); ggplot2 raises it.
  if (!all(vapply(cols, plain_discrete, logical(1)))) return(NULL)
  rows <- lapply(cols, rs_discrete_first_rows)
  if (any(vapply(rows, is.null, logical(1)))) return(NULL)

  for (j in seq_along(cols)) {
    # ScaleDiscrete$train skips empty input.
    if (length(cols[[j]]) == 0) next
    scale$train(vctrs::vec_slice(cols[[j]], rows[[j]]))
  }
  TRUE
}

# The distinct values of plain discrete `x` and its rows' keys into them,
# as rs_lookup_discrete() takes them: a factor's levels then NA, keyed by
# the factor itself; FALSE, TRUE, NA for a logical; for a character vector
# its distinct strings in order of appearance, keyed by their codes.
discrete_values <- function(x) {
  if (is.factor(x)) {
    lv <- levels(x)
    values <- structure(c(seq_along(lv), NA_integer_), levels = lv, class = oldClass(x))
    list(keys = x, values = values)
  } else if (is.logical(x)) {
    list(keys = x, values = c(FALSE, TRUE, NA))
  } else {
    f <- rs_factorize_strings(x)
    list(keys = f$codes, values = x[f$rows])
  }
}

# Discrete mapping: Scale$map_df -> ScaleDiscrete$map. map() is
# elementwise in `x` (match(as.character(x), limits) and
# vec_detect_missing(x); the palette and limits depend only on the scale),
# so ggplot2's own map() runs on each column's distinct values (O(levels))
# and Rust spreads the result over the rows. Named manual `values`,
# `na.translate`, `na.value` and the palette cache are thereby upstream's.
# Only atomic results without attributes are handled; a list (patterns) or
# matrix falls back. The fallback's map() calls then see the palette cache
# these calls filled for the same number of limits, so the palette runs and
# its cache warning fires once in total, as upstream.
kernel_np_map_discrete <- function(scale, df) {
  if (!identical(environment(scale$map_df)$f, environment(ggplot2::Scale$map_df)$f) ||
      !identical(environment(scale$map)$f, environment(ggplot2::ScaleDiscrete$map)$f)) {
    return(NULL)
  }
  if (gg_empty(df)) return(NULL)
  aesthetics <- intersect(scale$aesthetics, names(df))
  names(aesthetics) <- aesthetics
  if (length(aesthetics) == 0) return(NULL)
  if (!all(vapply(df[aesthetics], plain_discrete, logical(1)))) return(NULL)

  scale$palette <- scale$palette %||% gg_fetch_ggproto(scale, "fallback_palette")
  out <- lapply(aesthetics, function(j) {
    d <- discrete_values(df[[j]])
    table <- scale$map(d$values)
    if (length(table) != length(d$values)) return(NULL)
    rs_lookup_discrete(d$keys, table)
  })
  if (any(vapply(out, is.null, logical(1)))) return(NULL)
  out
}
