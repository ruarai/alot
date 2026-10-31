# The input to the Rust page layout (alot-core/src/render/layout.rs) for a
# single-panel plot: the sizes ggplot_gtable() (ggplot2 R/plot-build.R)
# gives the rows and columns of its table, measured from the render IR's
# theme, labels and axis guides, with string metrics from text_metrics().
# Mirrors FacetNull$draw_panels() (R/facet-null.R), Facet$draw_labels()
# (R/facet-.R), GuideAxis$measure_grobs() (R/guide-axis.R), titleGrob()
# (R/margins.R) and table_add_tag() (R/plot-build.R).

# Where grid reads a unit that alot doesn't convert (relative and
# font-based units), layout_spec() declines the plot.
layout_decline <- function(reason) {
  stop(structure(class = c("alot_layout_decline", "condition"), list(message = reason, call = NULL)))
}

# Pixels of each element of a unit (or margin) on a device of `res` pixels
# per inch. grid's absolute units only; `lines`, `char`, `npc` and the like
# depend on the viewport and font, so they decline.
layout_px <- function(u, res) {
  if (is.null(u)) {
    return(NULL)
  }
  if (!grid::is.unit(u)) {
    layout_decline("a size that is not a unit")
  }
  type <- grid::unitType(u)
  per_inch <- c(
    points = 72.27, pt = 72.27, bigpts = 72, picas = 72.27 / 12, cm = 2.54, mm = 25.4,
    inches = 1, `in` = 1, inch = 1
  )
  scale <- per_inch[type]
  if (anyNA(scale) || !is.null(attr(u, "data"))) {
    layout_decline(paste("unit", paste(setdiff(type, names(per_inch)), collapse = ", ")))
  }
  as.numeric(u) / unname(scale) * res
}

# A resolved theme element is blank (or missing).
layout_blank <- function(el) {
  is.null(el) || is_blank_props(el)
}

# A titleGrob() (ggplot2 R/margins.R) as the Rust layout takes it: the
# metrics of each label in `element`'s font. `label` NULL gives NULL, a
# zeroGrob(). `mx` and `my`: whether the margin counts across x and y.
layout_title <- function(element, label, res, mx, my, angle = NULL, hjust = NULL, vjust = NULL) {
  if (is.null(label) || inherits(label, "waiver") || layout_blank(element)) {
    return(NULL)
  }
  if (!(is.character(label) || is.factor(label)) || anyNA(label)) {
    layout_decline("a label that is not plain text")
  }
  label <- as.character(label)
  if (is.na(ir_face(element$face))) {
    layout_decline("unsupported font face")
  }
  family <- element$family %||% ""
  face <- ir_face(element$face)
  # font_descent() measures "gjpqyQ" in the same family and size but, as it
  # is called with gp$fontface (which gpar() leaves unset: it stores `font`),
  # always in the plain face.
  m <- text_metrics(
    c(label, "gjpqyQ"), family, c(rep(face, length(label)), 1L), fontsize = element$size,
    lineheight = element$lineheight, res = res
  )
  if (anyNA(m$width) || anyNA(m$height)) {
    layout_decline("text alot doesn't measure as ragg does")
  }
  n <- length(label)
  margin <- layout_px(element$margin %||% ggplot2::margin(), res)
  angle <- as.numeric(angle %||% element$angle %||% 0)
  hjust <- as.numeric(hjust %||% element$hjust)
  vjust <- as.numeric(vjust %||% element$vjust)
  # What drawing the label needs (alot-core/src/render/title.rs): the font
  # file, ragg's size (fontsize * res / 72) and GEText()'s line height
  # (lineheight * 1.2 * fontsize * res / 72), the colour and titleGrob()'s
  # rotated justification.
  font <- text_fonts(family, face)
  colour <- point_colours(as.character(element$colour), NA)
  if (is.na(font$path) || is.null(colour) || length(colour) != 1) {
    layout_decline("a font or colour alot doesn't draw")
  }
  just <- gg("rotate_just")(angle, hjust, vjust)
  list(
    w = m$width[seq_len(n)], h = m$height[seq_len(n)], descent = m$descent[n + 1L],
    angle = angle, hjust = hjust, vjust = vjust, margin = margin, mx = as.numeric(mx), my = as.numeric(my),
    label = label, just = c(just$hjust, just$vjust), font_path = font$path, font_index = as.numeric(font$index),
    size = element$size * res / 72, line = element$lineheight * 1.2 * element$size * res / 72,
    colour = colour, check_overlap = 0
  )
}

# label_angle_heuristic() (ggplot2 R/guide-axis.R): the angle, hjust and
# vjust an axis guide's `angle` gives its labels.
layout_label_angle <- function(position, angle) {
  radian <- angle * pi / 180
  cosine <- sign(round(cos(radian), 3)) / 2 + 0.5
  sine <- sign(round(sin(radian), 3)) / 2 + 0.5
  list(
    angle = angle,
    hjust = switch(position, left = cosine, right = 1 - cosine, top = 1 - sine, sine),
    vjust = switch(position, left = 1 - sine, right = sine, top = 1 - cosine, cosine)
  )
}

# The axis at `position` as GuideAxis$draw() builds it: the tick lengths
# and one titleGrob() per dodge row or column of labels. NULL for no axis.
layout_axis <- function(ir, built, position, res) {
  scale <- ir$scales[[1]]
  at <- Filter(function(a) identical(a$position, position), scale$axes)
  if (length(at) == 0) {
    return(NULL)
  }
  if (length(at) > 1) {
    layout_decline("more than one axis guide at a position")
  }
  a <- at[[1]]
  key <- a$key
  if (!is.data.frame(key) || nrow(key) == 0) {
    layout_decline("an axis without breaks")
  }
  vertical <- position %in% c("left", "right")
  aes <- if (vertical) "y" else "x"
  suffix <- paste(aes, position, sep = ".")
  theme <- ir$theme
  text <- theme[[paste0("axis.text.", suffix)]]
  ticks <- theme[[paste0("axis.ticks.", suffix)]]
  major <- layout_px(theme[[paste0("axis.ticks.length.", suffix)]], res)
  if (layout_blank(ticks)) {
    major <- 0
  }
  minor <- NULL
  if (isTRUE(a$minor.ticks) && !layout_blank(theme[[paste0("axis.minor.ticks.", suffix)]])) {
    minor <- layout_px(theme[[paste0("axis.minor.ticks.length.", suffix)]], res)
  }
  if (!is.null(a$angle) && !inherits(a$angle, "waiver") && !layout_blank(text)) {
    h <- layout_label_angle(position, a$angle)
    text$angle <- h$angle
    text$hjust <- h$hjust
    text$vjust <- h$vjust
  }
  draw <- built@layout$panel_params[[1]]$draw_labels[[position]]
  labels <- character()
  if (".type" %in% names(key)) {
    type <- key$.type
  } else {
    type <- rep("major", nrow(key))
  }
  major_key <- key[type == "major", , drop = FALSE]
  if (!isFALSE(draw)) {
    labels <- major_key$.label
    if (is.expression(labels) || is.list(labels)) {
      layout_decline("axis labels that are not plain text")
    }
    labels <- as.character(labels)
  }
  items <- list()
  if (length(labels) > 0) {
    # GuideAxis$build_labels() and draw_axis_labels() (R/guide-axis.R):
    # labels dodge round-robin; check.overlap draws each group in
    # axis_label_priority() order.
    n_dodge <- a$n.dodge %||% 1
    check <- isTRUE(a$check.overlap)
    groups <- unname(split(seq_along(labels), rep(seq_len(n_dodge), length.out = length(labels))))
    items <- lapply(groups, function(i) {
      if (check) {
        i <- i[gg("axis_label_priority")(length(i))]
      }
      item <- layout_title(text, labels[i], res, mx = vertical, my = !vertical)
      if (!is.null(item)) {
        item[[aes]] <- as.numeric(major_key[[aes]][i])
        item$check_overlap <- as.numeric(check)
      }
      item
    })
    items <- Filter(Negate(is.null), items)
  }
  # Drawing: GuideAxis$assemble_drawing() justifies the labels by the text
  # element's rotated hjust (vertical axes) or vjust, and build_ticks() and
  # build_decor() draw the ticks and the axis line.
  just <- 0.5
  if (!layout_blank(text)) {
    just <- gg("rotate_just")(element = text)[[if (vertical) "hjust" else "vjust"]]
  }
  tick_set <- function(element, len, rows) {
    if (layout_blank(element) || is.null(len)) {
      return(NULL)
    }
    style <- full_line(element, res)
    if (is.null(style)) {
      return(NULL)
    }
    list(pos = as.numeric(key[[aes]][rows]), len = len, style = style)
  }
  list(
    major = major, minor = minor, items = items, side = position, just = as.numeric(just),
    line = full_line(theme[[paste0("axis.line.", suffix)]], res),
    ticks = tick_set(ticks, major, type == "major"),
    minor_ticks = if (!is.null(minor)) tick_set(theme[[paste0("axis.minor.ticks.", suffix)]], minor, type == "minor")
  )
}

# The spec of the Rust layout (see rs_layout()) for the plot `built`, on a
# device of `res` pixels per inch, or NULL with the reason as the
# "reason" attribute where alot doesn't lay the plot out. `legends` gives
# the sizes of the plot's legend boxes until their layout is mirrored: a
# list of c(width, height) in pixels named by position (right, left,
# bottom, top); NULL if the plot's legends are not sized.
layout_spec <- function(built, ir, res, legends = NULL) {
  tryCatch(
    layout_spec_(built, ir, res, legends),
    alot_layout_decline = function(e) structure(list(), reason = conditionMessage(e), class = "alot_layout_declined")
  )
}

layout_spec_ <- function(built, ir, res, legends) {
  plot <- built@plot
  layout <- built@layout
  theme <- ir$theme
  if (ir$facet$class != "FacetNull") {
    layout_decline("more than one panel")
  }
  if (!ir$coord$class %in% c("CoordCartesian", "CoordFlip", "CoordFixed", "CoordTransform")) {
    layout_decline("coord not laid out")
  }
  if (!is.null(theme[["panel.widths"]]) || !is.null(theme[["panel.heights"]])) {
    layout_decline("fixed panel sizes")
  }
  if (is.null(legends) && length(ir$legends) > 0) {
    layout_decline("legend layout is not mirrored yet")
  }

  aspect <- plot@theme$aspect.ratio %||% layout$coord$aspect(layout$panel_params[[1]])
  spec <- list(
    aspect = if (is.null(aspect)) NA_real_ else as.numeric(aspect),
    axis_l = layout_axis(ir, built, "left", res), axis_r = layout_axis(ir, built, "right", res),
    axis_t = layout_axis(ir, built, "top", res), axis_b = layout_axis(ir, built, "bottom", res)
  )

  # Layout$render(): the axis titles, [[1]] top or left, [[2]] bottom or right.
  labels <- layout$coord$labels(
    list(
      x = layout$resolve_label(layout$panel_scales_x[[1]], plot@labels),
      y = layout$resolve_label(layout$panel_scales_y[[1]], plot@labels)
    ),
    layout$panel_params[[1]]
  )
  axis_title <- function(label, element, mx, my) {
    if (is.null(label) || inherits(label, "waiver")) NULL else layout_title(theme[[element]], label, res, mx, my)
  }
  spec$xlab_t <- axis_title(labels$x[[1]], "axis.title.x.top", FALSE, TRUE)
  spec$xlab_b <- axis_title(labels$x[[2]], "axis.title.x.bottom", FALSE, TRUE)
  spec$ylab_l <- axis_title(labels$y[[1]], "axis.title.y.left", TRUE, FALSE)
  spec$ylab_r <- axis_title(labels$y[[2]], "axis.title.y.right", TRUE, FALSE)

  for (pos in c("right", "left", "bottom", "top")) {
    spec[[paste0("legend_", pos)]] <- legends[[pos]]
  }
  spacing <- layout_px(theme[["legend.box.spacing"]] %||% grid::unit(0.2, "cm"), res)
  spec$legend_spacing <- spacing
  spec$legend_plot <- as.numeric(identical(theme[["legend.location"]], "plot"))

  spec$title <- layout_title(theme[["plot.title"]], plot@labels$title, res, TRUE, TRUE)
  spec$subtitle <- layout_title(theme[["plot.subtitle"]], plot@labels$subtitle, res, TRUE, TRUE)
  spec$caption <- layout_title(theme[["plot.caption"]], plot@labels$caption, res, TRUE, TRUE)
  spec$title_plot <- as.numeric(identical(theme[["plot.title.position"]] %||% "panel", "plot"))
  spec$caption_plot <- as.numeric(identical(theme[["plot.caption.position"]] %||% "panel", "plot"))
  spec$tag <- layout_tag(theme, plot@labels$tag, res)

  spec$margin <- layout_px(theme[["plot.margin"]] %||% ggplot2::margin(), res)
  spec$background <- as.numeric(!is.null(plot@theme$plot.background))
  # NULL entries are absent from a list, so zeroGrobs are missing keys.
  spec[!vapply(spec, is.null, logical(1))]
}

# table_add_tag() (ggplot2 R/plot-build.R): the tag's size and where the
# table puts it.
layout_tag <- function(theme, label, res) {
  element <- theme[["plot.tag"]]
  if (length(label) < 1 || layout_blank(element)) {
    return(NULL)
  }
  position <- theme[["plot.tag.position"]] %||% "topleft"
  location <- theme[["plot.tag.location"]] %||% if (is.numeric(position)) "plot" else "margin"
  if (is.numeric(position)) {
    if (location == "margin") {
      layout_decline("a numeric tag position in the margin")
    }
    flags <- rep(FALSE, 4)
  } else {
    if (!position[1] %in% c("topleft", "top", "topright", "left", "right", "bottomleft", "bottom", "bottomright")) {
      layout_decline("an unknown tag position")
    }
    flags <- c(
      position %in% c("topleft", "top", "topright"), position %in% c("topleft", "left", "bottomleft"),
      position %in% c("topright", "right", "bottomright"), position %in% c("bottomleft", "bottom", "bottomright")
    )
  }
  item <- layout_title(element, label, res, TRUE, TRUE)
  list(
    item = item, top = as.numeric(flags[1]), left = as.numeric(flags[2]), right = as.numeric(flags[3]),
    bottom = as.numeric(flags[4]), location = match(location, c("margin", "plot", "panel")) - 1
  )
}

# The boxes (name, x0, y0, x1, y1, in device pixels from the top left) of
# the cells of a single-panel plot's table on a page of `width` × `height`
# pixels at `res` pixels per inch, or NULL with a "reason" attribute where
# alot doesn't lay the plot out.
layout_boxes_rust <- function(built, width, height, res, ir = render_ir(built), legends = NULL) {
  spec <- layout_spec(built, ir, res, legends)
  if (inherits(spec, "alot_layout_declined")) {
    return(structure(list(), reason = attr(spec, "reason")))
  }
  out <- rs_layout(spec, c(width, height))
  as.data.frame(out)
}
