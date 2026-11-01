# Labels and polygons in the full tier (TASKS.md R6.5d): geom_label() and
# geom_polygon(). Mirrors GeomLabel$draw_panel() and labelGrob() (ggplot2
# R/geom-label.R), with titleGrob() (R/margins.R) placing the text and
# grid's roundrectGrob() (rrpoints(), R src/library/grid/R/roundRect.R)
# drawing the box as a polygon; and GeomPolygon$draw_panel() (ggplot2
# R/geom-polygon.R) without subgroups. annotate() layers need nothing of
# their own: they are layers of these geoms with inherit.aes = FALSE and
# no legend. geom_raster() is drawn by R/render-raster.R.

label_kind <- function(geom) {
  if (identical(geom, ggplot2::GeomLabel) &&
    identical(environment(geom$draw_panel)$f, environment(ggplot2::GeomLabel$draw_panel)$f)) {
    "label"
  }
}

# A unit of labelGrob() as device pixels per row: "lines" and "char" are
# relative to the label viewport's fontsize (labelGrob() sets
# gpar(fontsize) on it; lineheight is grid's default 1.2), other types are
# absolute. NULL where alot doesn't convert the unit.
label_unit_px <- function(u, fontsize, res) {
  if (!grid::is.unit(u) || !is.null(attr(u, "data")) && !all(vapply(attr(u, "data"), is.null, logical(1)))) {
    return(NULL)
  }
  type <- grid::unitType(u)
  per_inch <- c(points = 72.27, pt = 72.27, bigpts = 72, picas = 72.27 / 12, cm = 2.54, mm = 25.4, inches = 1, `in` = 1, inch = 1)
  out <- lapply(seq_along(u), function(i) {
    v <- as.numeric(u[i])
    switch(type[i],
      lines = v * fontsize * 1.2 / 72 * res,
      char = v * fontsize / 72 * res,
      if (type[i] %in% names(per_inch)) rep(v / per_inch[[type[i]]] * res, length(fontsize))
    )
  })
  if (any(vapply(out, is.null, logical(1)))) NULL else out
}

# Why a geom_label() layer isn't drawn in Rust, or NULL.
label_decline <- function(data, params) {
  reason <- text_decline(data, params)
  if (!is.null(reason)) {
    return(reason)
  }
  if (!all(c("fill", "linewidth", "linetype") %in% names(data))) {
    return("missing label aesthetics")
  }
  if (!all(is.finite(data$x)) || !all(is.finite(data$y))) {
    return("non-finite label positions")
  }
  if (any(grepl("\n", as.character(data$label), fixed = TRUE))) {
    return("multi-line labels")
  }
  if (!is_colour_vector(data$fill) || !is.numeric(data$linewidth) || anyNA(data$linewidth) || is.null(lty_code(data$linetype))) {
    return("label fill, linewidth or linetype alot doesn't draw")
  }
  pad <- params$label.padding %||% grid::unit(0.25, "lines")
  r <- params$label.r %||% grid::unit(0.15, "lines")
  if (is.null(label_unit_px(pad, 1, 72)) || !length(pad) %in% c(1, 4) || is.null(label_unit_px(r, 1, 72)) || length(r) != 1) {
    return("label.padding or label.r in units alot doesn't convert")
  }
  for (p in c("border.colour", "text.colour")) {
    if (!is.null(params[[p]]) && !(is.character(params[[p]]) && length(params[[p]]) == 1)) {
      return(paste(p, "is not one colour"))
    }
  }
  NULL
}

# grid's rrpoints(): a round rect of width `w` and height `h` (pixels, y
# up, from its bottom-left corner) with corners of radius `r`, as the
# polygon makeContent.roundrect() draws.
label_rrpoints <- function(w, h, r) {
  n <- 10 * 4
  t <- seq(0, 2 * pi, length.out = n)
  corner <- function(num, x, y) {
    switch(num,
      list(xc = x + r, yc = y + r, s = (n / 2):(3 * n / 4)),
      list(xc = x + r, yc = y - r, s = (n / 4):(n / 2)),
      list(xc = x - r, yc = y - r, s = 1L:(n / 4)),
      list(xc = x - r, yc = y + r, s = (3 * n / 4):n)
    ) -> k
    list(x = k$xc + (cos(t) * r)[k$s], y = k$yc + (sin(t) * r)[k$s])
  }
  c1 <- corner(1, 0, 0)
  c2 <- corner(2, 0, h)
  c3 <- corner(3, w, h)
  c4 <- corner(4, w, 0)
  list(
    x = c(r, w - r, c4$x, w, w, c3$x, w - r, r, c2$x, 0, 0, c1$x),
    y = c(0, 0, c4$y, r, h - r, c3$y, h, h, c2$y, h - r, r, c1$y)
  )
}

# labelGrob()'s layout about its position, in device pixels (y up within,
# y down in the result): for text of width `w` and height `h` (grobwidth,
# grobheight), the descent `d` of "gjpqyQ", padding `pad` (top, right,
# bottom, left), corner radius `r`, justification and angle (degrees; the
# viewport rotates about the position). Returns the text's offset (`dx`,
# `dy`) and each box's polygon offsets (`boxes`, a list of x, y).
label_geometry <- function(w, h, d, pad, r, hjust, vjust, angle) {
  n <- length(w)
  pt <- pmax(pad[[1]], d)
  pb <- pmax(pad[[3]] - d, 0)
  pr <- pad[[2]]
  pl <- pad[[4]]
  bw <- pl + w + pr
  bh <- pt + h + d + pb
  theta <- angle / 180 * pi
  rot <- function(x, y, i) list(x = x * cos(theta[i]) - y * sin(theta[i]), y = -(x * sin(theta[i]) + y * cos(theta[i])))
  t <- rot(-pr * hjust + pl * (1 - hjust), (1 - vjust) * d - pt * vjust + pb * (1 - vjust), seq_len(n))
  boxes <- lapply(seq_len(n), function(i) {
    p <- label_rrpoints(bw[i], bh[i], r[i])
    rot(p$x - hjust[i] * bw[i], p$y - vjust[i] * bh[i], i)
  })
  list(dx = as.double(t$x), dy = as.double(t$y), boxes = boxes, width = bw, height = bh)
}

# A label layer: a "labels" spec of a path layer of boxes (closed, filled,
# at the labels' data positions plus offsets in device pixels) and a text
# layer (full_text() with the text's offsets). Per row, as labelGrob()
# lays it out in its viewport (rotated by `angle` about the position):
# the descent d of "gjpqyQ" (font_descent(), plain face) raises the top
# padding to at least d and takes d off the bottom one; the text, at
# hjust/vjust, sits at x - pr * h + pl * (1 - h), y + (1 - v) * d - pt * v +
# pb * (1 - v) (titleGrob()'s margins); the box is the text's width plus
# pl + pr and its height plus d + pt + pb (widthDetails()/heightDetails()),
# left at -h * W and bottom at -v * H, with col = border.colour (NA where
# linewidth is 0), fill = fill_alpha(fill, alpha), lwd and lty; the text's
# colour is text.colour or colour, without alpha.
full_labels <- function(layer, data, coord, pps, scales, n_panels, res, ranges) {
  params <- layer$computed_geom_params
  o <- order(as.integer(data$PANEL))
  data <- data[o, , drop = FALSE]
  n <- nrow(data)
  fontsize <- data$size * gg_resolve_text_unit(params$size.unit %||% "mm")
  label <- gg_validate_labels(as.character(data$label))
  face <- text_face(data$fontface)
  m <- text_metrics(label, data$family, face, fontsize = fontsize, lineheight = data$lineheight, res = res)
  d <- text_metrics(rep("gjpqyQ", n), data$family, 1L, fontsize = fontsize, res = res)$descent
  if (anyNA(m$width) || anyNA(m$height) || anyNA(d)) {
    layout_decline("label text alot doesn't measure as ragg does")
  }
  pad <- label_unit_px(params$label.padding %||% grid::unit(0.25, "lines"), fontsize, res)
  pad <- rep(pad, length.out = 4)
  r <- label_unit_px(params$label.r %||% grid::unit(0.15, "lines"), fontsize, res)[[1]]
  # The text layer (positions through the coord, justification resolved).
  text_data <- data
  text_data$colour <- params$text.colour %||% data$colour
  text_data$alpha <- NA
  text <- full_text(layer, text_data, coord, pps, scales, n_panels, res)
  g <- label_geometry(m$width, m$height, d, pad, r, text$hjust, text$vjust, data$angle)
  text$dx <- g$dx
  text$dy <- g$dy
  boxes <- g$boxes
  nv <- lengths(lapply(boxes, `[[`, "x"))
  border <- params$border.colour %||% data$colour
  border <- rep_len(border, n)
  border[data$linewidth == 0] <- NA
  marks <- path_marks(
    as.integer(data$PANEL), seq_len(n), nv, rep(data$x, nv), rep(data$y, nv), border, NA, data$linewidth, data$linetype, 1L,
    fill = data$fill, fill_alpha = data$alpha
  )
  panel <- rep(marks$panel, nv)
  pid <- rep(seq_len(n) - 1L, nv)
  rows <- layer_panel_rows(panel, n_panels)
  pid_rows <- lapply(rows, function(rr) if (length(rr)) pid[rr])
  boxes_spec <- c(ranges, list(
    x = marks$x, y = marks$y, colour = marks$colour, lwd = marks$lwd, lty = marks$lty, closed = marks$closed, fill = marks$fill,
    cap = 0, join = 0, mitre = 10, res = res,
    dx = as.double(unlist(lapply(boxes, `[[`, "x"))), dy = as.double(unlist(lapply(boxes, `[[`, "y"))),
    rows = rows, path_rows = pid_rows
  ))
  list(kind = "labels", boxes = boxes_spec, text = text)
}

# A polygon layer, mirroring draw_polygons_layer() (R/render.R) and
# GeomPolygon$draw_panel(): per panel of more than one row, one polygon
# per group in group order (polygonGrob(id = group), filled non-zero by
# ragg's drawPolygon()), styled by the group's first row (col = colour,
# fill = fill_alpha(fill, alpha)), lineend and linejoin from the
# parameters. Subgroups (pathGrob() with holes and `rule`) decline.
full_polygons <- function(layer, data, ranges, n_panels, res) {
  params <- layer$computed_geom_params
  if (!is.null(data$subgroup)) {
    layout_decline("polygon subgroups")
  }
  # A panel of one row draws nothing (zeroGrob()).
  per_panel <- tabulate(as.integer(data$PANEL), n_panels)
  data <- data[per_panel[as.integer(data$PANEL)] > 1, , drop = FALSE]
  if (nrow(data) == 0) {
    return(list())
  }
  pg <- panel_group_order(data)
  order <- pg$order
  key <- pg$key[order]
  first <- order[!duplicated(key)]
  nv <- as.vector(table(factor(key, levels = unique(key))))
  marks <- path_marks(
    as.integer(data$PANEL[first]), seq_along(first), nv, data$x[order], data$y[order], data$colour[first], NA,
    data$linewidth[first], data$linetype[first], 1L, fill = data$fill[first], fill_alpha = data$alpha[first]
  )
  full_marks(marks, NULL, ranges, n_panels, res, FALSE,
    cap = params$lineend %||% "butt", join = params$linejoin %||% "round", mitre = params$linemitre %||% 10
  )
}

# draw_key_label() (ggplot2 R/legend-draw.R): a labelGrob() of "a" (or the
# label) at (hjust, vjust) npc of the key, raised by the descent of
# "gjpqyQ" in the key's face at a fontsize of `size` (font_descent() is
# given the size in mm as points); the key's size is the text child's
# (titleGrob()) width and height, its padding taken in the device's default
# gpar (fontsize 12, lineheight 1.2) as convertWidth() sees it outside the
# label's viewport, while drawing takes it in the label's fontsize. Rotated
# keys decline. The mark is a label layer of one label in the key's npc.
legend_label_glyph <- function(data, params, res) {
  data <- unclass(data)
  label <- data$label %||% "a"
  if (is.factor(label)) label <- as.character(label)
  if (!identical(as.numeric(data$angle %||% 0), 0) || length(label) != 1 || !is.character(label) || is.na(label) ||
    grepl("\n", label, fixed = TRUE)) {
    layout_decline("a rotated or unusual label key")
  }
  hjust <- gg_compute_just(data$hjust %||% 0.5)
  vjust <- gg_compute_just(data$vjust %||% 0.5)
  family <- data$family %||% ""
  face <- text_face(data$fontface %||% 1)
  fontsize <- (data$size %||% 3.88) * ggplot2::.pt
  pad_u <- params$label.padding %||% grid::unit(0.25, "lines")
  r_u <- params$label.r %||% grid::unit(0.15, "lines")
  pad <- label_unit_px(pad_u, fontsize, res)
  pad0 <- label_unit_px(pad_u, 12, res)
  r <- label_unit_px(r_u, fontsize, res)[[1]]
  if (is.na(face) || is.null(pad) || is.null(pad0) || is.null(r) || !length(pad_u) %in% c(1, 4) || length(r_u) != 1) {
    layout_decline("a label key alot doesn't draw")
  }
  pad <- rep(pad, length.out = 4)
  pad0 <- rep(pad0, length.out = 4)
  # font_descent() of the key's raise is called with the size in mm as
  # its fontsize (points), and the key's face.
  m <- text_metrics(c(label, "gjpqyQ", "gjpqyQ"), family, c(face, 1L, face), fontsize = c(fontsize, fontsize, data$size %||% 3.88), res = res)
  if (anyNA(unlist(m))) {
    layout_decline("label key text alot doesn't measure as ragg does")
  }
  d <- m$descent[2]
  key_d <- m$descent[3]
  font <- text_fonts(family, face)
  if (is.na(font$path) || !all(rs_text_covered(enc2utf8(label), font$path, as.integer(font$index)))) {
    layout_decline("a label key font or glyph alot doesn't draw")
  }
  g <- label_geometry(m$width[1], m$height[1], d, pad, r, hjust, vjust, 0)
  size0 <- label_geometry(m$width[1], m$height[1], d, pad0, r, hjust, vjust, 0)
  lwd <- data$linewidth %||% 0.25
  border <- if (isTRUE(all.equal(lwd, 0))) NA else params$border.colour %||% data$colour %||% "black"
  box <- g$boxes[[1]]
  nv <- length(box$x)
  marks <- path_marks(1L, 1, nv, rep(hjust, nv), rep(vjust, nv), border, NA, lwd, data$linetype %||% 1L, 1L,
    fill = data$fill %||% "white", fill_alpha = data$alpha %||% NA
  )
  colour <- point_colours(as.character(params$text.colour %||% data$colour %||% "black"), NA)
  if (is.null(colour)) {
    layout_decline("a label key colour alot doesn't parse")
  }
  boxes <- list(
    x = marks$x, y = marks$y, colour = marks$colour, lwd = marks$lwd, lty = marks$lty, closed = marks$closed, fill = marks$fill,
    x_range = c(0, 1), y_range = c(0, 1), cap = 0, join = 0, mitre = 10, res = res,
    dx = as.double(box$x), dy = as.double(box$y - key_d), rows = list(seq_len(nv)), path_rows = list(rep(0L, nv))
  )
  text <- list(
    label = enc2utf8(label), x = as.double(hjust), y = as.double(vjust), hjust = as.double(hjust), vjust = as.double(vjust),
    rot = 0, font = 1L, font_path = font$path, font_index = as.integer(font$index), size = fontsize * res / 72,
    line = 1.2 * 1.2 * fontsize * res / 72, colour = colour, rows = list(1L), dx = g$dx, dy = g$dy - key_d
  )
  list(mark = list(type = "label", boxes = boxes, text = text), size = c(size0$width, size0$height))
}
