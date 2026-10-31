# Mirrors Layout$setup_panel_guides (ggplot2 R/layout.R) with
# Coord$setup_panel_guides and Coord$train_panel_guides (R/coord-.R) for
# CoordCartesian and CoordFixed, which share them and CoordCartesian's
# transform (R/coord-cartesian-.R).
#
# ggplot2 sets up and trains a pair of axis guides per distinct COORD. With
# default axis guides, the trained parameters of the x guide depend on the x
# view scale alone (breaks, labels, rescaling), apart from the column holding
# the opposite aesthetic, which is +-Inf squished to 0 or 1. So the x and y
# guides are trained once per distinct SCALE_X and SCALE_Y, from the raw
# ggproto functions rather than through ggproto dispatch, and each COORD's
# Guides object is assembled as a clone of one set-up template with those
# parameters swapped in. Anything else (user guides, secondary axes, cap,
# minor ticks, other coords) falls back.

layout_setup_panel_guides <- function(layout, guides, layers) {
  class_method <- environment(ggplot2::Layout$setup_panel_guides)$f
  if (!identical(environment(layout$setup_panel_guides)$f, class_method)) {
    record_trace("setup_panel_guides", class(layout)[1], "ggplot2")
    return(layout$setup_panel_guides(guides, layers))
  }
  coord <- layout$coord
  invisible(dispatch(
    "setup_panel_guides", coord, list(layout = layout, guides = guides, coord = coord),
    function() layout$setup_panel_guides(guides, layers)
  ))
}

# The members of the Coord and Facet that this kernel reproduces.
panel_guides_coord_methods <- c("setup_panel_guides", "train_panel_guides", "transform", "is_linear")

kernel_panel_guides <- function(layout, guides, coord) {
  for (m in panel_guides_coord_methods) {
    if (!identical(environment(coord[[m]])$f, environment(ggplot2::CoordCartesian[[m]])$f)) {
      return(NULL)
    }
  }
  # Facet$setup_panel_params may alter the panel params of a COORD.
  if (!identical(environment(layout$facet$setup_panel_params)$f, environment(ggplot2::Facet$setup_panel_params)$f)) {
    return(NULL)
  }
  params <- layout$coord_params
  if (!is.null(params$guide_default) || !is.null(params$guide_missing)) {
    return(NULL)
  }
  if (any(c("x", "y", "x.sec", "y.sec") %in% names(guides$guides))) {
    return(NULL)
  }

  panels <- layout$layout
  index <- vctrs::vec_unique_loc(panels$COORD)
  order <- vctrs::vec_match(panels$COORD, panels$COORD[index])
  panel_params <- layout$panel_params[index]
  scale_x <- panels$SCALE_X[index]
  scale_y <- panels$SCALE_Y[index]

  # Coord$setup_panel_guides, as ggplot2 calls it for every COORD. The Guides
  # objects it returns capture the call's frame, so they are not cloned.
  set_up <- lapply(panel_params, function(pp) coord$setup_panel_guides(pp, guides, params))
  template <- set_up[[1]]$guides
  fns <- panel_guides_functions(template, panel_params[[1]])
  if (is.null(fns)) {
    return(NULL)
  }
  same_setup <- vapply(set_up, function(pp) identical(pp$guides$params, template$params), logical(1))
  if (!all(same_setup)) {
    return(NULL)
  }

  # Base parameters, trained once per distinct x and y scale.
  base_x <- base_y <- list()
  for (i in which(!duplicated(scale_x))) {
    base_x[as.character(scale_x[i])] <- list(axis_guide_base(template$params[[1]], panel_params[[i]]$x, fns))
  }
  for (i in which(!duplicated(scale_y))) {
    base_y[as.character(scale_y[i])] <- list(axis_guide_base(template$params[[2]], panel_params[[i]]$y, fns))
  }
  if (any(vapply(c(base_x, base_y), is.null, logical(1)))) {
    return(NULL)
  }

  # The x guide's key has a y column holding the y scale's rescaling of +-Inf,
  # and the other way round, so the transformed parameters are cached per
  # (scale, value).
  cache <- new.env(parent = emptyenv())
  trained <- vector("list", length(index))
  for (i in seq_along(index)) {
    pp <- panel_params[[i]]
    if (!identical(pp$reverse, "none")) {
      return(NULL)
    }
    id_x <- as.character(scale_x[i])
    id_y <- as.character(scale_y[i])
    px <- axis_guide_params(cache, base_x[[id_x]], paste0("x", id_x), base_y[[id_y]])
    py <- axis_guide_params(cache, base_y[[id_y]], paste0("y", id_y), base_x[[id_x]])
    if (is.null(px) || is.null(py)) {
      return(NULL)
    }
    trained[[i]] <- list(px, py)
  }

  # Coord$train_panel_guides ends with guides$update_params().
  for (i in seq_along(index)) {
    g <- set_up[[i]]$guides
    g$params[[1]] <- trained[[i]][[1]]
    g$params[[2]] <- trained[[i]][[2]]
  }
  layout$panel_params <- set_up[order]
  TRUE
}

# The raw ggproto functions used to train an axis guide, if the template's
# guides are default axis guides these functions describe: GuideAxis for x
# and y, GuideNone for their secondary counterparts, the scales' own guides
# unset and no cap or minor ticks.
panel_guides_functions <- function(template, panel_params) {
  if (!identical(unname(template$aesthetics), c("x", "y", "x.sec", "y.sec"))) {
    return(NULL)
  }
  classes <- vapply(template$guides, function(g) class(g)[1], "")
  if (!identical(unname(classes), c("GuideAxis", "GuideAxis", "GuideNone", "GuideNone"))) {
    return(NULL)
  }
  raw <- function(obj, name) environment(obj[[name]])$f
  # With cap = "none", extract_decor() ignores the scale and the key.
  fns <- list(decor = lapply(
    c(x = "x", y = "y"),
    function(aesthetic) raw(ggplot2::GuideAxis, "extract_decor")(NULL, aesthetic, NULL, NULL, cap = "none")
  ))
  for (g in template$guides[1:2]) {
    for (m in c("train", "extract_key", "extract_decor", "extract_params", "transform", "get_layer_key")) {
      if (!identical(raw(g, m), raw(ggplot2::GuideAxis, m))) {
        return(NULL)
      }
    }
    if (!identical(g$params$minor.ticks, FALSE) || !identical(g$params$cap, "none")) {
      return(NULL)
    }
  }
  # Both secondary view scales must be the plain ones with a guide_none().
  if (!all(vapply(panel_params[c("x.sec", "y.sec")], function(v) inherits(v$guide, "GuideNone"), logical(1)))) {
    return(NULL)
  }
  fns
}

# What GuideAxis training (Guide$train, ggplot2 R/guide-.R) and transform
# determine from the view scale `vs` alone: aesthetic, key, decor, name and
# hash, with the key and decor rescaled. Returns the parameters and the view
# scale's rescaling of c(-Inf, Inf), or NULL for anything but a plain,
# non-empty axis on a view scale with a finite, non-zero range.
axis_guide_base <- function(params, vs, fns) {
  aesthetic <- .subset2(vs, "aesthetics")[1]
  range <- .subset2(vs, "continuous_range")
  position <- .subset2(vs, "position")
  if (!gg_is_waiver(.subset2(vs, "guide")) || !identical(position, params$position) ||
      !all(is.finite(range)) || scales::zero_range(range)) {
    return(NULL)
  }
  if (!(position %in% (if (aesthetic == "x") c("top", "bottom") else c("left", "right")))) {
    return(NULL)
  }
  params$aesthetic <- aesthetic
  key <- axis_key(vs, aesthetic)
  if (is.null(key) || nrow(key) == 0) {
    return(NULL)
  }
  params$key <- key
  params$decor <- fns$decor[[aesthetic]]
  params$name <- paste0(params$name, "_", aesthetic)
  # Guide$hashables of GuideAxis: title, key$.value, key$.label, name.
  params$hash <- rlang::hash(list(params$title, key$.value, key$.label, params$name))

  # The part of GuideAxis$transform (ggplot2 R/guide-axis.R) that depends on
  # this view scale alone, under CoordCartesian$transform with no reversal.
  # rescale() works elementwise, so a plain double column and the decor's
  # c(-Inf, Inf) go through together.
  x <- key[[aesthetic]]
  if (is.double(x) && is.null(attributes(x))) {
    n <- length(x)
    all <- scales::squish_infinite(axis_rescale(vs, c(x, -Inf, Inf)))
    rescaled <- all[seq_len(n)]
    infinite <- all[n + 1:2]
  } else {
    rescaled <- scales::squish_infinite(axis_rescale(vs, x))
    infinite <- scales::squish_infinite(axis_rescale(vs, c(-Inf, Inf)))
  }
  # Ported over from `warn_for_position_guide`: ggplot2 warns when all unique
  # breaks land on one value. The fallback then warns.
  unique_breaks <- !duplicated(key$.value)
  if (sum(unique_breaks) > 1 && length(unique(rescaled[unique_breaks])) == 1) {
    return(NULL)
  }
  params$key <- axis_set_column(key, aesthetic, rescaled)
  params$decor <- axis_set_column(params$decor, aesthetic, infinite)
  list(params = params, infinite = infinite)
}

# Mirrors ViewScale$rescale (ggplot2 R/scale-view.R).
axis_rescale <- function(vs, x) {
  .subset2(vs, "scale")$rescale(x, .subset2(vs, "limits"), .subset2(vs, "continuous_range"))
}

# Mirrors Guide$extract_key and GuideAxis$extract_key (ggplot2 R/guide-.R,
# R/guide-axis.R) without minor ticks, for a ViewScale (R/scale-view.R). NULL
# if there are no breaks, which ggplot2 handles.
axis_key <- function(vs, aesthetic) {
  breaks <- .subset2(vs, "breaks")
  if (length(breaks) == 0) {
    return(NULL)
  }
  scale <- .subset2(vs, "scale")
  mapped <- if (.subset2(vs, "scale_is_discrete")) scale$map(breaks, .subset2(vs, "limits")) else breaks
  labels <- scale$get_labels(breaks)

  n <- length(mapped)
  if (length(breaks) == n && length(labels) == n && (is.character(labels) || is.numeric(labels)) &&
      is.null(names(mapped)) && is.null(names(breaks)) && is.null(names(labels))) {
    # What data_frame() and `$<-` build, without their overhead.
    key <- structure(
      list(mapped, breaks, labels),
      names = c(aesthetic, ".value", ".label"), row.names = c(NA_integer_, -n), class = "data.frame"
    )
  } else {
    key <- rlang::inject(vctrs::data_frame(!!aesthetic := mapped))
    key$.value <- breaks
    key$.label <- labels
  }

  if (is.numeric(breaks)) {
    range <- .subset2(vs, "continuous_range") %||% vs$get_limits()
    key <- key[is.finite(scales::oob_censor_any(breaks, range)), , drop = FALSE]
  }
  key
}

# The rest of GuideAxis$transform: the key and decor get a column for the
# opposite aesthetic, holding the override (-+Inf by position) rescaled and
# squished by the opposite view scale, which `ortho` is the base of. That is
# 0 or 1 for the ranges axis_guide_base() accepts; NULL if it is neither.
axis_guide_params <- function(cache, base, id, ortho_base) {
  params <- base$params
  aesthetic <- params$aesthetic
  ortho <- if (aesthetic == "x") "y" else "x"
  override <- switch(params$position, bottom = , left = -Inf, Inf)
  override <- -override # `reverse` is "none"
  ortho_value <- ortho_base$infinite[if (override > 0) 2L else 1L]
  if (!ortho_value %in% c(0, 1)) {
    return(NULL)
  }

  key_id <- paste0(id, "|", ortho_value)
  out <- cache[[key_id]]
  if (is.null(out)) {
    out <- params
    out$key[[ortho]] <- ortho_value
    out$decor[[ortho]] <- ortho_value
    cache[[key_id]] <- out
  }
  out
}

# One column of `df` replaced, the way transform_position() does (on the
# unclassed list).
axis_set_column <- function(df, name, value) {
  oldclass <- class(df)
  df <- unclass(df)
  df[[name]] <- value
  class(df) <- oldclass
  df
}
