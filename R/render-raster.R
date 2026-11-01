# geom_raster() in the full tier and, through the "marks" drawer, the
# hybrid tier (task S1.1; SPATIAL.md, Architecture "Raster").
# Mirrors GeomRaster$draw_panel() (ggplot2 R/geom-raster.R): the cell
# positions from resolution(x, FALSE), the colour matrix of
# alpha(fill, alpha) with NA (transparent) for absent cells, and the
# rasterGrob() over the range of the cells' xmin-xmax and ymin-ymax. Rust
# builds the matrix straight from the fill strings, per panel, and draws it
# as ragg's drawRaster() draws it with interpolate = FALSE
# (alot-core/src/render/raster.rs). Under coord_flip() the matrix is built
# from the unflipped x and y, as upstream builds it before
# coord$transform(), and only its placement flips.

raster_kind <- function(geom) {
  if (identical(geom, ggplot2::GeomRaster) &&
    identical(environment(geom$draw_panel)$f, environment(ggplot2::GeomRaster$draw_panel)$f)) {
    "raster"
  }
}

# Why a geom_raster() layer isn't drawn in Rust, or NULL. Declines what
# upstream draws differently (interpolate = TRUE, a partial alpha, whose
# premultiplication ragg's raster conversion doesn't share with the
# drawers here) or aborts on (pattern fills, which aren't a colour vector).
raster_decline <- function(data, params) {
  cols <- c("x", "y", "fill", "alpha", "xmin", "xmax", "ymin", "ymax")
  if (!all(cols %in% names(data))) {
    return("missing raster aesthetics")
  }
  if (!isFALSE(params$interpolate %||% FALSE)) {
    return("interpolate = TRUE")
  }
  pos <- data[c("x", "y", "xmin", "xmax", "ymin", "ymax")]
  if (!all(vapply(pos, is.numeric, logical(1))) || any(vapply(pos, inherits, logical(1), "AsIs"))) {
    return("positions are not numeric")
  }
  if (!is.character(data$fill)) {
    return("fill is not a colour vector")
  }
  if (!(is.double(data$alpha) || rs_all_na_logical(data$alpha))) {
    return("alpha is not numeric")
  }
  rs_raster_check(pos, data$fill, data$alpha)
}

# The full tier's spec of a geom_raster() layer (raster_layers() in
# alot-r/src/page.rs reads it): borrowed columns, the panel of each row
# when there are several, and the data x and y ranges (`ranges`, already
# swapped back to data space under coord_flip(), see full_layer_specs()).
full_raster <- function(data, ranges, n_panels, flip) {
  num <- function(v) if (is.double(v)) v else as.double(v)
  c(ranges, list(
    x = num(data$x), y = num(data$y),
    xmin = num(data$xmin), xmax = num(data$xmax), ymin = num(data$ymin), ymax = num(data$ymax),
    fill = data$fill, alpha = data$alpha, flip = as.double(flip),
    # resolution() is 1 for integer positions.
    integer = as.double(c(is.integer(data$x), is.integer(data$y))),
    panel = if (n_panels > 1) as.integer(data$PANEL)
  ))
}
