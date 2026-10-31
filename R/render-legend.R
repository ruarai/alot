# The legend boxes of the full tier (TASKS.md R5.3, R6.4): what the Rust legend
# module (alot-core/src/render/legend.rs) needs to measure, lay out and draw
# the guides of a plot, resolved once per guide from the theme in O(breaks)
# R work. Rust assembles the gtables.
#
# Mirrors Guides$assemble(), $draw() and $package_box() (ggplot2
# R/guides-.R), Guide$draw() (R/guide-.R), GuideLegend (R/guide-legend.R),
# GuideColourbar (R/guide-colorbar.R), GuideColoursteps
# (R/guide-colorsteps.R), GuideBins (R/guide-bins.R) and the draw_key
# functions of the geoms the full tier draws (R/legend-draw.R). Guides' own
# setup_params() and setup_elements() resolve the theme; the rest is
# mirrored, not called, since it builds grobs measured on a device. Other
# guides, keys and settings decline.

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

# One titleGrob() per label: GuideLegend$build_labels(). With `na`, a
# missing label (an NA break's) is the string "NA", as grid measures and
# draws it; otherwise it declines.
legend_labels <- function(element, labels, res, na = FALSE) {
  missing <- is.na(labels)
  if (na && any(missing) && (is.character(labels) || is.factor(labels))) {
    labels <- as.character(labels)
    labels[missing] <- "NA"
  }
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

# set_key_size() (ggplot2 R/guide-legend.R): a key's size in cm, from the
# glyph's own size (`own`, both dimensions) or the data's size and
# linewidth, else the default.
legend_key_cm <- function(data, own = NULL, default = NULL) {
  if (!is.null(own)) {
    return(own)
  }
  if (is.null(data$size) && is.null(data$linewidth)) {
    return(default)
  }
  size <- data$size %||% 0
  linewidth <- data$linewidth %||% 0
  size <- if (is.na(size)[1]) 0 else size[1]
  linewidth <- if (is.na(linewidth)[1]) 0 else linewidth[1]
  rep((size + linewidth) / 10, 2)
}

# One colour as point_colours() packs it, or a decline.
legend_colour <- function(colour, alpha = NA) {
  out <- point_colours(as.character(colour), alpha)
  if (is.null(out) || length(out) != 1) {
    layout_decline("a legend key colour alot doesn't parse")
  }
  out
}

# R's line type code of one key's line type, -1 for blank, or a decline.
legend_lty <- function(lty) {
  code <- lty_code(lty)
  if (is.null(code) || length(code) != 1) {
    layout_decline("a legend key line type alot doesn't draw")
  }
  code
}

# draw_key_point() (ggplot2 R/legend-draw.R) as a PointLayer
# (alot-core/src/render/panel.rs) of one point at the centre of a unit
# square.
legend_point_glyph <- function(data, res) {
  shape <- gg_translate_shape_string(data$shape %||% 19)
  size <- data$size %||% 1.5
  stroke <- data$stroke %||% 0.5
  if (!is.numeric(shape) || anyNA(c(size, stroke, shape)) || length(shape) != 1) {
    layout_decline("a point key with missing aesthetics")
  }
  list(
    type = "point", x = 0.5, y = 0.5, x_range = c(0, 1), y_range = c(0, 1), shape = as.double(shape), size = as.double(size),
    stroke = as.double(stroke), colour = legend_colour(data$colour %||% "black", data$alpha %||% NA),
    fill = legend_colour(data$fill %||% "black", data$alpha %||% NA), consts = c(ggplot2::.pt, ggplot2::.stroke, res)
  )
}

# draw_key_polygon() and draw_key_rect() (ggplot2 R/legend-draw.R): a
# rectGrob() centred in the key, `inset` pixels narrower and shorter
# (unit(1, "npc") - unit(lwd, "mm")), as Painter::rect_capped() draws it
# with the layer's lineend.
legend_rect_glyph <- function(fill, colour, lwd, lty, join, cap, inset, res) {
  join <- match(join, c("mitre", "round", "bevel")) - 1L
  cap <- match(cap, c("round", "butt", "square")) - 1L
  if (length(join) != 1 || is.na(join) || length(cap) != 1 || is.na(cap) || length(lwd) != 1 || is.na(lwd)) {
    layout_decline("a legend key rect alot doesn't draw")
  }
  lty <- if (lwd > 0) legend_lty(lty) else 0
  list(
    type = "rect", inset = as.double(inset), fill = fill, col = colour,
    lwd = lwd * ggplot2::.pt * (lty >= 0) * res / 96, lty = as.numeric(max(lty, 0)), join = as.numeric(join),
    cap = as.numeric(cap)
  )
}

# draw_key_text() (ggplot2 R/legend-draw.R): a titleGrob() of the label
# with margins of 0.1 lines on every side. Its size (the grob's, the key's
# `width` and `height`) takes the margins in the device's default gpar; the
# text's position takes them in the text's own, which cancel only for
# centred text, so other justifications decline, as do rotated keys.
legend_text_glyph <- function(data, res) {
  data <- unclass(data)
  data$label <- data$label %||% "a"
  data$angle <- data$angle %||% 0
  hjust <- gg_compute_just(data$hjust %||% 0.5)
  vjust <- gg_compute_just(data$vjust %||% 0.5)
  if (!identical(as.numeric(data$angle), 0) || !isTRUE(all.equal(c(hjust, vjust), c(0.5, 0.5)))) {
    layout_decline("a rotated or justified text key")
  }
  label <- data$label
  if (is.factor(label)) label <- as.character(label)
  element <- list(
    family = data$family %||% "", face = data$fontface %||% 1, size = (data$size %||% 3.88) * ggplot2::.pt,
    lineheight = 1.2, colour = "black", margin = ggplot2::margin_auto(0.1 * 12 * 1.2, unit = "bigpts")
  )
  item <- layout_title(element, label, res, TRUE, TRUE, angle = 0, hjust = 0.5, vjust = 0.5)
  if (length(item$label) != 1) {
    layout_decline("a text key alot doesn't draw")
  }
  covered <- rs_text_covered(enc2utf8(item$label), item$font_path, as.integer(item$font_index))
  if (!all(covered)) {
    layout_decline("glyph missing from the font in a text key")
  }
  item$colour <- legend_colour(data$colour %||% data$fill %||% "black", data$alpha %||% NA)
  item$label <- enc2utf8(item$label)
  # convertWidth(grobWidth()) and convertHeight(grobHeight()) of the grob.
  m <- item$margin
  size <- c(item$w + m[2] + m[4], item$h + item$descent + m[1] + m[3])
  list(mark = c(list(type = "text"), item), size = size)
}

# One key glyph: what Rust draws (NULL for nothing) and the key's size in
# pixels (build_decor()'s `width` and `height` attributes, after
# set_key_size()). `f` is the layer's draw_key function; others decline.
legend_glyph <- function(f, data, params, res, default_cm) {
  if (!isTRUE(data$.draw %||% TRUE)) {
    return(list(mark = NULL, size = c(0, 0)))
  }
  px <- function(cm) cm / 2.54 * res
  is_key <- function(name) identical(f, gg(paste0("draw_key_", name)))
  if (is_key("point")) {
    return(list(mark = legend_point_glyph(data, res), size = px(legend_key_cm(data, default = default_cm))))
  }
  if (is_key("blank")) {
    return(list(mark = NULL, size = px(legend_key_cm(data, default = default_cm))))
  }
  if (is_key("polygon")) {
    lwd <- data$linewidth %||% 0
    if (!is.numeric(lwd) || length(lwd) != 1 || is.na(lwd)) {
      layout_decline("a legend key linewidth alot doesn't draw")
    }
    mark <- legend_rect_glyph(
      fill = legend_colour(data$fill %||% "grey20", data$alpha %||% NA), colour = legend_colour(data$colour %||% NA),
      lwd = lwd, lty = data$linetype %||% 1, join = params$linejoin %||% "mitre",
      cap = params$lineend %||% "butt", inset = lwd / 25.4 * res, res = res
    )
    # The polygon's own size: lwd / 5 cm both ways.
    return(list(mark = mark, size = px(rep(lwd / 5, 2))))
  }
  if (is_key("rect")) {
    colour <- if (is.na(data$fill %||% NA)) data$colour else data$fill
    mark <- legend_rect_glyph(
      fill = legend_colour(colour %||% "grey20", data$alpha %||% NA), colour = legend_colour(NA),
      lwd = 0, lty = 1, join = "round", cap = "round", inset = 0, res = res
    )
    return(list(mark = mark, size = px(legend_key_cm(data, default = default_cm))))
  }
  # draw_key_path(): a segment across the middle; draw_key_timeseries(): a
  # zigzag polyline. Without a linetype, neither draws a line.
  line <- list(path = list(x = c(0.1, 0.9), y = c(0.5, 0.5)), timeseries = list(x = c(0, 0.4, 0.6, 1), y = c(0.1, 0.6, 0.4, 0.9)))
  for (name in names(line)) {
    if (!is_key(name)) next
    if (!is.null(params[["arrow"]])) {
      layout_decline("a legend key with an arrow")
    }
    lwd <- data$linewidth %||% 0.5
    lty <- legend_lty(data$linetype %||% 0)
    cap <- match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L
    join <- if (name == "path") 0L else match(params$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L
    if (!is.numeric(lwd) || length(lwd) != 1 || is.na(lwd) || length(cap) != 1 || is.na(cap) || length(join) != 1 || is.na(join)) {
      layout_decline("a legend key line alot doesn't draw")
    }
    mark <- if (lty >= 0) {
      c(line[[name]], list(
        type = "path", col = legend_colour(data$colour %||% data$fill %||% "black", data$alpha %||% NA),
        lwd = lwd * ggplot2::.pt * res / 96, lty = as.numeric(lty), cap = as.numeric(cap), join = as.numeric(join)
      ))
    }
    return(list(mark = mark, size = px(legend_key_cm(data, default = default_cm))))
  }
  if (is_key("text")) {
    return(legend_text_glyph(data, res))
  }
  # draw_key_smooth(): with `se`, a rect of alpha(fill, alpha) filling the
  # key, then draw_key_path() of the data with alpha 1.
  if (is_key("smooth")) {
    fill <- data$fill %||% "grey60"
    rect <- if (isTRUE(params$se)) {
      legend_rect_glyph(
        fill = legend_colour(fill, data$alpha %||% NA), colour = legend_colour(NA),
        lwd = 0, lty = 1, join = "round", cap = "round", inset = 0, res = res
      )
    }
    data$alpha <- 1
    path <- legend_glyph(gg("draw_key_path"), data, params, res, default_cm)
    return(list(marks = c(if (!is.null(rect)) list(rect), if (!is.null(path$mark)) list(path$mark)), size = path$size))
  }
  layout_decline("a legend key alot doesn't draw")
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
  # GuideBins$setup_elements() (ggplot2 R/guide-bins.R).
  bins <- inherits(guide, "GuideBins")
  if (bins) {
    valid <- if (vertical) c("right", "left") else c("bottom", "top")
    elements[["legend.text.position"]] <- elements[["legend.text.position"]] %||% valid[1]
    elements[["legend.axis.line"]] <- elements[["legend.axis.line"]] %||% params$default_axis
    elements[["legend.ticks"]] <- elements[["legend.ticks"]] %||% params$default_ticks
  }
  text_position <- elements[["legend.text.position"]] %||% "right"
  title_position <- elements[["legend.title.position"]] %||% if (vertical) "top" else "left"
  positions <- c("top", "right", "bottom", "left")
  if (!text_position %in% positions || !title_position %in% positions) {
    layout_decline("a legend text or title position alot doesn't read")
  }
  if ((bar || bins) && !text_position %in% if (vertical) c("right", "left") else c("bottom", "top")) {
    layout_decline("a colourbar or bins text position that ggplot2 rejects")
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
    ticks = if (bar || bins) calc("legend.ticks"), ticks_length = if (bar || bins) calc("legend.ticks.length"),
    axis_line = if (bins) calc("legend.axis.line"),
    frame = if (bar) calc("legend.frame"),
    title = legend_text_element("legend.title", theme, elements, 0, 0.5, title_margin),
    text = legend_text_element("legend.text", theme, elements, text[1], text[2], text_margin),
    text_position = text_position, title_position = title_position
  )
}

# The gtable pieces every guide shares (GuideLegend$setup_elements() and
# $override_elements()): the title and background.
legend_common <- function(elems, res, title) {
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

# GuideLegend$build_decor() (ggplot2 R/guide-legend.R) for the first `n`
# keys: per key, the layers' glyphs (legend_glyph()) and the key's size,
# the largest of its glyphs' and the default (NA sizes dropped), with the
# default key size, all in pixels. With legend.key.justification (`just`),
# each key is drawn in a viewport of its own size, justified in its cell.
legend_keys <- function(params, elems, n, res) {
  key_size <- c(legend_px(elems$key_width, res), legend_px(elems$key_height, res))
  marks <- vector("list", n)
  size <- matrix(key_size, nrow = 2, ncol = n)
  for (dec in params$decor) {
    f <- environment(dec$draw_key)$f %||% dec$draw_key
    for (i in seq_len(n)) {
      k <- legend_glyph(f, vctrs::vec_slice(dec$data, i), dec$params, res, key_size / res * 2.54)
      add <- k$marks %||% if (!is.null(k$mark)) list(k$mark)
      if (length(add)) marks[[i]] <- c(marks[[i]], add)
      size[, i] <- c(max(size[1, i], k$size[1], na.rm = TRUE), max(size[2, i], k$size[2], na.rm = TRUE))
    }
  }
  list(marks = marks, size = size, default = key_size, just = if (!is.null(elems$key_just)) legend_just(elems$key_just))
}

# Tick lengths in pixels: `npc` lengths are shares of `across`, the
# ticks' cell across them.
legend_tick_len <- function(unit_len, across, res) {
  vapply(seq_along(unit_len), function(i) {
    u <- unit_len[i]
    if (identical(grid::unitType(u), "npc")) as.numeric(u) * across else legend_px(u, res)
  }, numeric(1))
}

# GuideLegend$draw() with the keys of legend_glyph().
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
  k <- legend_keys(params, elems, n, res)
  labels <- if (length(keys$.label) > 0) legend_labels(elems$text, keys$.label, res, na = TRUE) else list()
  c(
    list(
      kind = "legend", dim = as.numeric(c(params$nrow, params$ncol)), byrow = as.numeric(isTRUE(elems$byrow)),
      key_w = k$size[1, ], key_h = k$size[2, ], default = k$default, key_bg = full_rect(as_element(elems$key), res),
      marks = k$marks, labels = labels, key_just = k$just,
      spacing = c(legend_px(elems$spacing_x, res), legend_px(elems$spacing_y, res))
    ),
    legend_common(elems, res, params$title)
  )
}

# GuideColourbar$draw() for the raster and rectangle displays, and
# GuideColoursteps (ggplot2 R/guide-colorsteps.R).
legend_bar <- function(guide, params, theme, res) {
  steps <- inherits(guide, "GuideColoursteps")
  if (!is.data.frame(params$decor) || !(steps || params$display %in% c("raster", "rectangles"))) {
    layout_decline("a colourbar drawn as a gradient")
  }
  if (!is.null(params$angle) && !inherits(params$angle, "waiver")) {
    layout_decline("legend label angle")
  }
  elems <- legend_elements(guide, params, theme)
  vertical <- identical(params$direction, "vertical")
  key <- params$key
  decor <- params$decor
  colours <- point_colours(as.character(decor$colour), NA)
  if (is.null(colours)) {
    layout_decline("a colourbar colour alot doesn't parse")
  }
  # GuideColourbar$build_decor() for `display = "rectangles"` and
  # GuideColoursteps$build_decor(): a rectGrob() of one rect per colour,
  # from `lo` to `hi` along the bar (npc from the bottom or left), without
  # an outline. NULL for the raster.
  rects <- NULL
  if (steps) {
    lo <- pmin(decor$min, decor$max)
    hi <- pmax(decor$min, decor$max)
    rects <- list(lo = as.double(lo), hi = as.double(hi))
  } else if (identical(params$display, "rectangles")) {
    n <- nrow(decor)
    rects <- list(lo = (seq_len(n) - 1) / n, hi = seq_len(n) / n)
  }
  if (!is.null(rects) && anyNA(c(rects$lo, rects$hi))) {
    layout_decline("a colour step alot doesn't place")
  }
  bar <- c(legend_px(elems$key_width, res), legend_px(elems$key_height, res))
  # GuideColourbar$build_labels(): one titleGrob with the labels at the
  # breaks along the bar, flipped for a vertical bar.
  labels <- NULL
  if (length(key$.label) > 0) {
    labels <- legend_text(elems$text, key$.label, res, mx = vertical, my = !vertical)
    if (!is.null(labels)) labels[[if (vertical) "y" else "x"]] <- as.numeric(key$.value)
  }
  # GuideColourbar$build_ticks(): both sides, drawn from the edge in.
  pos <- key$.value
  lim <- params$draw_lim %||% c(TRUE, TRUE)
  if (!lim[1]) pos <- pos[-1]
  if (!lim[2]) pos <- pos[-length(pos)]
  ticks <- NULL
  if (!layout_blank(as_element(elems$ticks)) && length(pos) > 0) {
    # `npc` lengths are shares of the bar across the ticks.
    len <- legend_tick_len(rep(elems$ticks_length, length.out = 2), if (vertical) bar[1] else bar[2], res)
    ticks <- list(pos = as.numeric(pos), len = len, style = full_line(as_element(elems$ticks), res))
  }
  c(
    list(
      kind = "bar", bar_size = bar, horizontal = as.numeric(!vertical), image = colours, rects = rects,
      frame = full_rect(as_element(elems$frame), res, fill = NA), ticks = ticks, bar_labels = labels
    ),
    legend_common(elems, res, params$title)
  )
}

# GuideBins$draw() (ggplot2 R/guide-bins.R): the keys stacked in one cell
# (all as large as the largest), an axis line along the labels' side,
# ticks at the bins' edges and one label grob with the labels at them, laid
# out as one break of GuideLegend.
legend_bins <- function(guide, params, theme, res) {
  key <- params$key
  vertical <- identical(params$direction, "vertical")
  elems <- legend_elements(guide, params, theme)
  if (!is.null(params$angle) && !inherits(params$angle, "waiver")) {
    layout_decline("legend label angle")
  }
  nkeys <- nrow(key) - 1L
  if (nkeys < 1 || is.null(params$decor) || is.data.frame(params$decor)) {
    layout_decline("a legend without keys")
  }
  k <- legend_keys(params, elems, nkeys, res)
  # build_decor(): measure_legend_keys() over the stack, every key then as
  # large as the largest.
  key_size <- c(max(k$size[1, ]), max(k$size[2, ]))
  show <- params$show.limits %||% c(FALSE, FALSE)
  value <- as.numeric(key$.value)
  if (vertical) value <- 1 - value
  # build_labels(): hidden limits get empty labels.
  labels <- NULL
  if (length(key$.label) > 0) {
    text <- key$.label
    text[c(1, length(text))[!show]] <- ""
    labels <- legend_text(elems$text, gg_validate_labels(text), res, mx = vertical, my = !vertical)
    if (!is.null(labels)) labels[[if (vertical) "y" else "x"]] <- value
  }
  side <- elems$text_position
  # build_ticks(): Guide$build_ticks() at the edges, from the labels' side
  # inward; hidden limits draw none.
  ticks <- NULL
  pos <- value
  pos[c(1, length(pos))[!show]] <- NA
  pos <- pos[!is.na(pos)]
  if (!layout_blank(as_element(elems$ticks)) && length(pos) > 0) {
    across <- if (vertical) key_size[1] else key_size[2]
    len <- legend_tick_len(elems$ticks_length %||% grid::unit(0.2, "npc"), across, res)[1]
    ticks <- list(pos = pos, len = len, style = full_line(as_element(elems$ticks), res))
  }
  c(
    list(
      kind = "bins", horizontal = as.numeric(!vertical), key_size = key_size, n = as.numeric(nkeys),
      key_bg = full_rect(as_element(elems$key), res), marks = k$marks, key_w = k$size[1, ], key_h = k$size[2, ],
      key_just = k$just, axis = full_line(as_element(elems$axis_line), res), ticks = ticks, bar_labels = labels
    ),
    legend_common(elems, res, params$title)
  )
}

# Guides$assemble() (ggplot2 R/guides-.R): the boxes of the plot's legends
# by position, or NULL where there are none. `inside` is a list of the
# boxes inside the panels, one per distinct position and justification.
# Declines (layout_decline()) where a guide or setting isn't mirrored.
legend_boxes <- function(built, res) {
  plot <- built@plot
  guides <- plot@guides
  theme <- plot@theme
  if (length(guides$guides) < 1) {
    return(NULL)
  }
  default_position <- theme$legend.position %||% "right"
  if (length(default_position) == 2) {
    default_position <- "inside"
  }
  trbl <- c("top", "right", "bottom", "left")
  if (!default_position %in% c(trbl, "inside")) {
    return(NULL)
  }
  direction <- theme$legend.direction
  default_inside_just <- gg("calc_element")("legend.justification.inside", theme)
  default_inside_position <- gg("calc_element")("legend.position.inside", theme)
  built_guides <- list()
  for (j in seq_along(guides$guides)) {
    g <- guides$guides[[j]]
    params <- guides$params[[j]]
    if (inherits(g, "GuideNone")) next
    position <- params$position[1] %||% default_position
    if (!position %in% c(trbl, "inside")) {
      layout_decline("a legend position alot doesn't read")
    }
    # The inside position and justification can be set per guide, by the
    # guide's own theme only.
    just <- coord <- NULL
    if (position == "inside") {
      just <- legend_just(params$theme[["legend.justification.inside"]] %||% default_inside_just)
      coord <- params$theme[["legend.position.inside"]] %||% default_inside_position %||% just
      coord <- as.numeric(coord)
      if (length(coord) != 2 || anyNA(coord)) {
        layout_decline("an inside legend position alot doesn't read")
      }
    }
    # Guides$draw(): the direction follows the position unless set.
    params$position <- params$position %||% position
    params$direction <- params$direction %||% direction %||% if (position %in% c("top", "bottom")) "horizontal" else "vertical"
    params <- g$setup_params(params)
    class <- class(g)[1]
    spec <- if (ir_is_ggplot2(g, "GuideLegend")) {
      legend_guide(g, params, theme, res)
    } else if (ir_is_ggplot2(g, c("GuideColourbar", "GuideColoursteps"))) {
      legend_bar(g, params, theme, res)
    } else if (ir_is_ggplot2(g, "GuideBins")) {
      legend_bins(g, params, theme, res)
    } else {
      layout_decline(paste("the", class, "guide"))
    }
    key <- paste(position, paste(just, collapse = " "), paste(coord, collapse = " "))
    built_guides[[length(built_guides) + 1L]] <- list(position = position, key = key, just = just, coord = coord, spec = spec)
  }
  if (length(built_guides) == 0) {
    return(NULL)
  }
  theme$legend.spacing <- theme$legend.spacing %||% grid::unit(0.5, "lines")
  out <- list()
  # vec_group_loc(): groups in order of first appearance.
  keys <- vapply(built_guides, `[[`, "", "key")
  for (k in unique(keys)) {
    at <- built_guides[keys == k]
    position <- at[[1]]$position
    box <- legend_box(lapply(at, `[[`, "spec"), position, theme, res, at[[1]]$just, at[[1]]$coord)
    if (position == "inside") {
      out$inside <- c(out$inside, list(box))
    } else {
      out[[position]] <- box
    }
  }
  out
}

# Guides$package_box() (ggplot2 R/guides-.R) for one position: the
# guides' arrangement, `legend.box.margin` and `legend.box.background`,
# and where the box sits: `legend.justification.<position>`, and for
# inside legends their position (`inside`, npc of the panel area).
legend_box <- function(guides, position, theme, res, inside_just = NULL, inside_position = NULL) {
  calc <- function(name) gg("calc_element")(name, theme)
  direction <- if (position %in% c("top", "bottom")) "horizontal" else "vertical"
  box <- theme$legend.box %||% direction
  box_just <- legend_just(theme$legend.box.just %||% if (direction == "vertical") c("left", "top") else c("center", "top"))
  global <- if (position == "inside") inside_just else legend_just(calc(paste0("legend.justification.", position)))
  margin <- legend_px(calc("legend.box.margin") %||% ggplot2::margin(), res)
  spacing <- legend_px(calc(if (identical(box, "horizontal")) "legend.spacing.x" else "legend.spacing.y"), res)
  list(
    horizontal = as.numeric(identical(box, "horizontal")), spacing = spacing, box_just = box_just, global_just = global,
    inside = if (position == "inside") as.double(inside_position), margin = margin,
    background = legend_box_background(theme$legend.box.background %||% ggplot2::element_blank(), res),
    guides = guides
  )
}

# element_grob() of `legend.box.background`, which package_box() takes
# from the theme as it is, unresolved: properties left NULL fall back to
# grid's defaults (black, lwd 1, solid, round joins) and the device's
# starting fill, its background (`fill_bg`).
legend_box_background <- function(el, res) {
  el <- as_element(el)
  if (layout_blank(el)) {
    return(NULL)
  }
  fill_bg <- is.null(el$fill)
  el$fill <- el$fill %||% NA
  el$colour <- el$colour %||% "black"
  el$linewidth <- el$linewidth %||% (1 / ggplot2::.pt)
  el$linetype <- el$linetype %||% 1
  el$linejoin <- el$linejoin %||% "round"
  c(full_rect(el, res), list(fill_bg = as.numeric(fill_bg)))
}
