# Continuous non-position scales: Scale$train_df and Scale$map_df (ggplot2
# R/scale-.R) for ScaleContinuous, training through ScaleContinuous$train
# and mapping through ScaleContinuous$map with a scales::pal_gradient_n()
# colour palette (gradient, gradient2, gradientn, distiller, viridis_c and
# the default continuous colour scale).

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
