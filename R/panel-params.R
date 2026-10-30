# Mirrors Layout$setup_panel_params (ggplot2 R/layout.R) for
# CoordCartesian, CoordFlip and CoordFixed, whose setup_panel_params is
# CoordCartesian's (ggplot2 R/coord-cartesian-.R) plus, for CoordFlip, a
# swap of the expansion and of the x/y names (R/coord-flip.R).
#
# ggplot2 builds view scales once per distinct (SCALE_X, SCALE_Y) pair
# (COORD), and builds each primary view scale twice, as view_scale_secondary()
# calls view_scale_primary() again. The view scales of one axis depend on
# that axis only, so the limits, breaks and minor breaks are computed once
# per distinct SCALE_X and SCALE_Y, with every extended_breaks() call
# batched into one Rust call (R/breaks.R). The ViewScale objects are then
# built per COORD as ggplot2 builds them, so no two COORDs share one.

layout_setup_panel_params <- function(layout) {
  class_method <- environment(ggplot2::Layout$setup_panel_params)$f
  if (!identical(environment(layout$setup_panel_params)$f, class_method)) {
    record_trace("setup_panel_params", class(layout)[1], "ggplot2")
    return(layout$setup_panel_params())
  }
  coord <- layout$coord
  invisible(dispatch(
    "setup_panel_params", coord, list(layout = layout, coord = coord),
    function() layout$setup_panel_params()
  ))
}

kernel_panel_params <- function(layout, coord) {
  flip <- class(coord)[1] == "CoordFlip"
  class_method <- if (flip) ggplot2::CoordFlip$setup_panel_params else ggplot2::CoordCartesian$setup_panel_params
  if (!identical(environment(coord$setup_panel_params)$f, environment(class_method)$f)) {
    return(NULL)
  }
  scales_x <- layout$panel_scales_x
  scales_y <- layout$panel_scales_y
  # Secondary axes build their view scale from break_info(); leave them to
  # ggplot2. Decline before modify_scales(), which changes the scales.
  if (any(vapply(c(scales_x, scales_y), has_secondary_axis, logical(1)))) {
    return(NULL)
  }

  # Fudge for CoordFlip and CoordPolar - in place modification of
  # scales is not elegant, but it is pragmatic
  coord$modify_scales(scales_x, scales_y)

  # We only need to setup panel params once for unique combinations of x/y
  # scales. These will be repeated for duplicated combinations.
  panels <- layout$layout
  index <- vctrs::vec_unique_loc(panels$COORD)
  order <- vctrs::vec_match(panels$COORD, panels$COORD[index])
  scale_x <- panels$SCALE_X[index]
  scale_y <- panels$SCALE_Y[index]

  params <- layout$coord_params
  if (flip) {
    params$expand <- params$expand[c(2, 1, 4, 3)]
  }
  x_ids <- unique(scale_x)
  y_ids <- unique(scale_y)
  axes <- view_scale_parts(
    c(scales_x[x_ids], scales_y[y_ids]),
    coord_limits = rep(list(coord$limits$x, coord$limits$y), c(length(x_ids), length(y_ids))),
    expand = rep(list(params$expand[c(4, 2)], params$expand[c(3, 1)]), c(length(x_ids), length(y_ids)))
  )
  x_axes <- axes[seq_along(x_ids)][match(scale_x, x_ids)]
  y_axes <- axes[length(x_ids) + seq_along(y_ids)][match(scale_y, y_ids)]

  reverse <- coord$reverse %||% "none"
  guide <- ggplot2::guide_none()
  panel_params <- Map(function(x, y) {
    panel <- c(view_scales_from_parts(x, guide), view_scales_from_parts(y, guide), reverse = reverse)
    if (flip) gg_flip_axis_labels(panel) else panel
  }, x_axes, y_axes, USE.NAMES = FALSE)[order] # `[order]` does the repeating

  # Let Facet modify `panel_params` for each panel
  layout$panel_params <- layout$facet$setup_panel_params(panel_params, coord)
  TRUE
}

# The test in view_scale_secondary() (ggplot2 R/scale-view.R).
has_secondary_axis <- function(scale) {
  sec <- scale$secondary.axis
  !(is.null(sec) || gg_is_waiver(sec) || sec$empty())
}

# For each scale, the values view_scales_from_scale() and
# view_scale_primary() (ggplot2 R/coord-cartesian-.R, R/scale-view.R)
# compute: limits, continuous range, breaks and minor breaks.
view_scale_parts <- function(scales, coord_limits, expand) {
  parts <- Map(function(scale, coord_limits, expand) {
    expansion <- gg_default_expansion(scale, expand = expand)
    limits <- scale$get_limits()
    continuous_range <- gg_expand_limits_scale(scale, expansion, limits, coord_limits = coord_limits)
    continuous_scale_sorted <- sort(continuous_range)
    breaks <- if (!scale$is_discrete()) {
      continuous_breaks_plan(scale, continuous_scale_sorted)
    } else {
      scale$get_breaks(limits)
    }
    list(
      scale = scale, limits = limits, continuous_range = continuous_range,
      continuous_scale_sorted = continuous_scale_sorted, breaks = breaks
    )
  }, scales, coord_limits, expand)

  # One Rust call for every range that needs labeling::extended().
  pending <- which(vapply(parts, function(p) inherits(p$breaks, "alot_extended_plan"), logical(1)))
  if (length(pending) > 0) {
    plans <- lapply(parts[pending], `[[`, "breaks")
    extended <- extended_breaks_batch(
      vapply(plans, `[[`, double(1), "dmin"),
      vapply(plans, `[[`, double(1), "dmax"),
      vapply(plans, function(p) as.double(p$n), double(1))
    )
    for (i in seq_along(pending)) {
      # Breaks in data space need to be converted back to transformed space
      parts[[pending[i]]]$breaks <- plans[[i]]$transformation$transform(extended[[i]])
    }
  }

  lapply(parts, function(p) {
    scale <- p$scale
    breaks <- p$breaks
    if (!scale$is_discrete()) {
      breaks <- scales::censor(breaks, p$continuous_scale_sorted, only.finite = FALSE)
    }
    minor_breaks <- scale$get_breaks_minor(b = breaks, limits = p$continuous_scale_sorted)
    p$minor_breaks <- scales::censor(minor_breaks, p$continuous_range, only.finite = FALSE)
    p$breaks <- breaks
    p
  })
}

# Mirrors ScaleContinuous$get_breaks (ggplot2 R/scale-.R) up to the call of
# the breaks function. If that is scales::breaks_extended() with no extra
# arguments, returns a plan for the batched call: the range, `n` and the
# transformation to apply after. Otherwise returns the breaks from the
# scale's own get_breaks().
continuous_breaks_plan <- function(scale, limits) {
  sorted_limits <- limits
  if (!identical(environment(scale$get_breaks)$f, environment(ggplot2::ScaleContinuous$get_breaks)$f)) {
    return(scale$get_breaks(limits))
  }
  if (scale$is_empty()) {
    return(numeric())
  }
  transformation <- scale$get_transformation()
  breaks <- scale$breaks %|W|% transformation$breaks
  if (!is_extended_breaks(breaks)) {
    return(scale$get_breaks(limits))
  }

  # Ensure limits don't exceed domain (#980)
  domain <- suppressWarnings(transformation$transform(transformation$domain))
  domain <- sort(domain)
  # To avoid NaN causing issues. NaN are dropped by the sort()
  if (length(domain) == 2 && !scales::zero_range(domain)) {
    limits <- scales::oob_squish(limits, domain)
  }
  if (scales::zero_range(as.numeric(limits))) {
    return(limits[1])
  }

  # Limits in transformed space need to be converted back to data space
  limits <- transformation$inverse(limits)
  # breaks_extended() supports `n`, so n.breaks is used when set.
  n <- scale$n.breaks %||% environment(breaks)$n_default

  # The body of breaks_extended()'s breaks function.
  x <- limits[is.finite(limits)]
  if (length(x) == 0) {
    return(transformation$transform(numeric()))
  }
  rng <- range(x)
  if (!is.double(rng) || length(n) != 1 || !is.numeric(n)) {
    return(scale$get_breaks(sorted_limits))
  }
  structure(
    list(dmin = rng[1], dmax = rng[2], n = n, transformation = transformation),
    class = "alot_extended_plan"
  )
}

# Whether `f` is the breaks function of scales::breaks_extended() with no
# arguments passed on to labeling::extended().
is_extended_breaks <- function(f) {
  if (!is.function(f) || inherits(f, "ggproto_method")) {
    return(FALSE)
  }
  ref <- extended_breaks_ref()
  env <- environment(f)
  identical(body(f), body(ref)) && identical(formals(f), formals(ref)) &&
    is.environment(env) && exists("n_default", envir = env, inherits = FALSE) &&
    exists("...", envir = env, inherits = FALSE) && evalq(...length(), env) == 0L
}

extended_breaks_ref <- local({
  ref <- NULL
  function() ref <<- ref %||% scales::breaks_extended()
})

# The ggproto() call of view_scale_primary() (ggplot2 R/scale-view.R). It
# runs in a frame holding exactly view_scale_primary()'s variables, under
# ggplot2's namespace, so the `super` closure ggproto() captures equals the
# one ggplot2's objects carry.
view_scale_call <- quote(ggproto(NULL, ViewScale,
  scale = scale,
  guide = scale$guide,
  position = scale$position,
  aesthetics = scale$aesthetics,
  name = scale$name,
  scale_is_discrete = scale$is_discrete(),
  limits = limits,
  continuous_range = continuous_range,
  breaks = breaks,
  minor_breaks = minor_breaks
))

new_view_scale_primary <- function(parts) {
  frame <- list2env(
    parts[c("scale", "limits", "continuous_range", "continuous_scale_sorted", "breaks", "minor_breaks")],
    parent = asNamespace("ggplot2")
  )
  eval(view_scale_call, frame)
}

# Mirrors view_scales_from_scale() (ggplot2 R/coord-cartesian-.R) and, for
# scales without a secondary axis, view_scale_secondary() (R/scale-view.R).
# `guide` is a guide_none() to copy, rather than building one per scale.
view_scales_from_parts <- function(parts, guide) {
  primary_scale <- new_view_scale_primary(parts)
  gg_scale_flip_position(primary_scale)
  primary_scale$guide <- clone_ggproto(guide)
  aesthetic <- parts$scale$aesthetics[1]

  view_scales <- list(
    new_view_scale_primary(parts),
    sec = primary_scale,
    range = parts$continuous_range
  )
  names(view_scales) <- c(aesthetic, paste0(aesthetic, ".", names(view_scales)[-1]))

  view_scales
}

# A copy of ggproto object `x` with the same members and class.
clone_ggproto <- function(x) {
  e <- list2env(as.list.environment(x, all.names = TRUE), parent = emptyenv())
  class(e) <- class(x)
  e
}
