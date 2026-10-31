# The full tier's page for plots of blank layers (PHASE2.md, Architecture;
# TASKS.md R4.2): everything ggplot_gtable() draws around the panel, drawn
# in Rust. page_spec() resolves the theme elements the drawers need once
# per plot into plain lists (colours packed, widths in pixels), on top of
# the layout spec of R/render-layout.R; rs_render_page()
# (alot-core/src/render/page.rs) lays the page out and draws it.
#
# Mirrors Coord$draw_panel(), Coord$render_bg()/render_fg() and
# guide_grid() (ggplot2 R/coord-.R, R/guides-grid.R), GuideAxis
# (R/guide-axis.R) and the plot background of ggplot_gtable()
# (R/plot-build.R). The layers drawn are those of full_geoms().

# Pixels of a page of `size` (agg_capture()'s arguments): ragg's get_dims()
# (ragg R/aaa.R).
page_px <- function(size) {
  per <- switch(size$units %||% "px", `in` = size$res, cm = size$res / 2.54, mm = size$res / 25.4, px = 1)
  as.integer(c(size$width, size$height) * per)
}

# A resolved element_line as the Rust drawers take it: packed colour, width
# in pixels (grid's lwd is linewidth * .pt; ragg's pixels are lwd * res /
# 96), R's line type code, and line end and join codes. NULL where the
# line draws nothing.
full_line <- function(el, res) {
  if (layout_blank(el)) {
    return(NULL)
  }
  if (!is.null(el$arrow) && !isFALSE(el$arrow)) {
    layout_decline("arrows")
  }
  lty <- lty_code(el$linetype %||% 1)
  colour <- point_colours(as.character(el$colour %||% NA), NA)
  if (is.null(lty) || is.null(colour) || length(lty) != 1 || length(colour) != 1) {
    layout_decline("a line type or colour alot doesn't draw")
  }
  cap <- as.numeric(match(el$lineend %||% "butt", c("round", "butt", "square")) - 1L)
  join <- as.numeric(match(el$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L)
  if (anyNA(c(cap, join))) {
    layout_decline("an unsupported line end or join")
  }
  if (lty < 0) {
    return(NULL)
  }
  list(col = colour, lwd = el$linewidth * ggplot2::.pt * res / 96, lty = lty, cap = cap, join = join)
}

# A resolved element_rect as rectGrob() draws it: fill, outline colour and
# width in pixels (0 for blank line types), R's line type code (0 solid;
# dashed outlines start at the bottom-left corner, as GERect() hands ragg
# the corners) and the join (0 mitre, 1 round, 2 bevel). `fill = NA`
# overrides the fill. NULL for a blank element.
full_rect <- function(el, res, fill = el$fill %||% NA) {
  if (layout_blank(el)) {
    return(NULL)
  }
  lty <- lty_code(el$linetype %||% 1)
  fill <- point_colours(as.character(fill), NA)
  colour <- point_colours(as.character(el$colour %||% NA), NA)
  join <- as.numeric(match(el$linejoin %||% "round", c("mitre", "round", "bevel")) - 1L)
  if (length(lty) != 1 || is.null(fill) || is.null(colour) || length(fill) != 1 || length(colour) != 1 || is.na(join)) {
    layout_decline("a rect alot doesn't draw")
  }
  list(
    fill = fill, col = colour, lwd = (el$linewidth %||% 0) * ggplot2::.pt * (lty >= 0) * res / 96,
    lty = as.numeric(max(lty, 0)), join = join
  )
}

# Coord$render_bg(), guide_grid() and Coord$render_fg() (ggplot2
# R/coord-.R, R/guides-grid.R) for the panel: the background, the grid
# lines (minor y, minor x, major y, major x) as break positions in npc, and
# the border. With `panel.ontop`, Coord$draw_panel() draws the background
# and grid over the layers.
full_panel <- function(built, ir, res, panel = 1L) {
  layout <- built@layout
  pp <- layout$panel_params[[panel]]
  coord <- layout$coord
  theme <- ir$theme
  x_major <- pp$x$mapped_breaks()
  y_major <- pp$y$mapped_breaks()
  breaks <- list(
    minor.y = setdiff(pp$y$mapped_breaks_minor(), y_major), minor.x = setdiff(pp$x$mapped_breaks_minor(), x_major),
    major.y = y_major, major.x = x_major
  )
  grid <- list()
  for (type in names(breaks)) {
    var <- breaks[[type]]
    style <- full_line(theme[[paste0("panel.grid.", type)]], res)
    if (length(var) < 1 || is.null(style)) next
    horizontal <- endsWith(type, ".y")
    df <- data.frame(var = rep(var, each = 2), alt = rep(c(-Inf, Inf), length(var)))
    names(df) <- if (horizontal) c("y", "x") else c("x", "y")
    df <- coord$transform(df, pp)
    pos <- if (horizontal) df$y else df$x
    grid[[length(grid) + 1L]] <- list(pos = as.numeric(pos[seq(1, length(pos), by = 2)]), horizontal = as.numeric(horizontal), style = style)
  }
  list(
    clip = as.numeric(identical(coord$clip, "on")), ontop = as.numeric(isTRUE(theme[["panel.ontop"]])),
    background = full_rect(theme[["panel.background"]], res), grid = grid,
    border = full_rect(theme[["panel.border"]], res, fill = NA)
  )
}

# The panels in layout order: one full_panel() per distinct pair of
# scales.
full_panels <- function(built, ir, res) {
  scales <- ir$layout$scales
  first <- match(seq_len(max(scales)), scales)
  lapply(first, function(i) full_panel(built, ir, res, i))[scales]
}

# The layers as rs_render_page() reads them, each a list with its `kind`
# ("points", "rects", "paths" or "text"), in layer order. Layers without
# rows draw nothing. `ir`'s layer data has missing rows removed and shapes
# translated. Positions rescale linearly (hybrid_decline() checked): the
# ranges are one pair for every panel, or a pair per panel where scales
# are free.
full_layers <- function(built, ir, res) {
  pps <- built@layout$panel_params
  scales <- ir$layout$scales
  first <- match(seq_len(max(scales)), scales)
  pair <- function(aes) {
    r <- lapply(pps[first], function(pp) as.double(linear_range(pp[[aes]])))
    if (length(r) == 1) r[[1]] else unlist(r[scales])
  }
  ranges <- list(x_range = pair("x"), y_range = pair("y"))
  n_panels <- nrow(ir$layout$panels)
  out <- list()
  for (i in seq_along(ir$layers)) {
    layer <- ir$layers[[i]]
    if (is.null(layer$kind) || nrow(layer$data) == 0) next
    spec <- switch(layer$kind,
      points = full_points(layer$data, ranges, n_panels, res),
      rects = full_rects(built@plot@layers[[i]], layer$data, ranges, n_panels, res),
      paths = full_paths(built@plot@layers[[i]], layer$data, ranges, n_panels, res),
      text = full_text(built@plot@layers[[i]], layer$data, built@layout$coord, pps, scales, n_panels, res),
      ribbons = full_ribbons(built@plot@layers[[i]], layer$data, ranges, n_panels, res, FALSE),
      smooth = full_ribbons(built@plot@layers[[i]], layer$data, ranges, n_panels, res, TRUE),
      label = {
        out[[length(out) + 1L]] <- full_labels(built@plot@layers[[i]], layer$data, built@layout$coord, pps, scales, n_panels, res, ranges)
        next
      },
      polygons = {
        out <- c(out, full_polygons(built@plot@layers[[i]], layer$data, ranges, n_panels, res))
        next
      },
      {
        draw <- if (layer$kind %in% names(segment_kinds())) full_segments else full_range
        out <- c(out, draw(layer$kind, built@plot@layers[[i]], layer$data, ranges, n_panels, res))
        next
      }
    )
    kind <- if (layer$kind %in% c("ribbons", "smooth")) "paths" else layer$kind
    if (!is.null(spec)) out[[length(out) + 1L]] <- c(list(kind = kind), spec)
  }
  out
}

# The rows of each panel (1-based, in the order given), NULL for a panel
# without rows, from the PANEL value of each row.
layer_panel_rows <- function(panel, n_panels, rows = seq_along(panel)) {
  by <- split(rows, factor(as.integer(panel)[rows], levels = seq_len(n_panels)))
  unname(lapply(by, function(r) if (length(r)) r))
}

# A point layer (draw_points_layer(), R/render.R, and GeomPoint$draw_panel(),
# ggplot2 R/geom-point.R). Each layer carries its rows' `panel` (1-based,
# layout order) for Rust to deal them out.
full_points <- function(data, ranges, n_panels, res) {
  colour <- point_colours(data$colour, data$alpha)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    layout_decline("a point colour alot doesn't parse")
  }
  c(ranges, list(
    x = as.double(data$x), y = as.double(data$y),
    shape = as.double(data$shape), size = as.double(data$size), stroke = as.double(data$stroke),
    colour = colour, fill = fill, consts = c(ggplot2::.pt, ggplot2::.stroke, res),
    panel = if (n_panels > 1) as.integer(data$PANEL)
  ))
}

# A rect layer, mirroring draw_rects_layer() (R/render.R) and
# GeomRect$draw_panel() (ggplot2 R/geom-rect.R): rectGrob(col = colour,
# fill = fill_alpha(fill, alpha)); the outline keeps its colour's own
# alpha, and gg_par(lwd = linewidth) is linewidth * .pt (no stroke for
# blank line types).
full_rects <- function(layer, data, ranges, n_panels, res) {
  params <- layer$computed_geom_params
  colour <- point_colours(as.character(data$colour), NA)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    layout_decline("a rect colour alot doesn't parse")
  }
  c(ranges, list(
    xmin = data$xmin, xmax = data$xmax, ymin = data$ymin, ymax = data$ymax,
    colour = colour, fill = fill, lwd = as.double(data$linewidth * ggplot2::.pt * rect_linetype(data$linetype)),
    join = as.numeric(match(params$linejoin %||% "mitre", c("mitre", "round", "bevel")) - 1L), res = res,
    rows = layer_panel_rows(data$PANEL, n_panels)
  ))
}

# A path layer, mirroring draw_paths_layer() (R/render.R) and
# GeomPath$draw_panel() (ggplot2 R/geom-path.R): one polyline per group in
# group order, styled from its first row, groups of one row dropped.
# geom_step() draws its stairsteps the same way (GeomStep$draw_panel()).
full_paths <- function(layer, data, ranges, n_panels, res) {
  params <- layer$computed_geom_params
  if (inherits(layer$geom, "GeomStep")) data <- step_data(data, params)
  if (nrow(data) == 0) {
    return(NULL)
  }
  groups <- rs_path_groups(as.integer(data$PANEL), data$group)
  if (is.null(groups)) {
    pg <- panel_group_order(data)
    key <- pg$key
    order <- pg$order[tabulate(key)[key[pg$order]] >= 2]
    first <- order[!duplicated(key[order])]
    path <- match(key[order], key[first]) - 1L
  } else {
    order <- groups$order
    first <- groups$first
    path <- groups$path
  }
  if (length(order) == 0) {
    return(NULL)
  }
  colour <- point_colours(data$colour[first], data$alpha[first])
  if (is.null(colour)) {
    layout_decline("a line colour alot doesn't parse")
  }
  codes <- lty_code(data$linetype[first])
  c(ranges, list(
    x = data$x, y = data$y, colour = colour,
    lwd = ifelse(codes < 0, 0, data$linewidth[first] * ggplot2::.pt),
    lty = as.double(pmax(codes, 0)),
    cap = as.numeric(match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L),
    join = as.numeric(match(params$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L),
    mitre = as.double(params$linemitre %||% 10), res = res,
    rows = if (n_panels == 1) list(order) else layer_panel_rows(data$PANEL, n_panels, order),
    path_rows = if (n_panels == 1) {
      list(path)
    } else {
      unname(lapply(split(path, factor(as.integer(data$PANEL)[order], levels = seq_len(n_panels))), function(p) if (length(p)) p))
    }
  ))
}

# A ribbon layer as a path layer of polygons and polylines in drawing
# order. Mirrors Geom$draw_panel() (ggplot2 R/geom-.R: each group in turn,
# by panel then group) and GeomRibbon$draw_group() (R/geom-ribbon.R) for a
# linear coord and aesthetics constant along each ribbon (ribbons_decline()):
# a polygonGrob() of the upper line (rows not marked `align_padding` by
# stat_align()) then the lower line reversed, filled with
# fill_alpha(fill, alpha) and outlined only for outline.type = "full"; then
# polylineGrob()s of the upper and/or lower line in `colour` (its own
# alpha). With `smooth`, GeomSmooth$draw_group() (R/geom-smooth.R): the
# ribbon (when `se`, uncoloured, so without its lines), then
# GeomLine$draw_panel()'s polyline of x and y in alpha(colour, NA).
full_ribbons <- function(layer, data, ranges, n_panels, res, smooth) {
  params <- layer$computed_geom_params
  flipped <- isTRUE(params$flipped_aes)
  nm <- if (flipped) c(pos = "y", lo = "xmin", hi = "xmax", val = "x") else c(pos = "x", lo = "ymin", hi = "ymax", val = "y")
  ribbon <- !smooth || (isTRUE(params$se) && all(nm[c("lo", "hi")] %in% names(data)))
  outline <- if (smooth) "none" else params$outline.type %||% "both"
  o <- order(as.integer(data$PANEL), data$group)
  key <- vctrs::vec_group_id(data.frame(as.integer(data$PANEL), data$group)[o, , drop = FALSE])
  n_groups <- attr(key, "n")
  first <- o[match(seq_len(n_groups), key)]
  # Pieces of each group's paths: rows, the column giving their value
  # (1 lower, 2 upper, 3 the smooth's line) and the slot of the path.
  pieces <- list()
  add <- function(rows, k, which, slot) {
    pieces[[length(pieces) + 1L]] <<- list(rows = rows, key = k, which = rep(which, length(rows)), slot = rep(slot, length(rows)))
  }
  if (ribbon) {
    keep <- if (is.null(data$align_padding)) rep(TRUE, nrow(data)) else !data$align_padding %in% TRUE
    up <- keep[o]
    lo_order <- order(rev(key))
    lo_rows <- rev(o)[lo_order]
    lo_key <- rev(key)[lo_order]
    add(o[up], key[up], 2L, 0L)
    add(lo_rows, lo_key, 1L, 0L)
    if (outline %in% c("both", "upper")) add(o[up], key[up], 2L, 1L)
    if (outline %in% c("both", "lower")) add(lo_rows, lo_key, 1L, 2L)
  }
  if (smooth) add(o, key, 3L, 3L)
  rows <- unlist(lapply(pieces, `[[`, "rows"))
  path <- (unlist(lapply(pieces, `[[`, "key")) - 1L) * 4L + unlist(lapply(pieces, `[[`, "slot"))
  which <- unlist(lapply(pieces, `[[`, "which"))
  ord <- order(path)
  rows <- rows[ord]
  path <- path[ord]
  which <- which[ord]
  if (length(rows) == 0) {
    return(NULL)
  }
  ids <- unique(path)
  g <- first[ids %/% 4L + 1L]
  slot <- ids %% 4L
  pos <- data[[nm[["pos"]]]][rows]
  val <- numeric(length(rows))
  for (w in 1:3) {
    at <- which == w
    val[at] <- data[[nm[[c("lo", "hi", "val")[w]]]]][rows[at]]
  }
  codes <- lty_code(data$linetype[g])
  # Polygons: stroked only for outline.type = "full"; lines and the
  # smooth's path take colour with its own alpha.
  stroked <- slot != 0L | outline == "full"
  colour <- point_colours(ifelse(stroked, as.character(data$colour[g]), NA_character_), NA)
  fill <- point_colours(as.character(data$fill[g]), data$alpha[g])
  if (is.null(colour) || is.null(fill)) {
    layout_decline("a ribbon colour alot doesn't parse")
  }
  panel <- as.integer(data$PANEL)[rows]
  path <- match(path, ids) - 1L
  seqs <- seq_along(rows)
  c(ranges, list(
    x = as.double(if (flipped) val else pos), y = as.double(if (flipped) pos else val), colour = colour,
    lwd = ifelse(codes < 0 | !stroked, 0, data$linewidth[g] * ggplot2::.pt), lty = as.double(pmax(codes, 0)),
    closed = as.integer(slot == 0L), fill = fill,
    cap = as.numeric(match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L),
    join = as.numeric(match(params$linejoin %||% "round", c("round", "mitre", "bevel")) - 1L),
    mitre = as.double(params$linemitre %||% 10), res = res,
    rows = if (n_panels == 1) list(seqs) else layer_panel_rows(panel, n_panels),
    path_rows = if (n_panels == 1) list(path) else unname(lapply(split(path, factor(panel, levels = seq_len(n_panels))), function(p) if (length(p)) p))
  ))
}

# Fontface codes of grid's gpar(fontface =): 1 plain, 2 bold, 3 italic, 4
# bold italic; NA for what alot doesn't mirror (the symbol face and so on).
text_face <- function(face) {
  if (is.numeric(face)) {
    return(ifelse(face %in% 1:4, as.integer(face), NA_integer_))
  }
  match(as.character(face), c("plain", "bold", "italic", "bold.italic"))
}

# Why a geom_text() layer isn't drawn in Rust, or NULL. Layers that
# decline here are drawn by ggplot2 (hybrid tier).
text_decline <- function(data, params) {
  cols <- c("x", "y", "label", "colour", "family", "size", "angle", "hjust", "vjust", "alpha", "fontface", "lineheight")
  if (!all(cols %in% names(data))) {
    return("missing text aesthetics")
  }
  if (isTRUE(params$parse)) {
    return("parsed labels (plotmath)")
  }
  if (isTRUE(params$check_overlap)) {
    return("check_overlap")
  }
  if (!(params$size.unit %||% "mm") %in% c("mm", "pt", "cm", "in", "pc")) {
    return("unsupported size.unit")
  }
  if (!is.double(data$x) || !is.double(data$y) || inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is not double")
  }
  if (!is.character(data$label) && !is.factor(data$label)) {
    return("labels are not character")
  }
  if (!is.character(data$family) || anyNA(text_face(data$fontface))) {
    return("a font alot doesn't mirror")
  }
  if (!is_colour_vector(data$colour)) {
    return("colour is not a colour vector")
  }
  num <- c("size", "angle", "lineheight")
  if (!all(vapply(data[num], is.numeric, logical(1))) || anyNA(data[num]) || !(is.numeric(data$hjust) || is.character(data$hjust)) ||
    !(is.numeric(data$vjust) || is.character(data$vjust))) {
    return("size, angle, lineheight, hjust or vjust is not numeric")
  }
  NULL
}

# A text layer, mirroring GeomText$draw_panel() (ggplot2 R/geom-text.R):
# positions transformed by the coord (npc), justification resolved by
# compute_just(), and textGrob(gp = gg_par(col = alpha(colour, alpha),
# fontsize = size * size.unit, fontfamily, fontface, lineheight)). Sizes
# and line heights are in device pixels as text_raster() (R/render-text.R)
# gives them.
full_text <- function(layer, data, coord, pps, scales, n_panels, res) {
  params <- layer$computed_geom_params
  label <- gg_validate_labels(as.character(data$label))
  # Each panel's rows through its scales (Coord$transform() per panel, as
  # Layer$draw_geom() hands GeomText$draw_panel() a panel at a time).
  key <- scales[as.integer(data$PANEL)]
  tr <- data[c("x", "y")]
  for (k in unique(key)) {
    rows <- which(key == k)
    tr[rows, ] <- coord$transform(data[rows, c("x", "y")], pps[[match(k, scales)]])
  }
  hjust <- as.double(gg_compute_just(data$hjust, tr$x, tr$y, data$angle))
  vjust <- as.double(gg_compute_just(data$vjust, tr$y, tr$x, data$angle))
  fontsize <- data$size * gg_resolve_text_unit(params$size.unit %||% "mm")
  colour <- point_colours(as.character(data$colour), data$alpha)
  font <- text_fonts(data$family, text_face(data$fontface))
  key <- paste(font$path, font$index)
  distinct <- !duplicated(key)
  if (is.null(colour) || anyNA(font$path) || anyNA(c(hjust, vjust, tr$x, tr$y, fontsize)) || anyNA(label)) {
    layout_decline("text alot doesn't draw as ragg does")
  }
  for (k in which(distinct)) {
    covered <- rs_text_covered(enc2utf8(unique(label[key == key[k]])), font$path[k], font$index[k])
    if (!all(covered)) {
      layout_decline(sprintf("glyph missing from the font in \"%s\"", unique(label[key == key[k]])[!covered][1]))
    }
  }
  list(
    label = enc2utf8(label), x = as.double(tr$x), y = as.double(tr$y), hjust = hjust, vjust = vjust, rot = as.double(data$angle),
    font = match(key, key[distinct]), font_path = font$path[distinct], font_index = as.integer(font$index[distinct]),
    size = as.double(fontsize * res / 72), line = as.double(data$lineheight * 1.2 * fontsize * res / 72), colour = colour,
    rows = layer_panel_rows(data$PANEL, n_panels)
  )
}

# The geoms the full tier draws (R6.1); a geom keeping one of their
# draw_panel methods under another class is not drawn (full_kind() would
# say so, the geoms are compared by identity).
full_geoms <- function() {
  list(
    ggplot2::GeomPoint, ggplot2::GeomRect, ggplot2::GeomTile, ggplot2::GeomBar,
    ggplot2::GeomCol, ggplot2::GeomPath, ggplot2::GeomLine, ggplot2::GeomStep, ggplot2::GeomText,
    ggplot2::GeomRibbon, ggplot2::GeomArea, ggplot2::GeomDensity, ggplot2::GeomSmooth,
    ggplot2::GeomBoxplot, ggplot2::GeomViolin, ggplot2::GeomCrossbar, ggplot2::GeomErrorbar,
    ggplot2::GeomLinerange, ggplot2::GeomPointrange, ggplot2::GeomSegment, ggplot2::GeomAbline,
    ggplot2::GeomHline, ggplot2::GeomVline, ggplot2::GeomRug, ggplot2::GeomLabel, ggplot2::GeomPolygon
  )
}

# Why the full tier can't draw `built`, or NULL: it draws the layers of
# full_geoms() and geom_blank(), and only the cartesian axes and guides
# above.
full_decline <- function(built, ir) {
  drawn <- vapply(built@plot@layers, function(l) {
    geom <- drawn_geom(l$geom)
    ir_is_ggplot2(geom, "GeomBlank") || any(vapply(full_geoms(), identical, logical(1), geom))
  }, logical(1))
  if (!all(drawn)) {
    return("layers other than geom_point(), geom_line() and the other geoms the full tier draws")
  }
  support <- ir$support
  # Layers without rows draw nothing.
  support <- support[!(support$component == "layer" & (support$name == "GeomBlank" | support$reason == "no rows")), ]
  if (nrow(support) > 0) {
    return(support$reason[1])
  }
  if (!ir$coord$class %in% c("CoordCartesian", "CoordFixed") || !identical(ir$coord$reverse %||% "none", "none")) {
    return("coord not drawn yet")
  }
  caps <- unlist(lapply(ir$scales, function(s) vapply(s$axes, function(a) !identical(a$cap %||% "none", "none"), logical(1))))
  if (any(caps)) {
    return("axis cap")
  }
  NULL
}

# The spec of rs_render_page() for `built` on a page of `size`; declines
# with layout_decline().
page_spec <- function(built, ir, size) {
  res <- size$res
  if (!identical(as.numeric(size$scaling %||% 1), 1)) {
    layout_decline("scaling")
  }
  reason <- full_decline(built, ir)
  if (!is.null(reason)) {
    layout_decline(reason)
  }
  layout <- layout_spec(built, ir, res)
  if (inherits(layout, "alot_layout_declined")) {
    layout_decline(attr(layout, "reason"))
  }
  bg <- point_colours(as.character(size$bg %||% "white"), NA)
  if (is.null(bg)) {
    layout_decline("a background colour alot doesn't parse")
  }
  list(
    page = page_px(size), bg = bg, layout = layout,
    background = full_rect(ir$theme[["plot.background"]], res),
    panels = full_panels(built, ir, res),
    layers = full_layers(built, ir, res)
  )
}

# Draws `built` in the full tier: a nativeRaster, or NULL with the reason
# as a "reason" attribute where the full tier declines the plot.
render_full <- function(built, size) {
  decline <- function(reason) structure(list(), reason = reason)
  spec <- tryCatch(page_spec(built, render_ir(built), size), alot_layout_decline = function(e) e)
  if (inherits(spec, "condition")) {
    return(decline(conditionMessage(spec)))
  }
  out <- rs_render_page(spec, render_threads())
  if (is.null(out)) {
    return(decline("the page spec is not one the Rust drawer reads"))
  }
  # ggplot2 warns of the rows it removes as it draws the layers.
  for (i in seq_along(built@plot@layers)) {
    layer <- built@plot@layers[[i]]
    data <- built@data[[i]]
    if (is.null(full_kind(layer)) || gg_empty(data)) next
    data <- point_handle_na(layer, data)
    if (identical(full_kind(layer), "paths") && nrow(data) > 0) path_messages(layer, data)
  }
  out
}
