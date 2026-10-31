# The legend boxes of the full tier (TASKS.md R5.3): what the Rust legend
# module (alot-core/src/render/legend.rs) needs to measure, lay out and draw
# the guides of a plot, resolved once per guide from the theme in O(breaks)
# R work. Rust assembles the gtables.
#
# Mirrors Guides$assemble(), $draw() and $package_box() (ggplot2
# R/guides-.R), Guide$draw() (R/guide-.R), GuideLegend (R/guide-legend.R),
# GuideColourbar (R/guide-colorbar.R) and draw_key_point() (R/legend-draw.R).
# Guides' own setup_params() and setup_elements() resolve the theme; the
# rest is mirrored, not called, since it builds grobs measured on a device.
# Only guide_legend() with point keys and guide_colourbar() are drawn; other
# guides, positions and settings decline.

# Pixels of a unit on a device of `res` pixels per inch, where grid
# converts it outside any viewport: `lines` and `char` follow the device's
# default gpar (layout_px()). `null` units stretch the guide, which
# declines.
legend_px <- function(u, res) {
  if (is.null(u)) {
    return(NULL)
  }
  if (!grid::is.unit(u)) {
    layout_decline("a legend size that is not a unit")
  }
  if (any(grid::unitType(u) == "null")) {
    layout_decline("a stretched legend")
  }
  layout_px(u, res)
}

# Legend justification as valid.just() reads it: two numbers (x, y).
legend_just <- function(just) {
  out <- tryCatch(as.numeric(grid::valid.just(just)), error = function(e) NULL)
  if (length(out) != 2 || anyNA(out)) {
    layout_decline("a legend justification alot doesn't read")
  }
  out
}

# A guide title or label's text element, with the labels as titleGrob()
# measures them (layout_title()), one item per label for `legend_labels()`.
legend_text <- function(element, label, res, mx, my) {
  element <- as_element(element)
  if (layout_blank(element)) {
    return(NULL)
  }
  layout_title(element, label, res, mx = mx, my = my)
}

# One titleGrob() per label: GuideLegend$build_labels().
legend_labels <- function(element, labels, res) {
  item <- legend_text(element, labels, res, TRUE, TRUE)
  if (is.null(item)) {
    return(list())
  }
  lapply(seq_along(labels), function(i) {
    one <- item
    one$w <- item$w[i]
    one$h <- item$h[i]
    one$label <- item$label[i]
    one
  })
}

# draw_key_point() (ggplot2 R/legend-draw.R) for one key as a PointLayer
# (alot-core/src/render/panel.rs) of one point at the centre of a unit
# square, and the key's size in pixels as set_key_size() sets it. NULL where
# the layer draws nothing for this key.
legend_point_key <- function(data, res) {
  if (!isTRUE(data$.draw %||% TRUE)) {
    return(list(mark = NULL, size = c(0, 0)))
  }
  shape <- gg_translate_shape_string(data$shape %||% 19)
  size <- data$size %||% 1.5
  stroke <- data$stroke %||% 0.5
  if (!is.numeric(shape) || anyNA(c(size, stroke, shape)) || length(shape) != 1) {
    layout_decline("a point key with missing aesthetics")
  }
  colour <- point_colours(as.character(data$colour %||% "black"), data$alpha %||% NA)
  fill <- point_colours(as.character(data$fill %||% "black"), data$alpha %||% NA)
  if (is.null(colour) || is.null(fill) || length(colour) != 1 || length(fill) != 1) {
    layout_decline("a point key colour alot doesn't parse")
  }
  mark <- list(
    x = 0.5, y = 0.5, x_range = c(0, 1), y_range = c(0, 1), shape = as.double(shape), size = as.double(size),
    stroke = as.double(stroke), colour = colour, fill = fill, consts = c(ggplot2::.pt, ggplot2::.stroke, res)
  )
  # set_key_size(): (size + linewidth) / 10 cm.
  cm <- (size + (data$linewidth %||% 0)) / 10
  list(mark = mark, size = rep(cm / 2.54 * res, 2))
}

# A theme_calc() state (R/render-ir.R) over `elements`, a list of theme
# elements, as resolve_theme_fast() sets it up for `theme`.
legend_state <- function(theme, elements) {
  st <- new.env(hash = TRUE, parent = emptyenv())
  st$theme <- theme
  st$elements <- elements
  st$tree <- ggplot2::get_element_tree()
  st$memo <- new.env(hash = TRUE, parent = emptyenv())
  st$memo_skip <- new.env(hash = TRUE, parent = emptyenv())
  st$combine <- gg("combine_elements")
  st$defaults <- gg("ggplot_global")$theme_default
  st
}

# The text element `name` as GuideLegend$setup_elements() resolves it: the
# theme's `text` element gets the guide's default justification and margin,
# which `name` inherits unless it or its parents set their own.
legend_text_element <- function(name, theme, elements, hjust, vjust, margin) {
  text <- as_element(elements[["text"]])
  text$hjust <- hjust
  text$vjust <- vjust
  text$margin <- margin
  elements[["text"]] <- text
  theme_calc(name, legend_state(theme, elements), FALSE)
}

# Guide$setup_elements() with GuideLegend's and GuideColourbar's
# setup_elements() (ggplot2 R/guide-.R, R/guide-legend.R,
# R/guide-colorbar.R) on resolved property lists instead of S7 elements,
# which is the same resolution at a tenth of the cost. A guide with its own
# `theme` uses the guide's own method.
legend_elements <- function(guide, params, theme) {
  if (!is.null(params$theme)) {
    return(guide$setup_elements(params, guide$elements, theme))
  }
  elements <- S7::S7_data(theme)
  vertical <- identical(params$direction, "vertical")
  bar <- inherits(guide, "GuideColourbar")
  if (bar) {
    # Defaults, so that a guide's own theme can still overrule them.
    if (vertical) {
      elements[["legend.key.height"]] <- (elements[["legend.key.height"]] %||% ggplot2::rel(1)) * 5
    } else {
      elements[["legend.key.width"]] <- (elements[["legend.key.width"]] %||% ggplot2::rel(1)) * 5
    }
    valid <- if (vertical) c("right", "left") else c("bottom", "top")
    elements[["legend.text.position"]] <- elements[["legend.text.position"]] %||% valid[1]
    elements[["legend.ticks"]] <- elements[["legend.ticks"]] %||% params$default_ticks
    elements[["legend.frame"]] <- elements[["legend.frame"]] %||% params$default_frame
  }
  text_position <- elements[["legend.text.position"]] %||% "right"
  title_position <- elements[["legend.title.position"]] %||% if (vertical) "top" else "left"
  positions <- c("top", "right", "bottom", "left")
  if (!text_position %in% positions || !title_position %in% positions) {
    layout_decline("a legend text or title position alot doesn't read")
  }
  if (bar && !text_position %in% if (vertical) c("right", "left") else c("bottom", "top")) {
    layout_decline("a colourbar text position that ggplot2 rejects")
  }
  gap <- theme_calc("legend.key.spacing", legend_state(theme, elements), FALSE)
  # For backward compatibility, vertical guides have no spacing between keys.
  if (vertical) {
    elements[["legend.key.spacing.y"]] <- elements[["legend.key.spacing.y"]] %||% grid::unit(0, "pt")
  }
  state <- legend_state(theme, elements)
  calc <- function(name) theme_calc(name, state, FALSE)
  margin <- calc("text")$margin
  title_margin <- gg("position_margin")(title_position, margin, gap)
  text_margin <- gg("position_margin")(text_position, margin, gap)
  text <- switch(text_position, top = c(0.5, 0), bottom = c(0.5, 1), left = c(1, 0.5), c(0, 0.5))
  list(
    background = calc("legend.background"), margin = calc("legend.margin"), key = calc("legend.key"),
    key_height = calc("legend.key.height"), key_width = calc("legend.key.width"),
    key_just = calc("legend.key.justification"), spacing_x = calc("legend.key.spacing.x"),
    spacing_y = calc("legend.key.spacing.y"), byrow = calc("legend.byrow"),
    ticks = if (bar) calc("legend.ticks"), ticks_length = if (bar) calc("legend.ticks.length"),
    frame = if (bar) calc("legend.frame"),
    title = legend_text_element("legend.title", theme, elements, 0, 0.5, title_margin),
    text = legend_text_element("legend.text", theme, elements, text[1], text[2], text_margin),
    text_position = text_position, title_position = title_position
  )
}

# The gtable pieces every guide shares (GuideLegend$setup_elements() and
# $override_elements()): the title and background.
legend_common <- function(elems, res, title) {
  if (!is.null(elems$key_just)) {
    layout_decline("legend.key.justification")
  }
  title_position <- elems$title_position
  title_el <- as_element(elems$title)
  just <- if (layout_blank(title_el)) c(0, 0.5) else unlist(gg("rotate_just")(element = title_el)[c("hjust", "vjust")])
  list(
    title = if (!is.null(title)) legend_text(elems$title, title, res, TRUE, TRUE),
    title_position = title_position, title_just = as.numeric(just), text_position = elems$text_position,
    padding = legend_px(elems$margin %||% ggplot2::margin(), res),
    background = full_rect(as_element(elems$background), res)
  )
}

# GuideLegend$draw() with draw_key_point() keys.
legend_guide <- function(guide, params, theme, res) {
  keys <- params$key
  n <- params$n_breaks
  elems <- legend_elements(guide, params, theme)
  if (!is.null(params$angle) && !inherits(params$angle, "waiver")) {
    layout_decline("legend label angle")
  }
  if (is.null(n) || n < 1 || is.null(params$decor) || is.data.frame(params$decor)) {
    layout_decline("a legend without keys")
  }
  key_size <- c(legend_px(elems$key_width, res), legend_px(elems$key_height, res))
  # build_decor(): per key, the layers' glyphs and the key's size.
  marks <- vector("list", n)
  size <- matrix(key_size, nrow = 2, ncol = n)
  for (dec in params$decor) {
    f <- environment(dec$draw_key)$f %||% dec$draw_key
    if (!identical(f, gg("draw_key_point"))) {
      layout_decline("a legend key other than draw_key_point()")
    }
    for (i in seq_len(n)) {
      k <- legend_point_key(vctrs::vec_slice(dec$data, i), res)
      if (!is.null(k$mark)) marks[[i]] <- c(marks[[i]], list(k$mark))
      size[, i] <- pmax(size[, i], k$size)
    }
  }
  labels <- if (length(keys$.label) > 0) legend_labels(elems$text, keys$.label, res) else list()
  c(
    list(
      kind = "legend", dim = as.numeric(c(params$nrow, params$ncol)), byrow = as.numeric(isTRUE(elems$byrow)),
      key_w = size[1, ], key_h = size[2, ], default = key_size, key_bg = full_rect(as_element(elems$key), res),
      marks = marks, labels = labels,
      spacing = c(legend_px(elems$spacing_x, res), legend_px(elems$spacing_y, res))
    ),
    legend_common(elems, res, params$title)
  )
}

# GuideColourbar$draw() for the default raster display.
legend_bar <- function(guide, params, theme, res) {
  if (!identical(params$display, "raster") || !is.data.frame(params$decor)) {
    layout_decline("a colourbar that is not a raster")
  }
  if (!is.null(params$angle) && !inherits(params$angle, "waiver")) {
    layout_decline("legend label angle")
  }
  elems <- legend_elements(guide, params, theme)
  vertical <- identical(params$direction, "vertical")
  key <- params$key
  colours <- point_colours(params$decor$colour, NA)
  if (is.null(colours)) {
    layout_decline("a colourbar colour alot doesn't parse")
  }
  bar <- c(legend_px(elems$key_width, res), legend_px(elems$key_height, res))
  # GuideColourbar$build_labels(): one titleGrob with the labels at the
  # breaks along the bar, flipped for a vertical bar.
  labels <- NULL
  if (length(key$.label) > 0) {
    labels <- legend_text(elems$text, key$.label, res, mx = vertical, my = !vertical)
    labels[[if (vertical) "y" else "x"]] <- as.numeric(key$.value)
  }
  # GuideColourbar$build_ticks(): both sides, drawn from the edge in.
  pos <- key$.value
  lim <- params$draw_lim %||% c(TRUE, TRUE)
  if (!lim[1]) pos <- pos[-1]
  if (!lim[2]) pos <- pos[-length(pos)]
  ticks <- NULL
  if (!layout_blank(as_element(elems$ticks)) && length(pos) > 0) {
    # `npc` lengths are shares of the bar across the ticks.
    across <- if (vertical) bar[1] else bar[2]
    unit_len <- rep(elems$ticks_length, length.out = 2)
    len <- vapply(seq_along(unit_len), function(i) {
      u <- unit_len[i]
      if (identical(grid::unitType(u), "npc")) as.numeric(u) * across else legend_px(u, res)
    }, numeric(1))
    ticks <- list(pos = as.numeric(pos), len = len, style = full_line(as_element(elems$ticks), res))
  }
  c(
    list(
      kind = "bar", bar_size = bar, horizontal = as.numeric(!vertical), image = colours,
      frame = full_rect(as_element(elems$frame), res, fill = NA), ticks = ticks, bar_labels = labels
    ),
    legend_common(elems, res, params$title)
  )
}

# Guides$assemble() (ggplot2 R/guides-.R): the boxes of the plot's legends
# by position, or NULL where there are none. Declines (layout_decline())
# where a guide or setting isn't mirrored.
legend_boxes <- function(built, res) {
  plot <- built@plot
  guides <- plot@guides
  theme <- plot@theme
  if (length(guides$guides) < 1) {
    return(NULL)
  }
  default_position <- theme$legend.position %||% "right"
  if (length(default_position) == 2 || identical(default_position, "inside")) {
    layout_decline("inside legends")
  }
  if (!default_position %in% c("top", "right", "bottom", "left")) {
    return(NULL)
  }
  direction <- theme$legend.direction
  built_guides <- list()
  for (j in seq_along(guides$guides)) {
    g <- guides$guides[[j]]
    params <- guides$params[[j]]
    if (inherits(g, "GuideNone")) next
    position <- params$position[1] %||% default_position
    if (!position %in% c("top", "right", "bottom", "left")) {
      layout_decline("inside legends")
    }
    # Guides$draw(): the direction follows the position unless set.
    params$position <- params$position %||% position
    params$direction <- params$direction %||% direction %||% if (position %in% c("top", "bottom")) "horizontal" else "vertical"
    params <- g$setup_params(params)
    class <- class(g)[1]
    spec <- if (ir_is_ggplot2(g, "GuideLegend")) {
      legend_guide(g, params, theme, res)
    } else if (ir_is_ggplot2(g, "GuideColourbar")) {
      legend_bar(g, params, theme, res)
    } else {
      layout_decline(paste("the", class, "guide"))
    }
    built_guides[[length(built_guides) + 1L]] <- list(position = position, spec = spec)
  }
  if (length(built_guides) == 0) {
    return(NULL)
  }
  spacing_default <- theme$legend.spacing %||% grid::unit(0.5, "lines")
  theme$legend.spacing <- spacing_default
  out <- list()
  for (position in c("right", "left", "bottom", "top")) {
    at <- Filter(function(b) identical(b$position, position), built_guides)
    if (length(at) == 0) next
    out[[position]] <- legend_box(lapply(at, `[[`, "spec"), position, theme, res)
  }
  out
}

# Guides$package_box() (ggplot2 R/guides-.R) for one position.
legend_box <- function(guides, position, theme, res) {
  direction <- if (position %in% c("top", "bottom")) "horizontal" else "vertical"
  box <- theme$legend.box %||% direction
  box_just <- legend_just(theme$legend.box.just %||% if (direction == "vertical") c("left", "top") else c("center", "top"))
  global <- legend_just(gg("calc_element")(paste0("legend.justification.", position), theme))
  margin <- legend_px(gg("calc_element")("legend.box.margin", theme) %||% ggplot2::margin(), res)
  if (any(margin != 0)) {
    layout_decline("legend.box.margin")
  }
  if (!layout_blank(as_element(theme$legend.box.background %||% ggplot2::element_blank()))) {
    layout_decline("legend.box.background")
  }
  spacing <- legend_px(gg("calc_element")(if (identical(box, "horizontal")) "legend.spacing.x" else "legend.spacing.y", theme), res)
  list(
    horizontal = as.numeric(identical(box, "horizontal")), spacing = spacing, box_just = box_just, global_just = global,
    guides = guides
  )
}
