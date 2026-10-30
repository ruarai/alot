# The render IR (PHASE2.md, Architecture 2): what the full tier's layout
# and drawers need from a built plot, gathered in O(k) R work plus borrowed
# layer columns. Building it also decides, per layer, guide, element and
# label, whether the full tier can draw the plot, with the reason when not.
# Mirrors the inputs ggplot_gtable() (ggplot2 R/plot-build.R) and
# Layout$render() (R/layout.R) draw from.

# Builds the IR of a built plot. Returns a list:
# - `theme`: every element of the element tree, resolved as calc_element()
#   would (see resolve_theme());
# - `fonts`: the distinct font styles of the theme's text elements and
#   their files (text_fonts());
# - `layers`: per layer its geom, drawer `kind`, data (borrowed) and
#   `reason` the full tier can't draw it (NA if it can);
# - `layout`: the facet layout data frame (borrowed);
# - `facet`, `coord`: class and the parameters the layout uses;
# - `scales`: per distinct (SCALE_X, SCALE_Y) pair, the panel ranges, the
#   grid's major and minor break positions (0-1) and the axis guides (keys
#   borrowed); `layout$scales` gives each panel's pair;
# - `strips`: the labeller's strip labels (Facet$format_strip_labels());
# - `labels`: title, subtitle, caption, tag and axis titles, as
#   Layout$render() and ggplot_gtable() resolve them;
# - `legends`: the plot's guides (`plot@guides$params`);
# - `support`: a data frame of `component`, `name` and `reason` for
#   everything the full tier can't draw (no rows if it can draw the plot).
render_ir <- function(built) {
  plot <- built@plot
  layout <- built@layout
  support <- ir_support()

  theme <- resolve_theme(plot@theme)
  for (n in names(theme)) {
    reason <- ir_element_decline(theme[[n]])
    if (!is.null(reason)) support$add("element", n, reason)
  }
  fonts <- ir_fonts(theme)
  if (anyNA(fonts$path)) {
    support$add("element", "fonts", "a text element's font is not one alot measures")
  }

  layers <- lapply(seq_along(plot@layers), function(i) {
    layer <- plot@layers[[i]]
    data <- suppressWarnings(hybrid_data(layer, built@data[[i]]))
    reason <- hybrid_decline(layer, data, layout)
    geom <- class(layer$geom)[1]
    if (!is.null(reason)) support$add("layer", geom, reason)
    list(geom = geom, kind = hybrid_kind(layer), data = data, reason = reason %||% NA_character_)
  })

  coord <- layout$coord
  coord_class <- class(coord)[1]
  coords <- c("CoordCartesian", "CoordFlip", "CoordFixed", "CoordTransform")
  if (!ir_is_ggplot2(coord, coords)) {
    support$add("coord", coord_class, "coord not in Phase 2 scope")
  }
  facet <- layout$facet
  facet_class <- class(facet)[1]
  if (!ir_is_ggplot2(facet, c("FacetNull", "FacetWrap", "FacetGrid"))) {
    support$add("facet", facet_class, "facet not in Phase 2 scope")
  }

  scales <- ir_scales(layout, support)
  strips <- facet$format_strip_labels(layout$layout, layout$facet_params)
  strip_text <- unlist(lapply(strips, function(s) lapply(s, ir_text, support, "strip")), use.names = FALSE)

  labels <- ir_labels(built, support)
  legends <- ir_legends(plot@guides, support)

  # A glyph missing from any of the plot's fonts sends it to the hybrid
  # tier, where ragg falls back to another font.
  text <- c(
    unlist(labels, use.names = FALSE), strip_text,
    unlist(lapply(scales, function(s) lapply(s$axes, function(a) ir_text(a$key$.label, support, "axis label"))), use.names = FALSE),
    unlist(lapply(legends, function(l) c(ir_text(l$title, support, "legend title"), ir_text(l$key$.label, support, "legend label"))), use.names = FALSE)
  )
  text <- unique(as.character(text[!is.na(text)]))
  for (k in which(!is.na(fonts$path))) {
    covered <- rs_text_covered(enc2utf8(text), fonts$path[k], fonts$index[k])
    if (!all(covered)) {
      support$add("text", fonts$path[k], sprintf("glyph missing from the font in \"%s\"", text[!covered][1]))
    }
  }

  layout_df <- layout$layout
  pair <- paste(layout_df$SCALE_X, layout_df$SCALE_Y)
  list(
    theme = theme,
    fonts = fonts,
    layers = layers,
    layout = list(panels = layout_df, scales = match(pair, unique(pair))),
    facet = list(class = facet_class, params = layout$facet_params[intersect(
      c("free", "space_free", "strip.position", "switch", "ncol", "nrow", "dir",
        "as.table", "draw_axes", "axis_labels", "margins"),
      names(layout$facet_params)
    )]),
    coord = list(
      class = coord_class, clip = coord$clip, expand = coord$expand,
      ratio = coord$ratio, reverse = coord$reverse
    ),
    scales = scales,
    strips = strips,
    labels = labels,
    legends = legends,
    support = support$get()
  )
}

# Collects (component, name, reason) rows.
ir_support <- function() {
  rows <- list()
  list(
    add = function(component, name, reason) {
      rows[[length(rows) + 1L]] <<- c(component, name, reason)
    },
    get = function() {
      m <- matrix(as.character(unlist(rows)), ncol = 3, byrow = TRUE)
      data.frame(component = m[, 1], name = m[, 2], reason = m[, 3])
    }
  )
}

# Whether ggproto object `x` is exactly one of ggplot2's classes `classes`
# (not an extension's subclass).
ir_is_ggplot2 <- function(x, classes) {
  cls <- class(x)[1]
  cls %in% classes && identical(class(x), class(get(cls, asNamespace("ggplot2"))))
}

# A label or key text as character, or NULL. Expressions and calls are
# plotmath, which the full tier doesn't draw.
ir_text <- function(x, support, what) {
  if (is.null(x) || inherits(x, "waiver")) {
    return(NULL)
  }
  if (is.character(x) || is.factor(x)) {
    return(as.character(x))
  }
  if (is.list(x) && all(vapply(x, function(v) is.character(v) && length(v) == 1, logical(1)))) {
    return(unlist(x))
  }
  support$add("text", what, "label is not plain text (plotmath or another type)")
  NULL
}

# Theme ------------------------------------------------------------------

# Every element of the element tree, resolved as calc_element() (ggplot2
# R/theme.R) would, but as plain property lists: calc_element() rebuilds
# S7 objects at every step of the inheritance, which costs about 50 ms per
# plot, and parents are shared, so each (element, skip_blank) is resolved
# once. Elements become lists of class "alot_element" with `.class` (the S7
# class name) and their properties; other values (units, margins,
# characters) are what calc_element() returns. Anything unusual (old S3
# elements, a child of another element class) uses calc_element() itself.
resolve_theme <- function(theme) {
  tree <- ggplot2::get_element_tree()
  names <- names(tree)
  out <- tryCatch(
    resolve_theme_fast(theme, tree, names),
    alot_slow_theme = function(e) NULL
  )
  out %||% stats::setNames(lapply(names, function(n) as_element(ggplot2::calc_element(n, theme))), names)
}

resolve_theme_fast <- function(theme, tree, names) {
  st <- new.env(hash = TRUE, parent = emptyenv())
  st$theme <- theme
  # The theme's elements as a plain list: `[[` on the S7 theme dispatches.
  st$elements <- S7::S7_data(theme)
  st$tree <- tree
  st$memo <- new.env(hash = TRUE, parent = emptyenv())
  st$memo_skip <- new.env(hash = TRUE, parent = emptyenv())
  st$combine <- gg("combine_elements")
  st$defaults <- gg("ggplot_global")$theme_default
  stats::setNames(lapply(names, theme_calc, st, FALSE), names)
}

# calc_element() for one (element, skip_blank), memoised in `st$memo`
# (`st$memo_skip` when skipping blanks).
theme_calc <- function(element, st, skip_blank) {
  memo <- if (skip_blank) st$memo_skip else st$memo
  hit <- memo[[element]]
  if (!is.null(hit)) {
    return(hit[[1]])
  }
  out <- theme_calc_one(element, st, skip_blank)
  assign(element, list(out), envir = memo)
  out
}

theme_calc_one <- function(element, st, skip_blank) {
  el <- st$elements[[element]]
  if (inherits(el, "ggplot2::element_blank")) {
    if (skip_blank) el <- NULL else return(as_element(el))
  }
  out <- as_element(el)
  pnames <- st$tree[[element]]$inherit
  if (is.null(pnames)) {
    # A root with no NULL property is returned as is; otherwise
    # calc_element() fills it from the default theme.
    null <- if (inherits(out, "alot_element")) lengths(out) == 0 else vapply(el, is.null, logical(1))
    if (!any(null)) {
      return(out)
    }
    # NULL properties come from ggplot2's default theme; element_geom()
    # may keep NULL colour and fill.
    if (inherits(out, "alot_element")) {
      out <- combine_props(out, as_element(st$defaults[[element]]), st$combine)
      null <- lengths(out) == 0
      if (identical(out$.class, "ggplot2::element_geom")) null[c("colour", "fill")] <- FALSE
      if (!any(null)) {
        return(out)
      }
    }
    return(as_element(ggplot2::calc_element(element, st$theme, skip_blank = skip_blank)))
  }
  skip_blank <- skip_blank || (!is.null(el) && !isTRUE(if (inherits(out, "alot_element")) out$inherit.blank))
  for (p in pnames) {
    out <- combine_props(out, theme_calc(p, st, skip_blank), st$combine)
  }
  out
}

slow_theme <- function() {
  stop(structure(class = c("alot_slow_theme", "error", "condition"), list(message = "", call = NULL)))
}

# An S7 theme element as a property list; other values unchanged. S7
# stores properties as attributes (absent when NULL), so they are read
# directly, in the class's property order (as S7::props() gives them).
as_element <- function(x) {
  if (inherits(x, "S7_object")) {
    if (!inherits(x, "ggplot2::element")) {
      return(x)
    }
    cls <- class(x)[1]
    props <- element_props[[cls]]
    if (is.null(props)) {
      props <- names(S7::S7_class(x)@properties)
      assign(cls, props, envir = element_props)
    }
    out <- attributes(x)[props]
    names(out) <- props
    return(structure(c(list(.class = cls), out), class = "alot_element"))
  }
  if (inherits(x, "element")) {
    slow_theme()
  }
  x
}

element_props <- new.env(parent = emptyenv())

is_blank_props <- function(x) inherits(x, "alot_element") && identical(x$.class, "ggplot2::element_blank")

# combine_elements() (ggplot2 R/theme.R) on property lists.
combine_props <- function(e1, e2, combine) {
  if (is.null(e2) || is_blank_props(e1)) {
    return(e1)
  }
  if (is.null(e1)) {
    return(e2)
  }
  el1 <- inherits(e1, "alot_element")
  el2 <- inherits(e2, "alot_element")
  if (!el1 && !el2) {
    return(combine(e1, e2))
  }
  if (!el1 || !el2) {
    slow_theme()
  }
  if (is_blank_props(e2)) {
    return(if (isTRUE(e1$inherit.blank)) e2 else e1)
  }
  if (!identical(e1$.class, e2$.class)) {
    slow_theme()
  }
  n <- names(e1)[lengths(e1) == 0]
  e1[n] <- unclass(e2)[n]
  if (inherits(e1$size, "rel")) {
    e1$size <- e2$size * unclass(e1$size)
  }
  if (inherits(e1$linewidth, "rel")) {
    e1$linewidth <- e2$linewidth * unclass(e1$linewidth)
  }
  if (identical(e1$.class, "ggplot2::element_text")) {
    # combine_elements() on margins only changes a margin with NAs.
    m1 <- e1$margin
    if (is.null(m1) || anyNA(m1)) {
      e1["margin"] <- list(combine(m1, e2$margin))
    }
  }
  e1
}

# Why the full tier can't use a resolved element or value, or NULL.
ir_element_decline <- function(x) {
  if (inherits(x, "alot_element")) {
    if (!x$.class %in% ir_element_classes) {
      return(paste("element class", x$.class))
    }
    if (identical(x$.class, "ggplot2::element_text")) {
      if (is.na(ir_face(x$face))) {
        return("unsupported font face")
      }
      if (!is.null(x$margin) && !inherits(x$margin, "simpleUnit") && is.null(ir_unit(x$margin))) {
        return("margin is not a simple unit")
      }
    }
    return(NULL)
  }
  if (grid::is.unit(x) && !inherits(x, "simpleUnit") && is.null(ir_unit(x))) {
    return("compound unit")
  }
  NULL
}

ir_element_classes <- paste0("ggplot2::element_", c("blank", "text", "line", "rect", "point", "polygon", "geom"))

# grid's font faces (gpar()'s fontface), or NA.
ir_face <- function(face) {
  if (is.numeric(face) && length(face) == 1 && face %in% 1:4) {
    return(as.integer(face))
  }
  if (is.character(face) && length(face) == 1 && face %in% names(ir_faces)) ir_faces[[face]] else NA_integer_
}

ir_faces <- c(plain = 1L, bold = 2L, italic = 3L, oblique = 3L, bold.italic = 4L)

# A simple unit as list(value, unit), or NULL for compound units.
ir_unit <- function(u) {
  if (inherits(u, "simpleUnit")) {
    return(list(value = as.numeric(u), unit = grid::unitType(u)))
  }
  type <- grid::unitType(u)
  if (!is.character(type) || any(type %in% c("sum", "min", "max")) || !is.null(attr(u, "data"))) {
    return(NULL)
  }
  list(value = as.numeric(u), unit = type)
}

# Distinct (family, face) of the theme's text elements and their files.
ir_fonts <- function(theme) {
  text <- theme[vapply(theme, function(x) identical(attr(x, "class"), "alot_element") && identical(x$.class, "ggplot2::element_text"), logical(1))]
  family <- vapply(text, function(x) x$family %||% "", character(1), USE.NAMES = FALSE)
  face <- vapply(text, function(x) ir_face(x$face), integer(1), USE.NAMES = FALSE)
  first <- !duplicated(paste(family, face, sep = "\r"))
  list2DF(c(list(family = family[first], face = face[first]), text_fonts(family[first], face[first])))
}

# Panels -----------------------------------------------------------------

# Per distinct (SCALE_X, SCALE_Y) pair: panel params depend only on the
# panel's scales (Coord$setup_panel_params()), so panels sharing a pair
# share them, and 400 fixed-scale panels cost one.
ir_scales <- function(layout, support) {
  df <- layout$layout
  pair <- paste(df$SCALE_X, df$SCALE_Y)
  first <- match(unique(pair), pair)
  axis_guides <- c("GuideAxis", "GuideNone")
  lapply(first, function(i) {
    pp <- layout$panel_params[[i]]
    guides <- pp$guides
    axes <- list()
    if (!is.null(guides)) {
      for (j in seq_along(guides$params)) {
        g <- guides$guides[[j]]
        params <- guides$params[[j]]
        if (!ir_is_ggplot2(g, axis_guides)) {
          support$add("guide", class(g)[1], "axis guide not in Phase 2 scope")
          next
        }
        if (inherits(g, "GuideNone")) next
        axes[[length(axes) + 1L]] <- params[intersect(
          c("name", "position", "key", "title", "angle", "n.dodge", "minor.ticks", "cap", "check.overlap", "order"),
          names(params)
        )]
      }
    }
    view <- function(v) {
      if (is.null(v)) return(NULL)
      list(major = v$break_positions(), minor = v$break_positions_minor())
    }
    list(x.range = pp$x.range, y.range = pp$y.range, x = view(pp$x), y = view(pp$y), axes = axes)
  })
}

# Labels -----------------------------------------------------------------

# Plot titles and axis titles: the axis titles as Layout$render() resolves
# them (Layout$resolve_label(), then Coord$labels()).
ir_labels <- function(built, support) {
  layout <- built@layout
  labels <- built@plot@labels
  axis <- layout$coord$labels(
    list(
      x = layout$resolve_label(layout$panel_scales_x[[1]], labels),
      y = layout$resolve_label(layout$panel_scales_y[[1]], labels)
    ),
    layout$panel_params[[1]]
  )
  out <- list(
    title = labels$title, subtitle = labels$subtitle, caption = labels$caption, tag = labels$tag,
    x = axis$x$primary, x.sec = axis$x$secondary, y = axis$y$primary, y.sec = axis$y$secondary
  )
  lapply(stats::setNames(names(out), names(out)), function(n) {
    x <- ir_text(out[[n]], support, paste(n, "label"))
    if (length(x) > 1) {
      support$add("text", paste(n, "label"), "label has more than one string")
    }
    x
  })
}

# Legends ----------------------------------------------------------------

# Legend keys the full tier will draw: ggplot2's own draw_key functions for
# in-scope geoms.
ir_draw_keys <- c(
  "point", "rect", "polygon", "path", "blank", "abline", "vline", "vpath",
  "text", "label", "boxplot", "crossbar", "smooth", "pointrange",
  "linerange", "timeseries"
)

ir_legends <- function(guides, support) {
  legend_guides <- c("GuideLegend", "GuideColourbar", "GuideColoursteps", "GuideBins", "GuideNone")
  keys <- lapply(paste0("draw_key_", ir_draw_keys), get, envir = asNamespace("ggplot2"))
  out <- list()
  for (j in seq_along(guides$params)) {
    g <- guides$guides[[j]]
    params <- guides$params[[j]]
    if (!ir_is_ggplot2(g, legend_guides)) {
      support$add("guide", class(g)[1], "legend guide not in Phase 2 scope")
      next
    }
    if (inherits(g, "GuideNone")) next
    if (class(g)[1] %in% c("GuideLegend", "GuideBins") && !is.data.frame(params$decor)) {
      for (d in params$decor) {
        f <- environment(d$draw_key)$f %||% d$draw_key
        if (!any(vapply(keys, identical, logical(1), f))) {
          support$add("guide", class(g)[1], "legend key not drawn by a ggplot2 draw_key function")
        }
      }
    }
    params$class <- class(g)[1]
    out[[length(out) + 1L]] <- params
  }
  out
}
