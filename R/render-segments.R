# Segments, reference lines and rugs in the full tier (task R6.5c):
# geom_segment(), geom_abline(), geom_hline(), geom_vline() and
# geom_rug(). ggplot2 draws each as segmentsGrob()s; here they become
# two-vertex path marks in ggplot2's drawing order, handed to
# rs_render_page() as path layers (full_marks(), R/render-ranges.R).
# Mirrors GeomSegment$draw_panel() (ggplot2 R/geom-segment.R),
# GeomAbline$draw_panel() (R/geom-abline.R), GeomHline$draw_panel()
# (R/geom-hline.R), GeomVline$draw_panel() (R/geom-vline.R) and
# GeomRug$draw_panel() (R/geom-rug.R). geom_curve() is not drawn: grid's
# curveGrob() places its control points in inches and draws an X-spline
# the graphics engine evaluates (GEXspline), which alot doesn't mirror.

# The full-tier kinds of this file, by geom (compared by identity, so
# GeomCurve, which inherits GeomSegment, isn't one).
segment_kinds <- function() {
  list(
    segment = ggplot2::GeomSegment, abline = ggplot2::GeomAbline, hline = ggplot2::GeomHline,
    vline = ggplot2::GeomVline, rug = ggplot2::GeomRug
  )
}

segment_kind <- function(geom) {
  kinds <- segment_kinds()
  hit <- vapply(kinds, identical, logical(1), geom)
  if (any(hit)) names(kinds)[hit][1]
}

# The position columns each kind draws from (the rug's are optional).
segment_positions <- function(kind, data) {
  switch(kind,
    segment = intersect(c("x", "y", "xend", "yend"), names(data)),
    abline = c("slope", "intercept"),
    hline = "yintercept",
    vline = "xintercept",
    rug = intersect(c("x", "y"), names(data))
  )
}

# Why a layer of these kinds isn't drawn in Rust, or NULL.
segment_decline <- function(kind, data, params) {
  pos <- segment_positions(kind, data)
  if (kind == "segment" && !all(c("x", "y") %in% pos)) {
    return("missing aesthetics")
  }
  if (!all(c(pos, "colour", "linewidth", "linetype", "alpha") %in% names(data))) {
    return("missing aesthetics")
  }
  if (!all(vapply(data[pos], is.double, logical(1))) || any(vapply(data[pos], inherits, logical(1), "AsIs"))) {
    return("positions are not double")
  }
  # GeomSegment$draw_panel() warns of the rows with NA it removes; grid
  # skips a rug's segments at NA (GeomRug$handle_na() keeps a row missing
  # only one of x and y).
  if (kind != "rug" && anyNA(data[pos])) {
    return("NA in positions")
  }
  if (!is_colour_vector(data$colour)) {
    return("colour is not a colour vector")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth) || !(is.numeric(data$alpha) || all(is.na(data$alpha)))) {
    return("linewidth or alpha is not numeric")
  }
  if (is.null(lty_code(data$linetype))) {
    return("unsupported linetype")
  }
  if (!is.null(params$arrow)) {
    return("arrows")
  }
  if (kind == "rug") {
    len <- params$length %||% grid::unit(0.03, "npc")
    if (!grid::is.unit(len) || length(len) != 1 || !identical(grid::unitType(len), "npc") || !is.character(params$sides %||% "bl") ||
      length(params$sides %||% "bl") != 1) {
      return("a rug length that is not one npc unit")
    }
  }
  line_params_decline(params)
}

# Each row's panel range (one pair, or a pair per panel) as two columns.
panel_range_rows <- function(r, panel) {
  if (length(r) == 2) cbind(rep(r[1], length(panel)), rep(r[2], length(panel))) else cbind(r[2 * panel - 1], r[2 * panel])
}

# The layers of one layer of these kinds (a list of layer specs).
full_segments <- function(kind, layer, data, ranges, n_panels, res) {
  params <- layer$computed_geom_params
  panel <- as.integer(data$PANEL)
  n <- nrow(data)
  # The reference lines: GeomSegment$draw_panel() of unique0(data) with
  # the ends set, per panel (PANEL is a column, so one vec_unique_loc()
  # over the panels is the same).
  ends <- switch(kind,
    segment = list(x = data$x, y = data$y, xend = data$xend %||% data$x, yend = data$yend %||% data$y),
    # coord$backtransform_range() is the panel's continuous range, which
    # rescales to 0 and 1 as -Inf and Inf squish to.
    hline = list(x = rep(-Inf, n), xend = rep(Inf, n), y = data$yintercept, yend = data$yintercept),
    vline = list(x = data$xintercept, xend = data$xintercept, y = rep(-Inf, n), yend = rep(Inf, n)),
    abline = {
      # clip is "on" (hybrid_decline()), so the ranges extend by their
      # width either side.
      rx <- panel_range_rows(ranges$x_range, panel)
      ry <- panel_range_rows(ranges$y_range, panel)
      dx <- rx[, 2] - rx[, 1]
      dy <- ry[, 2] - ry[, 1]
      x1 <- ((ry[, 1] - dy) - data$intercept) / data$slope
      x2 <- ((ry[, 2] + dy) - data$intercept) / data$slope
      x <- pmax(rx[, 1] - dx, pmin(x1, x2))
      xend <- pmin(rx[, 2] + dx, pmax(x1, x2))
      list(x = x, xend = xend, y = x * data$slope + data$intercept, yend = xend * data$slope + data$intercept)
    },
    rug = NULL
  )
  if (kind == "rug") {
    return(full_marks(rug_marks(data, panel, params, ranges), NULL, ranges, n_panels, res, FALSE,
      cap = params$lineend %||% "butt"))
  }
  rows <- seq_len(n)
  if (kind != "segment") {
    u <- data
    u[names(ends)] <- ends
    rows <- vctrs::vec_unique_loc(u)
    ends <- lapply(ends, `[`, rows)
  }
  if (anyNA(unlist(ends))) {
    # remove_missing() in GeomSegment$draw_panel() would warn of them.
    layout_decline("NA segment ends")
  }
  d <- data[rows, , drop = FALSE]
  marks <- segment_marks(panel[rows], seq_along(rows), ends$x, ends$y, ends$xend, ends$yend, d$colour, d$alpha, d$linewidth,
    d$linetype)
  full_marks(marks, NULL, ranges, n_panels, res, FALSE, cap = params$lineend %||% "butt",
    join = if (kind == "segment") params$linejoin %||% "round" else "round")
}

# GeomRug$draw_panel(): per panel, a segmentsGrob() of every row for each
# of the sides "b", "t" (from x) then "l", "r" (from y), from the panel's
# edge to `length` inside it (or outside, with `outside`), in
# alpha(colour, alpha). npc positions are given in data units of the
# panel's range. grid draws nothing for a segment at NA.
rug_marks <- function(data, panel, params, ranges) {
  sides <- params$sides %||% "bl"
  len <- as.numeric(params$length %||% grid::unit(0.03, "npc"))
  lo <- if (isTRUE(params$outside)) -len else len
  hi <- if (isTRUE(params$outside)) 1 + len else 1 - len
  n <- nrow(data)
  rx <- panel_range_rows(ranges$x_range, panel)
  ry <- panel_range_rows(ranges$y_range, panel)
  npc <- function(r, v) r[, 1] + v * (r[, 2] - r[, 1])
  marks <- list()
  side <- function(k, s, aes) {
    if (!grepl(s, sides) || is.null(data[[aes]])) {
      return()
    }
    keep <- which(!is.na(data[[aes]]))
    if (!length(keep)) {
      return()
    }
    r <- if (aes == "x") ry else rx
    from <- npc(r, if (s %in% c("b", "l")) 0 else 1)
    to <- npc(r, if (s %in% c("b", "l")) lo else hi)
    v <- data[[aes]]
    m <- if (aes == "x") {
      segment_marks(panel[keep], k * n + keep, v[keep], from[keep], v[keep], to[keep], data$colour[keep], data$alpha[keep],
        data$linewidth[keep], data$linetype[keep])
    } else {
      segment_marks(panel[keep], k * n + keep, from[keep], v[keep], to[keep], v[keep], data$colour[keep], data$alpha[keep],
        data$linewidth[keep], data$linetype[keep])
    }
    marks[[length(marks) + 1L]] <<- m
  }
  side(0, "b", "x")
  side(1, "t", "x")
  side(2, "l", "y")
  side(3, "r", "y")
  cat_marks(marks)
}
