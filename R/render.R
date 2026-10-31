# Rendering to PNG (PHASE2.md). alot_png() picks the first tier that
# supports the plot:
#
# - hybrid: ggplot2's gtable and grid drawing on ragg::agg_capture(), except
#   that layers with a Rust drawer become lazy grobs that render their panel
#   to a pixel-aligned raster in Rust. The PNG is encoded in Rust.
# - ggplot2: ggplot_gtable() drawn on ragg::agg_png(), unchanged.
#
# hybrid_gtable() swaps each supported layer's draw_geom (GeomPoint, and
# GeomRect and the geoms inheriting its draw_panel) for one that returns a
# lazy "alot_hybrid_layer" grob per panel. The grob holds the layer's
# columns; at draw time, on a raster (ragg) device, it renders the panel's
# marks at device resolution. On any other device it draws ggplot2's own
# grob.

#' Render a plot to PNG with alot (experimental)
#'
#' Builds `plot` with [alot_build()] (unless it is already built) and draws
#' it with the first rendering tier that supports it (see
#' [alot_render_coverage()]). In the hybrid tier, ggplot2 lays the plot out
#' and layers with a Rust drawer are rasterised in Rust; the PNG is encoded
#' in Rust. Otherwise the plot is drawn by ggplot2 on [ragg::agg_png()].
#' If the hybrid tier hits an internal error, `alot_png()` warns and draws
#' with ggplot2. The arguments follow [ggplot2::ggsave()]'s, and the file
#' has the size, resolution and colour type `ggsave()` gives with ragg.
#'
#' @param plot A ggplot or a built plot.
#' @param filename Output file.
#' @param width,height Plot size in `units`.
#' @param units One of `"in"`, `"cm"`, `"mm"` or `"px"`.
#' @param dpi Resolution: a number, or `"screen"`, `"print"` or `"retina"`.
#' @param bg Background colour. If `NULL`, the plot theme's
#'   `plot.background` fill, as in [ggplot2::ggsave()].
#' @param scaling Scaling factor for line widths and text, as in
#'   [ragg::agg_png()].
#' @param ... Passed to the ragg device ([ragg::agg_capture()] or
#'   [ragg::agg_png()]).
#' @return `filename`, invisibly, with attribute `"tier"` naming the tier
#'   that drew it (`"full"`, `"hybrid"` or `"ggplot2"`).
#' @seealso [alot_ggsave()]
#' @export
alot_png <- function(plot, filename, width = 7, height = 7, units = c("in", "cm", "mm", "px"),
                     dpi = 300, bg = NULL, scaling = 1, ...) {
  built <- if (ggplot2::is_ggplot(plot)) alot_build(plot) else plot
  filename <- path.expand(filename)
  dpi <- gg_parse_dpi(dpi)
  dim <- gg_plot_dim(c(width, height), units = units[1], limitsize = FALSE, dpi = dpi)
  bg <- gg_get_plot_background(built@plot, bg)
  size <- list(width = dim[1], height = dim[2], units = "in", res = dpi, bg = bg, scaling = scaling, ...)
  out <- render_raster(built, size)
  if (is.null(out$raster)) {
    render_ggplot2(built, filename, size)
  } else {
    write_png(out$raster, filename, bg, dpi)
  }
  invisible(structure(filename, tier = out$tier))
}

# Writes a nativeRaster as ragg's agg_png() would for this background and
# resolution (ragg src/png_dev.cpp, src/AggDevicePng.h): RGBA only if `bg` is
# not opaque, a bKGD chunk from `bg`, and a pHYs chunk from `dpi` unless it
# is NA.
write_png <- function(raster, filename, bg = "white", dpi = NA) {
  rgba <- as.integer(grDevices::col2rgb(bg, alpha = TRUE)[, 1])
  rs_write_png(raster, filename, rgba, if (is.na(dpi)) 0 else as.double(dpi))
}

# Draws a built plot with the first tier that supports it. Returns the
# `tier` and, for alot's tiers, the page as a nativeRaster; for the ggplot2
# tier, `raster` is NULL and the caller draws with ggplot2. An internal
# error in alot's tier warns (class "alot_render_fallback") and drops to
# ggplot2.
render_raster <- function(built, size) {
  # The full tier draws point and blank layers so far (R5.1);
  # options(alot.full_tier = FALSE) skips it.
  if (!isFALSE(getOption("alot.full_tier"))) {
    out <- tryCatch(
      render_full(built, size),
      error = function(e) {
        cli::cli_warn(
          c("alot's full renderer failed; trying another tier.", "x" = conditionMessage(e)),
          class = "alot_render_fallback"
        )
        NULL
      }
    )
    if (inherits(out, "nativeRaster")) {
      return(list(tier = "full", raster = out))
    }
  }
  tier <- render_coverage(built)$tier
  if (tier == "ggplot2") {
    cli::cli_inform(
      c("i" = "alot can't render any layer of this plot; drawing with ggplot2.",
        "i" = "See {.fn alot_render_coverage} for why."),
      .frequency = "once", .frequency_id = "alot_render_ggplot2"
    )
    return(list(tier = "ggplot2", raster = NULL))
  }
  tryCatch(
    list(tier = tier, raster = render_hybrid(built, size)),
    error = function(e) {
      cli::cli_warn(
        c("alot's {tier} renderer failed; drawing with ggplot2 instead.",
          "x" = conditionMessage(e)),
        class = "alot_render_fallback"
      )
      list(tier = "ggplot2", raster = NULL)
    }
  )
}

#' Report how alot would render a plot
#'
#' @param plot A ggplot or a built plot.
#' @return A list with `tier`, the tier [alot_png()] would use (`"full"`,
#'   `"hybrid"` or `"ggplot2"`; `"full"` unless `options(alot.full_tier =
#'   FALSE)`); `layers`, a data frame with one row per layer: its
#'   `geom`, the `engine` that draws it in the hybrid tier (`"rust"` or
#'   `"ggplot2"`) and, for `"ggplot2"`, the `reason`; and `full`, a data
#'   frame of the `component`, `name` and `reason` for everything that keeps
#'   the plot out of the full tier (no rows: nothing does). `tier` can still
#'   drop to `"hybrid"` if the full renderer meets something at draw time,
#'   such as a strip narrower than its text.
#' @export
alot_render_coverage <- function(plot) {
  built <- if (ggplot2::is_ggplot(plot)) alot_build(plot) else plot
  ir <- render_ir(built)
  out <- render_coverage(built)
  full <- ir$support
  reason <- full_page_reason(built, ir)
  if (nrow(full) == 0 && !is.null(reason)) {
    full <- data.frame(component = "page", name = "layout", reason = reason)
  }
  if (nrow(full) == 0 && !isFALSE(getOption("alot.full_tier"))) {
    out$tier <- "full"
  }
  c(out, list(full = full))
}

# Why the full tier's page can't be laid out for `built`, or NULL: the
# declines of page_spec() (any page size gives the same).
full_page_reason <- function(built, ir) {
  size <- list(width = 100, height = 100, units = "px", res = 96)
  out <- tryCatch(page_spec(built, ir, size), alot_layout_decline = function(e) conditionMessage(e))
  if (is.character(out)) out else NULL
}

render_coverage <- function(built) {
  layers <- built@plot@layers
  layout <- built@layout
  reason <- vapply(seq_along(layers), function(i) {
    data <- suppressWarnings(hybrid_data(layers[[i]], built@data[[i]]))
    hybrid_decline(layers[[i]], data, layout) %||% NA_character_
  }, character(1))
  geom <- vapply(layers, function(l) class(l$geom)[1], character(1))
  engine <- ifelse(is.na(reason), "rust", "ggplot2")
  list(
    tier = if (any(engine == "rust")) "hybrid" else "ggplot2",
    layers = data.frame(geom = geom, engine = engine, reason = reason)
  )
}

# The gtable is built with the device open, as print.ggplot() does:
# ggplot_gtable() measures text on the current device.
render_hybrid <- function(built, size) {
  old <- grDevices::dev.cur()
  cap <- do.call(ragg::agg_capture, size)
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev, old))
  gtable <- hybrid_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
  cap(native = TRUE)
}

render_ggplot2 <- function(built, filename, size) {
  old <- grDevices::dev.cur()
  do.call(ragg::agg_png, c(list(filename), size))
  dev <- grDevices::dev.cur()
  on.exit(close_device(dev, old))
  gtable <- ggplot2::ggplot_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
}

# Closes `dev` and makes `old` current again, as ggsave() does. Closing a
# device after an error mid-draw warns "Killing locked device"; the error
# itself is reported instead.
close_device <- function(dev, old = 1L) {
  withCallingHandlers(
    grDevices::dev.off(dev),
    warning = function(w) {
      if (grepl("locked device", conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
  # dev.off() already activates another open device, often `old`. R's
  # selectDevice() invokes activation callbacks even for the current device
  # (R src/main/devices.c); reselecting it can make RStudio redraw the plot.
  # Restore `old` only when it still exists and is not already current.
  if (old > 1 && old %in% grDevices::dev.list() && grDevices::dev.cur() != old) {
    grDevices::dev.set(old)
  }
}

# Like ggplot2::ggplot_gtable(), but layers with a Rust drawer become grobs
# that draw as a raster rendered in Rust when the device is a ragg device.
# Text grobs draw through Rust only with options(alot.hybrid_text = TRUE),
# which the text tests use: ragg draws a page's few text grobs faster than a
# raster per grob (inst/bench/RESULTS.md, R2.2). The full tier draws text in
# Rust regardless.
hybrid_gtable <- function(data) {
  plot <- data@plot
  plot@layers <- lapply(plot@layers, hybrid_layer)
  data@plot <- plot
  gtable <- ggplot2::ggplot_gtable(data)
  if (isTRUE(getOption("alot.hybrid_text"))) hybrid_text(gtable) else gtable
}

hybrid_layer <- function(layer) {
  draw <- switch(hybrid_kind(layer) %||% "",
    points = draw_points_layer,
    rects = draw_rects_layer,
    paths = draw_paths_layer,
    polygons = draw_polygons_layer,
    NULL
  )
  if (is.null(draw)) {
    return(layer)
  }
  ggplot2::ggproto(NULL, layer,
    draw_geom = function(self, data, layout) draw(data, layout, layer)
  )
}

# The geom that draws a layer's panels: a layer's `key_glyph` makes its geom
# a child that only sets `draw_key` (set_draw_key(), ggplot2 R/layer.R),
# which draws as its parent does.
drawn_geom <- function(geom) {
  while (inherits(geom, "ggproto") && is.function(geom$super) &&
    length(setdiff(ls(geom, all.names = TRUE), c("draw_key", "super"))) == 0) {
    geom <- geom$super()
  }
  geom
}

# Which Rust drawer a layer's geom has in the hybrid tier: GeomPoint's
# draw_panel, GeomRect's (inherited by GeomTile, GeomBar and GeomCol),
# GeomPath's (GeomLine), GeomStep's (stairsteps, then GeomPath's) or
# GeomPolygon's.
hybrid_kind <- function(layer) {
  geom <- drawn_geom(layer$geom)
  if (identical(geom, ggplot2::GeomPoint)) {
    return("points")
  }
  same_draw <- function(parent) {
    identical(environment(geom$draw_panel)$f, environment(parent$draw_panel)$f)
  }
  kinds <- list(
    list("rects", c("GeomRect", "GeomTile", "GeomBar", "GeomCol"), ggplot2::GeomRect),
    list("paths", c("GeomPath", "GeomLine"), ggplot2::GeomPath),
    list("paths", "GeomStep", ggplot2::GeomStep),
    list("polygons", "GeomPolygon", ggplot2::GeomPolygon)
  )
  for (k in kinds) {
    if (class(geom)[1] %in% k[[2]] && same_draw(k[[3]])) {
      return(k[[1]])
    }
  }
  NULL
}

# The drawer the full tier has for a layer's geom: the hybrid tier's, and
# GeomText's draw_panel (text is drawn by ggplot2 in the hybrid tier).
# GeomRibbon's draw_group (GeomArea, GeomDensity) and GeomSmooth's are
# drawn in the full tier only ("ribbons", "smooth"; R6.5a).
full_kind <- function(layer) {
  kind <- hybrid_kind(layer)
  if (!is.null(kind)) {
    return(kind)
  }
  geom <- drawn_geom(layer$geom)
  same <- function(parent, method) identical(environment(geom[[method]])$f, environment(parent[[method]])$f)
  if (identical(geom, ggplot2::GeomText) && same(ggplot2::GeomText, "draw_panel")) {
    return("text")
  }
  if (class(geom)[1] %in% c("GeomRibbon", "GeomArea", "GeomDensity") && same(ggplot2::GeomRibbon, "draw_group") &&
    same(ggplot2::GeomRibbon, "draw_panel") && same(ggplot2::GeomRibbon, "handle_na")) {
    return("ribbons")
  }
  if (identical(class(geom)[1], "GeomSmooth") && same(ggplot2::GeomSmooth, "draw_group") && same(ggplot2::GeomSmooth, "draw_panel")) {
    return("smooth")
  }
  # Boxplots, violins and the range geoms (R6.5b, R/render-ranges.R);
  # segments, reference lines and rugs (R6.5c, R/render-segments.R).
  # Labels (R6.5d, R/render-labels.R).
  range_kind(geom) %||% segment_kind(geom) %||% label_kind(geom)
}

# A layer's data as its geom draws it: Layer$draw_geom() removes missing
# values first (ggplot2 R/layer.R), and GeomPoint$draw_panel() translates
# shape names (R/geom-point.R).
hybrid_data <- function(layer, data) {
  kind <- full_kind(layer)
  if (is.null(kind) || gg_empty(data)) {
    return(data)
  }
  data <- point_handle_na(layer, data)
  if (kind == "points") {
    data$shape <- gg_translate_shape_string(data$shape)
  }
  data
}

# Geom$handle_na(), skipped when nothing is missing: remove_missing()
# (ggplot2 R/utilities.R) then returns the data unchanged, and scanning 1e6
# rows for it costs more than drawing them.
point_handle_na <- function(layer, data) {
  geom <- layer$geom
  # GeomRibbon$handle_na() (ggplot2 R/geom-ribbon.R) checks its own columns
  # and splits groups at the rows it removes.
  if (inherits(geom, "GeomRibbon")) {
    return(geom$handle_na(data, layer$computed_geom_params))
  }
  # So do the geoms of R/render-ranges.R, whose required_aes ("x|y",
  # "ymin|xmin", ...) aren't column names, GeomSegment ("xend|yend") and
  # GeomRug, whose handle_na() checks the columns of its sides.
  if (!is.null(range_kind(drawn_geom(geom)) %||% segment_kind(drawn_geom(geom)))) {
    return(geom$handle_na(data, layer$computed_geom_params))
  }
  vars <- intersect(c(geom$required_aes, geom$non_missing_aes), names(data))
  complete <- rs_columns_complete(unclass(data)[vars], render_threads())
  if (complete) data else geom$handle_na(data, layer$computed_geom_params)
}

# Why the hybrid tier draws a layer with ggplot2, or NULL if Rust draws it,
# given the layer's data from hybrid_data(). draw_points_layer() makes the
# same check, so coverage and drawing agree.
# With `full`, the full tier's check: it also draws coord_flip()
# (full_flip(), R/render-full.R), but not its rugs.
hybrid_decline <- function(layer, data, layout, kind = hybrid_kind(layer), full = FALSE) {
  if (is.null(kind)) {
    return("no Rust drawer for this geom")
  }
  coord <- layout$coord
  flip <- full && identical(class(coord), class(ggplot2::coord_flip()))
  trans <- full && identical(class(coord), class(ggplot2::coord_transform()))
  if (!(identical(class(coord), class(ggplot2::coord_cartesian())) || flip || trans) ||
    !identical(coord$reverse %||% "none", "none")) {
    return("coord is not an unreversed coord_cartesian()")
  }
  if (flip && identical(kind, "rug")) {
    return("a rug with coord_flip()")
  }
  # coord_transform(): points and text are placed by coord$transform()
  # alone; the other geoms are munched (coord_munch()), not mirrored.
  if (trans && !kind %in% c("points", "text")) {
    return("coord_transform() munches this geom")
  }
  if (!identical(coord$clip, "on")) {
    return("clip is not \"on\"")
  }
  if (nrow(data) == 0) {
    return("no rows")
  }
  reason <- switch(kind,
    points = points_decline(data),
    rects = rects_decline(data, layer$computed_geom_params),
    paths = paths_decline(data, layer$computed_geom_params),
    polygons = polygons_decline(data, layer$computed_geom_params),
    text = text_decline(data, layer$computed_geom_params),
    ribbons = ribbons_decline(data, layer$computed_geom_params, FALSE),
    smooth = ribbons_decline(data, layer$computed_geom_params, TRUE),
    label = label_decline(data, layer$computed_geom_params),
    if (kind %in% names(segment_kinds())) {
      segment_decline(kind, data, layer$computed_geom_params)
    } else {
      range_decline(kind, data, layer$computed_geom_params)
    }
  )
  if (!is.null(reason)) {
    return(reason)
  }
  # Panels sharing a pair of scales share their ranges.
  pair <- paste(layout$layout$SCALE_X, layout$layout$SCALE_Y)
  linear <- vapply(layout$panel_params[!duplicated(pair)], function(pp) {
    !is.null(linear_range(pp$x)) && !is.null(linear_range(pp$y))
  }, logical(1))
  if (!all(linear) && !trans) {
    return("position scale does not rescale linearly")
  }
  NULL
}

is_colour_vector <- function(x) is.character(x) || rs_all_na_logical(x)

points_decline <- function(data) {
  cols <- c("x", "y", "shape", "colour", "fill", "size", "stroke", "alpha")
  if (!all(cols %in% names(data))) {
    return("missing point aesthetics")
  }
  if (!is.double(data$x) || !is.double(data$y) || !is.character(data$colour)) {
    return("x, y or colour has an unsupported type")
  }
  if (!is_colour_vector(data$fill)) {
    return("fill is not a colour vector")
  }
  # Coord$transform() leaves AsIs positions untransformed (transform_position
  # callers in ggplot2 R/coord-.R); the hybrid would rescale them.
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  # hybrid_data() removed rows with NA x, y or size (Geom$handle_na()).
  if (!rs_columns_complete(list(data$stroke), render_threads())) {
    return("NA in stroke")
  }
  if (is.character(data$shape)) {
    return("character pch")
  }
  if (!rs_point_shapes_supported(data$shape)) {
    return("unsupported shape")
  }
  NULL
}

# Line types the rect drawer handles: solid, and blank (no stroke).
rect_linetype <- function(lty) {
  solid <- (is.numeric(lty) & lty %in% 1) | (is.character(lty) & lty %in% c("solid", "1"))
  blank <- is.na(lty) | (is.numeric(lty) & lty %in% 0) | (is.character(lty) & lty %in% c("blank", "0"))
  if (all(solid | blank)) !blank
}

rects_decline <- function(data, params) {
  cols <- c("xmin", "xmax", "ymin", "ymax", "colour", "fill", "linewidth", "linetype", "alpha")
  if (!all(cols %in% names(data))) {
    return("missing rect aesthetics")
  }
  pos <- data[c("xmin", "xmax", "ymin", "ymax")]
  if (!all(vapply(pos, is.double, logical(1)))) {
    return("xmin, xmax, ymin or ymax is not double")
  }
  if (any(vapply(pos, inherits, logical(1), "AsIs"))) {
    return("x or y is AsIs")
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill)) {
    return("colour or fill is not a colour vector")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth)) {
    return("linewidth is NA or not numeric")
  }
  if (is.null(rect_linetype(data$linetype))) {
    return("linetype is not solid or blank")
  }
  if (!(params$linejoin %||% "mitre") %in% c("mitre", "round", "bevel")) {
    return("unsupported linejoin")
  }
  NULL
}

# R's line types as the packed hex codes the graphics engine passes to
# devices (GE_LTYpar in R src/main/engine.c: named types, integers 0-6 and
# hex strings of 2, 4, 6 or 8 digits, first digit lowest), with -1 for
# blank; NULL if any can't be converted.
lty_code <- function(lty) {
  u <- unique(lty)
  codes <- lty_code_unique(u)
  if (!is.null(codes)) codes[match(lty, u)]
}

lty_code_unique <- function(lty) {
  named <- c(solid = "", dashed = "44", dotted = "13", dotdash = "1343", longdash = "73", twodash = "2262")
  if (is.numeric(lty)) {
    if (any(is.na(lty) | lty != round(lty) | lty < 0 | lty > 6)) return(NULL)
    lty <- c("blank", names(named))[lty + 1]
  }
  if (!is.character(lty)) return(NULL)
  lty[is.na(lty)] <- "blank"
  hex <- ifelse(lty %in% names(named), named[lty], lty)
  hex[lty == "blank"] <- NA
  ok <- is.na(hex) | hex == "" | (grepl("^[1-9a-fA-F]+$", hex) & nchar(hex) %in% c(2, 4, 6, 8))
  if (!all(ok)) return(NULL)
  vapply(hex, function(h) {
    if (is.na(h)) return(-1)
    if (h == "") return(0)
    digits <- strtoi(strsplit(h, "")[[1]], 16L)
    sum(digits * 16^(seq_along(digits) - 1))
  }, numeric(1), USE.NAMES = FALSE)
}

line_params_decline <- function(params) {
  if (!(params$lineend %||% "butt") %in% c("round", "butt", "square")) {
    return("unsupported lineend")
  }
  if (!(params$linejoin %||% "round") %in% c("round", "mitre", "bevel")) {
    return("unsupported linejoin")
  }
  if (!is.numeric(params$linemitre %||% 10) || (params$linemitre %||% 10) < 1) {
    return("unsupported linemitre")
  }
  NULL
}

paths_decline <- function(data, params) {
  cols <- c("x", "y", "colour", "linewidth", "linetype", "alpha", "group")
  if (!all(cols %in% names(data))) {
    return("missing path aesthetics")
  }
  if (!is.null(params$arrow)) {
    return("arrows")
  }
  if (!is.double(data$x) || !is.double(data$y) || !is.character(data$colour)) {
    return("x, y or colour has an unsupported type")
  }
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth)) {
    return("linewidth is NA or not numeric")
  }
  if (is.null(lty_code(data$linetype))) {
    return("unsupported linetype")
  }
  # Constant along each line: every row equals its group's first row.
  cols <- unclass(data)[c("colour", "linewidth", "linetype", "alpha")]
  constant <- rs_constant_by_group(data$group, cols)
  if (is.null(constant)) {
    g <- vctrs::vec_group_id(data$group)
    first <- match(seq_len(attr(g, "n")), g)
    constant <- all(vapply(cols, function(v) all(vctrs::vec_equal(v, v[first[g]], na_equal = TRUE)), logical(1)))
  }
  if (!constant) {
    return("aesthetics vary along a line")
  }
  line_params_decline(params)
}

# Integer keys for (PANEL, group) and the rows in drawing order: by panel,
# then group (then subgroup), as draw_panel sorts each panel's data.
panel_group_order <- function(data, sub = NULL) {
  panel <- as.integer(data$PANEL)
  group <- vctrs::vec_group_id(data.frame(panel, data$group))
  order <- if (is.null(sub)) order(panel, data$group) else order(panel, data$group, sub)
  list(key = as.integer(group), order = order)
}

polygons_decline <- function(data, params) {
  cols <- c("x", "y", "colour", "fill", "linewidth", "linetype", "alpha", "group")
  if (!all(cols %in% names(data))) {
    return("missing polygon aesthetics")
  }
  if (!is.double(data$x) || !is.double(data$y)) {
    return("x or y is not double")
  }
  if (inherits(data$x, "AsIs") || inherits(data$y, "AsIs")) {
    return("x or y is AsIs")
  }
  if (anyNA(data$x) || anyNA(data$y)) {
    return("NA in x or y")
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill)) {
    return("colour or fill is not a colour vector")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth)) {
    return("linewidth is NA or not numeric")
  }
  if (is.null(lty_code(data$linetype))) {
    return("unsupported linetype")
  }
  if (!(params$rule %||% "evenodd") %in% c("evenodd", "winding")) {
    return("unsupported rule")
  }
  line_params_decline(params)
}

# Mirrors Layer$draw_geom and Geom$draw_layer (ggplot2 R/layer.R, R/geom-.R)
# for GeomPoint, without splitting the data: one lazy grob per panel.
draw_points_layer <- function(data, layout, layer) {
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- point_handle_na(layer, data)
  data$shape <- gg_translate_shape_string(data$shape)
  ok <- is.null(hybrid_decline(layer, data, layout))
  colour <- if (ok) point_colours(data$colour, data$alpha)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    return(layer$geom$draw_layer(data, layer$computed_geom_params, layout, layout$coord))
  }

  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)
  counts <- tabulate(panel, n_panels)
  shared <- list(
    x = data$x, y = data$y, panel = panel,
    rows = split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels))),
    shape = data$shape,
    size = data$size, stroke = data$stroke, colour = colour, fill = fill,
    data = data, coord = layout$coord
  )
  lapply(seq_len(n_panels), function(i) {
    if (counts[i] == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob("points", shared, i, layout$panel_params[[i]], "geom_point")
  })
}

# A lazy grob drawing one panel of a layer in Rust at draw time (see
# drawDetails.alot_hybrid_layer).
hybrid_grob <- function(kind, shared, panel, panel_params, prefix) {
  grid::grob(
    kind = kind, shared = shared, panel = panel, panel_params = panel_params,
    name = grid::grobName(prefix = prefix), cl = "alot_hybrid_layer"
  )
}

# Mirrors Layer$draw_geom, Geom$draw_layer and GeomRect$draw_panel (ggplot2
# R/layer.R, R/geom-.R, R/geom-rect.R) for coord_cartesian: one lazy grob
# per panel drawing the layer's rectGrob in Rust.
draw_rects_layer <- function(data, layout, layer) {
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- point_handle_na(layer, data)
  params <- layer$computed_geom_params
  ok <- is.null(hybrid_decline(layer, data, layout))
  # rectGrob(col = colour, fill = fill_alpha(fill, alpha)): the outline
  # keeps its colour's own alpha.
  colour <- if (ok) point_colours(as.character(data$colour), NA)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill), data$alpha)
  if (is.null(fill)) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }

  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)
  counts <- tabulate(panel, n_panels)
  # gg_par(lwd = linewidth) is linewidth * .pt; blank line types draw no
  # stroke.
  lwd <- data$linewidth * ggplot2::.pt * rect_linetype(data$linetype)
  shared <- list(
    xmin = data$xmin, xmax = data$xmax, ymin = data$ymin, ymax = data$ymax,
    panel = panel, rows = split(seq_len(nrow(data)), factor(panel, levels = seq_len(n_panels))),
    colour = colour, fill = fill, lwd = as.double(lwd),
    join = match(params$linejoin %||% "mitre", c("mitre", "round", "bevel")) - 1L,
    data = data, coord = layout$coord, geom = layer$geom, params = params
  )
  lapply(seq_len(n_panels), function(i) {
    if (counts[i] == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob("rects", shared, i, layout$panel_params[[i]], "geom_rect")
  })
}

# Codes for rs_render_paths(): lineend, linejoin.
line_style <- function(closed, rule, params, linejoin_default) {
  c(
    as.integer(closed), rule,
    match(params$lineend %||% "butt", c("round", "butt", "square")) - 1L,
    match(params$linejoin %||% linejoin_default, c("round", "mitre", "bevel")) - 1L
  )
}

# One lazy grob per panel for path-like layers, given the rows in drawing
# order and each row's path and ring (shared$order, $path, $ring).
path_grobs <- function(kind, shared, data, layout, prefix) {
  n_panels <- nlevels(as.factor(data$PANEL))
  panel <- as.integer(data$PANEL)[shared$order]
  shared$rows <- split(shared$order, factor(panel, levels = seq_len(n_panels)))
  shared$path_rows <- split(shared$path, factor(panel, levels = seq_len(n_panels)))
  shared$ring_rows <- split(shared$ring, factor(panel, levels = seq_len(n_panels)))
  shared$panel <- as.integer(data$PANEL)
  lapply(seq_len(n_panels), function(i) {
    if (length(shared$rows[[i]]) == 0) {
      return(ggplot2::zeroGrob())
    }
    hybrid_grob(kind, shared, i, layout$panel_params[[i]], prefix)
  })
}

# Stairsteps for GeomStep$draw_panel (ggplot2 R/geom-path.R): the data as
# GeomPath$draw_panel gets it. Mirrors the dapply() of stairstep() by group,
# with the orientation flipped as the geom does.
step_data <- function(data, params) {
  flipped <- isTRUE(params$flipped_aes)
  direction <- params$direction %||% "hv"
  data <- gg_flip_data(data, flipped)
  if (flipped) {
    direction <- switch(direction, hv = "vh", vh = "hv", direction)
  }
  data <- gg_dapply(data, "group", gg_stairstep, direction = direction)
  gg_flip_data(data, flipped)
}

# GeomPath$draw_panel()'s message for groups of one row, once per panel as
# ggplot2 gives it. Steps have none: stairstep() drops such groups first.
path_messages <- function(layer, data) {
  if (inherits(layer$geom, "GeomStep")) {
    return(invisible())
  }
  for (d in split(data$group, data$PANEL)) {
    if (length(d) && !anyDuplicated(d)) {
      cli::cli_inform(c(
        "{.fn {gg_snake_class(layer$geom)}}: Each group consists of only one observation.",
        i = "Do you need to adjust the {.field group} aesthetic?"
      ))
    }
  }
}

# Mirrors GeomPath$draw_panel (ggplot2 R/geom-path.R) for coord_cartesian
# when aesthetics are constant along each line: one polyline per group, in
# group order, styled from its first row; groups of one row are dropped.
draw_paths_layer <- function(data, layout, layer) {
  if (gg_empty(data)) {
    return(layer$draw_geom(data, layout))
  }
  data <- point_handle_na(layer, data)
  params <- layer$computed_geom_params
  if (!is.null(hybrid_decline(layer, data, layout))) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }
  path_messages(layer, data)
  if (inherits(layer$geom, "GeomStep")) data <- step_data(data, params)
  pg <- panel_group_order(data)
  key <- pg$key
  order <- pg$order[tabulate(key)[key[pg$order]] >= 2]
  first <- order[!duplicated(key[order])]
  path <- match(key[order], key[first]) - 1L
  colour <- point_colours(data$colour[first], data$alpha[first])
  if (is.null(colour)) {
    return(layer$geom$draw_layer(data, params, layout, layout$coord))
  }
  shared <- list(
    x = data$x, y = data$y, order = order, path = path, ring = path,
    colour = colour, fill = integer(length(first)),
    lwd = data$linewidth[first] * ggplot2::.pt,
    lty = pmax(lty_code(data$linetype[first]), 0),
    style = line_style(FALSE, 0L, params, "round"),
    mitre = as.double(params$linemitre %||% 10),
    data = data, coord = layout$coord, geom = layer$geom, params = params
  )
  shared$lwd[lty_code(data$linetype[first]) < 0] <- 0
  path_grobs("paths", shared, data, layout, "geom_path")
}

# Mirrors GeomPolygon$draw_panel (ggplot2 R/geom-polygon.R) for
# coord_cartesian: polygonGrob (one polygon per group, filled non-zero by
# ragg's drawPolygon) or, with subgroups, pathGrob (one path per group, its
# rings by subgroup, filled with `rule`). Each is styled from the group's
# first row: col = colour, fill = fill_alpha(fill, alpha).
draw_polygons_layer <- function(data, layout, layer) {
  params <- layer$computed_geom_params
  if (gg_empty(data) || !is.null(hybrid_decline(layer, data, layout))) {
    return(layer$draw_geom(data, layout))
  }
  sub <- data$subgroup
  pg <- panel_group_order(data, sub)
  key <- pg$key
  order <- pg$order
  first <- order[!duplicated(key[order])]
  path <- match(key[order], key[first]) - 1L
  ring <- if (is.null(sub)) path else vctrs::vec_group_id(data.frame(key, sub)[order, ]) - 1L
  colour <- point_colours(as.character(data$colour[first]), NA)
  fill <- if (!is.null(colour)) point_colours(as.character(data$fill[first]), data$alpha[first])
  if (is.null(fill)) {
    return(layer$draw_geom(data, layout))
  }
  codes <- lty_code(data$linetype[first])
  rule <- if (is.null(sub)) 0L else match(params$rule %||% "evenodd", c("winding", "evenodd")) - 1L
  shared <- list(
    x = data$x, y = data$y, order = order, path = path, ring = ring,
    colour = colour, fill = fill,
    lwd = ifelse(codes < 0, 0, data$linewidth[first] * ggplot2::.pt),
    lty = pmax(codes, 0),
    style = line_style(TRUE, rule, params, "round"),
    mitre = as.double(params$linemitre %||% 10),
    data = data, coord = layout$coord, geom = layer$geom, params = params
  )
  path_grobs("polygons", shared, data, layout, "geom_polygon")
}

# Packed RGBA for the Rust drawers, as col2rgb(scales::alpha(colour, alpha),
# alpha = TRUE). Rust decodes colours as farver does (hex, names,
# "transparent", NA); what it declines (farver's numeric palette indices,
# or a colour farver rejects, which errors here as in ggplot2) goes
# through scales::alpha() once per distinct value. alpha(u) keeps each
# colour's own alpha, so applying `alpha` to its hex gives the same result.
point_colours <- function(colour, alpha) {
  out <- rs_point_colours(colour, alpha)
  if (is.null(out)) {
    u <- unique(colour[!is.na(colour)])
    out <- rs_point_colours(scales::alpha(u)[match(colour, u)], alpha)
  }
  out
}

# Worker threads for Rust rendering (PHASE2.md, User API):
# options(alot.threads), then ALOT_THREADS, else the available cores capped
# at 8 (0, resolved in Rust), or 2 under R CMD check's _R_CHECK_LIMIT_CORES_.
render_threads <- function() {
  n <- getOption("alot.threads", Sys.getenv("ALOT_THREADS"))
  if (is.character(n) && !nzchar(n)) {
    limit <- Sys.getenv("_R_CHECK_LIMIT_CORES_")
    return(if (nzchar(limit) && !identical(toupper(limit), "FALSE")) 2L else 0L)
  }
  n <- suppressWarnings(as.integer(n))
  if (length(n) != 1 || is.na(n) || n < 1) {
    cli::cli_abort("{.code alot.threads} / {.envvar ALOT_THREADS} must be a positive integer.")
  }
  n
}

# Pixels per inch of the current device if it is a ragg raster device.
raster_device_res <- function() {
  if (!startsWith(names(grDevices::dev.cur()), "agg_")) {
    return(NULL)
  }
  grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1]
}

# Range a view scale rescales from, if it rescales positions linearly with
# scales::rescale: ScaleContinuous$rescale with the default rescaler (also
# date and datetime scales), or
# ScaleDiscretePosition$rescale, whose map() passes mapped (numeric)
# positions through (ggplot2 R/scale-.R, R/scale-discrete-.R).
linear_range <- function(view) {
  range <- view$continuous_range
  scale <- view$scale
  # `$` wraps ggproto fields that are functions; compare the inner one.
  inner <- function(f) environment(f)$f
  # Date and datetime position scales inherit ScaleContinuous, not
  # ScaleContinuousPosition, and rescale the same way.
  position <- any(scale$aesthetics %in% c("x", "y"))
  continuous <- inherits(scale, "ScaleContinuous") && position &&
    identical(inner(scale$rescale), inner(ggplot2::ScaleContinuous$rescale)) &&
    identical(inner(scale$rescaler), scales::rescale)
  discrete <- inherits(scale, "ScaleDiscretePosition") &&
    identical(inner(scale$rescale), inner(ggplot2::ScaleDiscretePosition$rescale)) &&
    identical(inner(scale$map), inner(ggplot2::ScaleDiscretePosition$map))
  ok <- (continuous || discrete) &&
    is.numeric(range) && length(range) == 2 && all(is.finite(range)) && range[1] != range[2]
  if (ok) range
}

#' @exportS3Method grid::drawDetails
drawDetails.alot_hybrid_layer <- function(x, recording) {
  res <- raster_device_res()
  tr <- grid::current.transform()
  x_range <- linear_range(x$panel_params$x)
  y_range <- linear_range(x$panel_params$y)
  if (is.null(res) || tr[1, 2] != 0 || tr[2, 1] != 0 || is.null(x_range) || is.null(y_range)) {
    return(grid::grid.draw(hybrid_fallback_grob(x)))
  }

  # Panel corners in device pixels, from the top-left.
  lo <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  hi <- grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
  dev_h <- grDevices::dev.size("in")[2]
  left <- lo$x * res
  right <- hi$x * res
  top <- (dev_h - hi$y) * res
  bottom <- (dev_h - lo$y) * res
  # Render to the pixel-aligned box around the panel so the raster maps 1:1.
  x0 <- floor(left)
  y0 <- floor(top)
  w <- ceiling(right) - x0
  h <- ceiling(bottom) - y0
  rect <- c(left - x0, top - y0, right - left, bottom - top)
  dims <- as.integer(c(w, h))

  s <- x$shared
  rows <- s$rows[[x$panel]]
  img <- switch(x$kind,
    points = rs_render_points(
      s$x, s$y, rows, x_range, y_range, rect, dims,
      s$shape, s$size, s$stroke, s$colour, s$fill,
      c(ggplot2::.pt, ggplot2::.stroke, res),
      render_threads()
    ),
    rects = rs_render_rects(
      s$xmin, s$xmax, s$ymin, s$ymax, rows, x_range, y_range, rect, dims,
      s$colour, s$fill, s$lwd, s$join, res, render_threads()
    ),
    paths = ,
    polygons = rs_render_paths(
      s$x, s$y, rows, s$path_rows[[x$panel]], s$ring_rows[[x$panel]],
      s$colour, s$fill, as.double(s$lwd), as.double(s$lty), s$style, s$mitre,
      x_range, y_range, rect, dims, res, render_threads()
    )
  )
  if (is.null(img)) {
    return(grid::grid.draw(hybrid_fallback_grob(x)))
  }
  # Rust clipped each mark to the panel, as ragg does; clipping the raster
  # again would cut the edge pixels twice.
  grid::pushViewport(grid::viewport(clip = "off"))
  on.exit(grid::popViewport())
  grid::grid.raster(
    img,
    x = grid::unit(x0 / res - lo$x, "in"),
    y = grid::unit(dev_h - (y0 + h) / res - lo$y, "in"),
    width = grid::unit(w / res, "in"),
    height = grid::unit(h / res, "in"),
    just = c("left", "bottom"),
    interpolate = FALSE
  )
}

# ggplot2's own grob for the panel, for devices and viewports the Rust
# drawers don't handle.
hybrid_fallback_grob <- function(x) {
  s <- x$shared
  data <- vctrs::vec_slice(s$data, s$panel == x$panel)
  switch(x$kind,
    points = ggplot2::GeomPoint$draw_panel(data, x$panel_params, s$coord),
    rects = s$geom$draw_panel(
      data, x$panel_params, s$coord,
      lineend = s$params$lineend %||% "butt", linejoin = s$params$linejoin %||% "mitre"
    ),
    paths = s$geom$draw_panel(
      data, x$panel_params, s$coord,
      lineend = s$params$lineend %||% "butt", linejoin = s$params$linejoin %||% "round",
      linemitre = s$params$linemitre %||% 10
    ),
    polygons = s$geom$draw_panel(
      data, x$panel_params, s$coord, rule = s$params$rule %||% "evenodd",
      lineend = s$params$lineend %||% "butt", linejoin = s$params$linejoin %||% "round",
      linemitre = s$params$linemitre %||% 10
    )
  )
}

# Why a ribbon layer (GeomRibbon$draw_group(), also GeomArea and
# GeomDensity) or a geom_smooth() layer (GeomSmooth$draw_group(): the
# ribbon, then GeomLine's path) isn't drawn in Rust, or NULL. Declines what
# ggplot2 would draw as a gradient or abort on (aesthetics varying along a
# ribbon), and groups of fewer than two rows (one-point polylines, and the
# path's message for them).
ribbons_decline <- function(data, params, smooth) {
  flipped <- isTRUE(params$flipped_aes)
  nm <- if (flipped) c(pos = "y", lo = "xmin", hi = "xmax", val = "x") else c(pos = "x", lo = "ymin", hi = "ymax", val = "y")
  ribbon <- !smooth || (isTRUE(params$se) && all(nm[c("lo", "hi")] %in% names(data)))
  pos <- c(nm[["pos"]], if (ribbon) nm[c("lo", "hi")], if (smooth) nm[["val"]])
  cols <- c(pos, "colour", "fill", "linewidth", "linetype", "alpha", "group")
  if (!all(cols %in% names(data))) {
    return("missing ribbon aesthetics")
  }
  if (!all(vapply(data[pos], is.double, logical(1))) || any(vapply(data[pos], inherits, logical(1), "AsIs"))) {
    return("positions are not double")
  }
  if (anyNA(data[pos])) {
    return("NA in a ribbon's positions")
  }
  if (!is_colour_vector(data$colour) || !is_colour_vector(data$fill)) {
    return("colour or fill is not a colour vector")
  }
  if (!is.numeric(data$linewidth) || anyNA(data$linewidth) || !(is.numeric(data$alpha) || all(is.na(data$alpha)))) {
    return("linewidth or alpha is not numeric")
  }
  if (is.null(lty_code(data$linetype))) {
    return("unsupported linetype")
  }
  if (!smooth && !(params$outline.type %||% "both") %in% c("both", "upper", "lower", "full")) {
    return("unsupported outline.type")
  }
  key <- vctrs::vec_group_id(data.frame(as.integer(data$PANEL), data$group))
  if (any(tabulate(key) < 2)) {
    return("a group of fewer than two rows")
  }
  cols <- unclass(data)[c("colour", "fill", "linewidth", "linetype", "alpha")]
  first <- match(seq_len(attr(key, "n")), key)
  constant <- all(vapply(cols, function(v) all(vctrs::vec_equal(v, v[first[key]], na_equal = TRUE)), logical(1)))
  if (!constant) {
    return("aesthetics vary along a ribbon")
  }
  line_params_decline(params)
}
