# Boxplots, violins and the range geoms in the full tier (task R6.5b):
# geom_boxplot(), geom_violin(), geom_crossbar(), geom_errorbar(),
# geom_linerange() and geom_pointrange(). ggplot2 draws them as
# GeomPolygon, GeomSegment, GeomPath and GeomPoint grobs; here they become
# marks (closed filled paths, open paths, points) in ggplot2's drawing
# order, handed to rs_render_page() as path and point layers
# (full_marks()). Mirrors GeomBoxplot$draw_group() (ggplot2
# R/geom-boxplot.R), GeomViolin$draw_group() (R/geom-violin.R),
# GeomCrossbar$draw_panel() (R/geom-crossbar.R), GeomErrorbar$draw_panel()
# (R/geom-errorbar.R), GeomLinerange$draw_panel() (R/geom-linerange.R) and
# GeomPointrange$draw_panel() (R/geom-pointrange.R).

# The full-tier kinds of this file, by geom (compared by identity).
range_kinds <- function() {
  list(
    boxplot = ggplot2::GeomBoxplot, violin = ggplot2::GeomViolin, crossbar = ggplot2::GeomCrossbar,
    errorbar = ggplot2::GeomErrorbar, linerange = ggplot2::GeomLinerange, pointrange = ggplot2::GeomPointrange
  )
}

range_kind <- function(geom) {
  kinds <- range_kinds()
  hit <- vapply(kinds, identical, logical(1), geom)
  if (any(hit)) names(kinds)[hit][1]
}

# The position columns each kind draws from (after flip_data()).
range_positions <- function(kind) {
  switch(kind,
    boxplot = c("x", "xmin", "xmax", "lower", "middle", "upper", "ymin", "ymax"),
    violin = c("x", "y", "xmin", "xmax", "violinwidth"),
    crossbar = c("x", "y", "xmin", "xmax", "ymin", "ymax"),
    errorbar = c("x", "xmin", "xmax", "ymin", "ymax"),
    linerange = c("x", "ymin", "ymax"),
    pointrange = c("x", "ymin", "ymax")
  )
}

# Why a layer of these kinds isn't drawn in Rust, or NULL. The drawers
# (full_range()) decline the rest (gp overrides, shapes, notches) with
# layout_decline().
range_decline <- function(kind, data, params) {
  d <- gg_flip_data(data, isTRUE(params$flipped_aes))
  pos <- range_positions(kind)
  cols <- c(pos, "colour", "linewidth", "linetype", "alpha", "group", if (kind %in% c("boxplot", "violin", "crossbar")) "fill")
  if (!all(cols %in% names(d))) {
    return("missing aesthetics")
  }
  if (!all(vapply(d[pos], is.double, logical(1))) || any(vapply(d[pos], inherits, logical(1), "AsIs"))) {
    return("positions are not double")
  }
  # GeomErrorbar$handle_na() keeps rows with NA (its required_aes aren't
  # column names), and grid breaks the bars' polyline at them; the other
  # geoms would warn of them as GeomSegment$draw_panel() removes them.
  if (kind != "errorbar" && anyNA(d[pos])) {
    return("NA in positions")
  }
  if (!is_colour_vector(d$colour) || (!is.null(d$fill) && !is_colour_vector(d$fill))) {
    return("colour or fill is not a colour vector")
  }
  if (!is.numeric(d$linewidth) || anyNA(d$linewidth) || !(is.numeric(d$alpha) || all(is.na(d$alpha)))) {
    return("linewidth or alpha is not numeric")
  }
  if (is.null(lty_code(d$linetype))) {
    return("unsupported linetype")
  }
  if (!is.null(params$arrow)) {
    return("arrows")
  }
  if (kind == "boxplot") {
    if (anyDuplicated(data.frame(as.integer(d$PANEL), d$group))) {
      return("more than one boxplot per group")
    }
    if (!is.null(d$outliers) && !all(vapply(d$outliers, function(o) is.null(o) || is.double(o), logical(1)))) {
      return("outliers are not double")
    }
  }
  if (kind == "violin" && any(tabulate(vctrs::vec_group_id(data.frame(as.integer(d$PANEL), d$group))) < 2)) {
    return("a violin of fewer than two rows")
  }
  if (kind == "crossbar" && !is.null(d$ynotchlower)) {
    return("a notched crossbar")
  }
  line_params_decline(params)
}

# A colour, line type or line width override of a *_gp parameter: one
# value or NULL.
gp_value <- function(gp, name) {
  v <- gp[[name]]
  if (!is.null(v) && length(v) != 1) {
    layout_decline("a gp parameter alot doesn't draw")
  }
  v
}

# Path marks: one entry per path of `panel`, `key` (drawing order within
# the panel), vertex count `n` and style; `x` and `y` hold the vertices
# (NA splits an open path, as grid's polylines split). Colours are R
# colours, `alpha` NA keeps their own; widths are linewidths.
path_marks <- function(panel, key, n, x, y, colour, alpha, linewidth, linetype, closed, fill = NA, fill_alpha = NA) {
  k <- length(panel)
  rep_k <- function(v) if (length(v) == 1) rep(v, k) else v
  codes <- lty_code(rep_k(linetype))
  col <- point_colours(as.character(rep_k(colour)), rep_k(alpha))
  fill <- point_colours(as.character(rep_k(fill)), rep_k(fill_alpha))
  if (is.null(codes) || is.null(col) || is.null(fill)) {
    layout_decline("a colour or line type alot doesn't draw")
  }
  lwd <- rep_k(linewidth)
  if (!is.numeric(lwd) || anyNA(lwd)) {
    layout_decline("a linewidth alot doesn't draw")
  }
  list(
    panel = as.integer(panel), key = as.double(key), n = rep_k(as.integer(n)), x = as.double(x), y = as.double(y),
    colour = col, lwd = ifelse(codes < 0, 0, lwd * ggplot2::.pt), lty = as.double(pmax(codes, 0)),
    closed = rep_k(as.integer(closed)), fill = fill
  )
}

# Point marks as GeomPoint$draw_panel() (ggplot2 R/geom-point.R) draws them:
# shape names translated, col = alpha(colour, alpha), fill =
# fill_alpha(fill, alpha). Points of shape NA draw nothing (GESymbol(), R
# src/main/engine.c), so they are dropped.
point_marks <- function(panel, key, x, y, shape, size, stroke, colour, fill, alpha) {
  k <- length(panel)
  rep_k <- function(v) if (length(v) == 1) rep(v, k) else v
  shape <- rep_k(shape)
  if (is.character(shape)) {
    shape <- tryCatch(gg_translate_shape_string(shape), error = function(e) layout_decline("a point shape ggplot2 doesn't know"))
  }
  keep <- !is.na(shape)
  if (!any(keep)) {
    return(NULL)
  }
  shape <- shape[keep]
  size <- rep_k(size)[keep]
  stroke <- rep_k(stroke)[keep]
  if (!rs_point_shapes_supported(shape) || !is.numeric(size) || !is.numeric(stroke) || anyNA(size) || anyNA(stroke) ||
    anyNA(x[keep]) || anyNA(y[keep])) {
    layout_decline("a point alot doesn't draw")
  }
  alpha <- rep_k(alpha)[keep]
  col <- point_colours(as.character(rep_k(colour)[keep]), alpha)
  fill <- point_colours(as.character(rep_k(fill)[keep]), alpha)
  if (is.null(col) || is.null(fill)) {
    layout_decline("a point colour alot doesn't parse")
  }
  list(
    panel = as.integer(panel)[keep], key = as.double(key)[keep], x = as.double(x)[keep], y = as.double(y)[keep],
    shape = as.double(shape), size = as.double(size), stroke = as.double(stroke), colour = col, fill = fill
  )
}

cat_marks <- function(marks) {
  marks <- Filter(Negate(is.null), marks)
  if (length(marks) == 0) {
    return(NULL)
  }
  out <- lapply(names(marks[[1]]), function(n) unlist(lapply(marks, `[[`, n), use.names = FALSE))
  names(out) <- names(marks[[1]])
  out
}

# The marks as the layers rs_render_page() reads, in drawing order: within
# each panel, marks by `key` (ties keep their order), runs of paths and of
# points making one layer each. Where every panel has the same sequence of
# runs, run k of each panel shares a layer; otherwise each run is a layer
# of its own panel. `flip` swaps x and y (flip_data() back).
full_marks <- function(paths, points, ranges, n_panels, res, flip, cap = "butt", join = "round", mitre = 10) {
  if (flip) {
    if (!is.null(paths)) paths[c("x", "y")] <- paths[c("y", "x")]
    if (!is.null(points)) points[c("x", "y")] <- points[c("y", "x")]
  }
  np <- length(paths$panel)
  nq <- length(points$panel)
  if (np + nq == 0) {
    return(list())
  }
  type <- c(rep(0L, np), rep(1L, nq))
  idx <- c(seq_len(np), seq_len(nq))
  panel <- c(paths$panel, points$panel)
  o <- order(panel, c(paths$key, points$key))
  type <- type[o]
  idx <- idx[o]
  panel <- panel[o]
  m <- length(o)
  start <- c(TRUE, type[-1] != type[-m] | panel[-1] != panel[-m])
  run <- cumsum(start)
  first_run <- tapply(run, panel, min)
  k <- run - first_run[as.character(panel)] + 1L
  seqs <- tapply(type[start], panel[start], paste, collapse = "")
  spec_id <- if (length(unique(seqs)) == 1) k else run
  cap <- as.numeric(match(cap, c("round", "butt", "square")) - 1L)
  join <- as.numeric(match(join, c("round", "mitre", "bevel")) - 1L)
  if (is.na(cap) || is.na(join)) {
    layout_decline("an unsupported line end or join")
  }
  vstart <- c(0L, cumsum(paths$n))
  out <- list()
  for (s in unique(spec_id)) {
    at <- spec_id == s
    if (type[at][1] == 0L) {
      pi <- idx[at]
      nv <- paths$n[pi]
      verts <- rep(vstart[pi], nv) + sequence(nv)
      pid <- rep(seq_along(pi) - 1L, nv)
      pv <- rep(paths$panel[pi], nv)
      out[[length(out) + 1L]] <- c(list(kind = "paths"), ranges, list(
        x = paths$x[verts], y = paths$y[verts], colour = paths$colour[pi], lwd = paths$lwd[pi], lty = paths$lty[pi],
        closed = paths$closed[pi], fill = paths$fill[pi], cap = cap, join = join, mitre = as.double(mitre), res = res,
        rows = if (n_panels == 1) list(seq_along(verts)) else layer_panel_rows(pv, n_panels),
        path_rows = if (n_panels == 1) list(pid) else unname(lapply(split(pid, factor(pv, levels = seq_len(n_panels))), function(p) if (length(p)) p))
      ))
    } else {
      qi <- idx[at]
      out[[length(out) + 1L]] <- c(list(kind = "points"), ranges, list(
        x = points$x[qi], y = points$y[qi], shape = points$shape[qi], size = points$size[qi], stroke = points$stroke[qi],
        colour = points$colour[qi], fill = points$fill[qi], consts = c(ggplot2::.pt, ggplot2::.stroke, res),
        panel = if (n_panels > 1) points$panel[qi]
      ))
    }
  }
  out
}

# Segment marks (GeomSegment$draw_panel(), ggplot2 R/geom-segment.R, for a
# linear coord: segmentsGrob(col = alpha(colour, alpha))).
segment_marks <- function(panel, key, x, y, xend, yend, colour, alpha, linewidth, linetype) {
  path_marks(panel, key, 2L, vctrs::vec_interleave(x, xend), vctrs::vec_interleave(y, yend), colour, alpha, linewidth, linetype, 0L)
}

# The layers of one layer of these kinds (a list of layer specs).
full_range <- function(kind, layer, data, ranges, n_panels, res) {
  params <- layer$computed_geom_params
  flip <- isTRUE(params$flipped_aes)
  d <- gg_flip_data(data, flip)
  panel <- as.integer(d$PANEL)
  n <- nrow(d)
  marks <- switch(kind,
    boxplot = boxplot_marks(d, panel, params),
    violin = violin_marks(d, panel, params),
    crossbar = crossbar_marks(d, panel, params),
    errorbar = list(paths = path_marks(
      panel, seq_len(n), 8L,
      as.vector(rbind(d$xmin, d$xmax, NA, d$x, d$x, NA, d$xmin, d$xmax)),
      as.vector(rbind(d$ymax, d$ymax, NA, d$ymax, d$ymin, NA, d$ymin, d$ymin)),
      d$colour, d$alpha, d$linewidth, d$linetype, 0L
    )),
    linerange = list(paths = segment_marks(panel, seq_len(n), d$x, d$ymin, d$x, d$ymax, d$colour, d$alpha, d$linewidth, d$linetype)),
    pointrange = list(
      paths = segment_marks(panel, seq_len(n), d$x, d$ymin, d$x, d$ymax, d$colour, d$alpha, d$linewidth, d$linetype),
      points = if (!is.null(d$y)) {
        if (!all(c("shape", "size", "stroke", "fill") %in% names(d))) layout_decline("missing point aesthetics")
        point_marks(panel, n + seq_len(n), d$x, d$y, d$shape, d$size * (params$fatten %||% 4), d$stroke, d$colour, d$fill, d$alpha)
      }
    )
  )
  cap <- params$lineend %||% "butt"
  join <- switch(kind, boxplot = , crossbar = params$linejoin %||% "mitre", "round")
  full_marks(marks$paths, marks$points, ranges, n_panels, res, flip, cap = cap, join = join)
}

# GeomCrossbar$draw_panel(): every bar's polygon (GeomPolygon$draw_panel(),
# col = colour, fill = fill_alpha(fill, alpha)), then every middle segment
# (linewidth * fatten, alpha NA), with box_gp and middle_gp overriding.
crossbar_marks <- function(d, panel, params, base = 0, middle_gp = params$middle_gp, box_gp = params$box_gp,
                           fatten = params$fatten %||% 2.5, order = seq_len(nrow(d)), notch = NULL) {
  n <- nrow(d)
  if (is.null(notch)) {
    bx <- rbind(d$xmin, d$xmin, d$xmax, d$xmax, d$xmin)
    by <- rbind(d$ymax, d$ymin, d$ymin, d$ymax, d$ymax)
    mx0 <- d$xmin
    mx1 <- d$xmax
  } else {
    indent <- (1 - notch$width) * (d$xmax - d$xmin) / 2
    bx <- rbind(d$xmin, d$xmin, d$xmin + indent, d$xmin, d$xmin, d$xmax, d$xmax, d$xmax - indent, d$xmax, d$xmax, d$xmin)
    by <- rbind(d$ymax, notch$upper, d$y, notch$lower, d$ymin, d$ymin, notch$lower, d$y, notch$upper, d$ymax, d$ymax)
    mx0 <- d$xmin + indent
    mx1 <- d$xmax - indent
  }
  lw <- gp_value(middle_gp, "linewidth") %||% (d$linewidth * fatten)
  list(
    paths = cat_marks(list(
      path_marks(panel, base + order, nrow(bx), as.vector(bx), as.vector(by),
        gp_value(box_gp, "colour") %||% d$colour, NA, gp_value(box_gp, "linewidth") %||% d$linewidth,
        gp_value(box_gp, "linetype") %||% d$linetype, 1L, d$fill, d$alpha
      ),
      segment_marks(panel, base + n + order, mx0, d$y, mx1, d$y,
        gp_value(middle_gp, "colour") %||% d$colour, NA, lw, gp_value(middle_gp, "linetype") %||% d$linetype
      )
    ))
  )
}

# GeomBoxplot$draw_group(), one group at a time (Geom$draw_panel(): by
# panel, then group): the outliers (GeomPoint), the staples and whiskers
# (GeomSegment, alpha NA) and the box (GeomCrossbar$draw_panel(), fatten
# 2 by default, notched with `notch`).
boxplot_marks <- function(d, panel, params) {
  n <- nrow(d)
  rank <- integer(n)
  rank[order(panel, d$group)] <- seq_len(n)
  base <- rank * 8
  notch <- NULL
  if (isTRUE(params$notch)) {
    if (!all(c("notchlower", "notchupper") %in% names(d)) || anyNA(d[c("notchlower", "notchupper")])) {
      layout_decline("notches without notch bounds")
    }
    if (any(d$notchlower < d$lower | d$notchupper > d$upper)) {
      layout_decline("a notch outside the hinges")
    }
    notch <- list(lower = d$notchlower, upper = d$notchupper, width = params$notchwidth %||% 0.5)
  }
  box <- d
  box$y <- d$middle
  box$ymax <- d$upper
  box$ymin <- d$lower
  crossbar <- crossbar_marks(box, panel, params, middle_gp = params$median_gp, box_gp = params$box_gp,
    fatten = params$fatten %||% 2, notch = notch)
  # Box polygon key 3, median key 4 (crossbar_marks() keys them 1..n and
  # n+1..2n).
  crossbar$paths$key <- c(base + 3, base + 4)
  wg <- params$whisker_gp
  whiskers <- segment_marks(c(panel, panel), c(base + 2, base + 2.5), c(d$x, d$x), c(d$upper, d$lower), c(d$x, d$x),
    c(d$ymax, d$ymin), gp_value(wg, "colour") %||% rep(d$colour, 2), NA, gp_value(wg, "linewidth") %||% rep(d$linewidth, 2),
    gp_value(wg, "linetype") %||% rep(d$linetype, 2)
  )
  staples <- NULL
  sw <- params$staplewidth %||% 0
  if (sw != 0) {
    sg <- params$staple_gp
    x0 <- (d$xmin - d$x) * sw + d$x
    x1 <- (d$xmax - d$x) * sw + d$x
    staples <- segment_marks(c(panel, panel), c(base + 1, base + 1.5), c(x0, x0), c(d$ymax, d$ymin), c(x1, x1),
      c(d$ymax, d$ymin), gp_value(sg, "colour") %||% rep(d$colour, 2), NA, gp_value(sg, "linewidth") %||% rep(d$linewidth, 2),
      gp_value(sg, "linetype") %||% rep(d$linetype, 2)
    )
  }
  points <- NULL
  if (!is.null(d$outliers)) {
    no <- lengths(d$outliers)
    if (sum(no) > 0) {
      og <- params$outlier_gp
      at <- rep(seq_len(n), no)
      pick <- function(name, default) {
        v <- gp_value(og, name) %||% d[[name]] %||% default
        if (length(v) == 1) v else v[at]
      }
      points <- point_marks(panel[at], base[at], d$x[at], unlist(d$outliers, use.names = FALSE),
        pick("shape", 19), pick("size", 1.5), pick("stroke", 0.5), pick("colour", NA), pick("fill", NA), pick("alpha", NA)
      )
    }
  }
  list(paths = cat_marks(list(staples, whiskers, crossbar$paths)), points = points)
}

# GeomViolin$draw_group(), one group at a time: the polygon of each side
# (x -/+ violinwidth of the half width, by y up the left side and down the
# right, closed with the first row again; GeomPolygon$draw_panel(), styled
# by the first row), then the quantile lines of quantile_gp
# (GeomPath$draw_panel() of the polygon's rows with a quantile, one path
# per quantile, alpha(colour, alpha)).
violin_marks <- function(d, panel, params) {
  o <- order(panel, d$group)
  key <- vctrs::vec_group_id(data.frame(panel, d$group)[o, , drop = FALSE])
  groups <- split(o, key)
  rows <- lapply(groups, function(r) {
    up <- r[order(d$y[r])]
    c(up, r[order(d$y[r], decreasing = TRUE)], up[1])
  })
  side <- lapply(groups, function(r) c(rep(-1, length(r)), rep(1, length(r)), -1))
  rows_v <- unlist(rows, use.names = FALSE)
  side_v <- unlist(side, use.names = FALSE)
  xv <- ifelse(side_v < 0, d$x[rows_v] - d$violinwidth[rows_v] * (d$x[rows_v] - d$xmin[rows_v]),
    d$x[rows_v] + d$violinwidth[rows_v] * (d$xmax[rows_v] - d$x[rows_v]))
  yv <- d$y[rows_v]
  first <- vapply(groups, `[`, integer(1), 1)
  ng <- length(groups)
  paths <- list(path_marks(panel[first], seq_len(ng) * 2, lengths(rows), xv, yv, d$colour[first], NA, d$linewidth[first],
    d$linetype[first], 1L, d$fill[first], d$alpha[first]))
  qg <- params$quantile_gp
  if ("quantile" %in% names(d) && !(all(qg$linetype == 0) || all(qg$linetype == "blank"))) {
    gid <- rep(seq_len(ng), lengths(rows))
    q <- d$quantile[rows_v]
    has <- !is.na(q)
    if (any(has)) {
      g2 <- gid[has]
      grp <- unlist(lapply(split(seq_len(sum(has)), g2), function(i) match(q[has][i], unique(q[has][i]))), use.names = FALSE)
      ord <- order(g2, grp)
      vr <- which(has)[ord]
      pk <- paste(gid[vr], grp[ord])
      starts <- !duplicated(pk)
      nper <- as.vector(table(factor(pk, levels = unique(pk))))
      keep <- rep(nper >= 2, nper)
      vr <- vr[keep]
      starts <- starts[keep]
      nper <- nper[nper >= 2]
      if (length(vr)) {
        fr <- rows_v[vr][starts]
        rep_q <- function(v) if (is.null(v)) NULL else rep(v, length(fr))
        paths[[2]] <- path_marks(panel[fr], gid[vr][starts] * 2 + 1, nper, xv[vr], yv[vr],
          rep_q(gp_value(qg, "colour")) %||% d$colour[fr], d$alpha[fr], rep_q(gp_value(qg, "linewidth")) %||% d$linewidth[fr],
          rep_q(gp_value(qg, "linetype")) %||% d$linetype[fr], 0L
        )
      }
    }
  }
  list(paths = cat_marks(paths))
}
