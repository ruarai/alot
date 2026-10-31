# alot_ggsave(): a drop-in for ggplot2::ggsave() (PHASE2.md, User API).
# Mirrors ggsave() (ggplot2 R/save.R) for paths, sizes, units and the
# background; .png files are drawn with alot_png(), anything else is passed
# to ggsave() unchanged.

#' Save a plot, rendering PNGs with alot
#'
#' Has the signature of [ggplot2::ggsave()]. When the file is a PNG (a
#' `.png` extension and no `device`, or `device = "png"`), the plot is drawn
#' with [alot_png()] at the size, resolution and background `ggsave()` would
#' use with ragg. Any other file or device is passed to `ggsave()`
#' unchanged.
#'
#' @inheritParams ggplot2::ggsave
#' @param ... Passed to [alot_png()] (and from there to the ragg device) for
#'   PNGs, otherwise to [ggplot2::ggsave()].
#' @return `filename`, invisibly. For PNGs, with attribute `"tier"` as in
#'   [alot_png()].
#' @export
alot_ggsave <- function(filename, plot = ggplot2::get_last_plot(),
                        device = NULL, path = NULL, scale = 1,
                        width = NA, height = NA, units = c("in", "cm", "mm", "px"),
                        dpi = 300, limitsize = TRUE, bg = NULL,
                        create.dir = FALSE, ...) {
  png <- if (is.null(device)) {
    is.character(filename) && length(filename) == 1 && grepl("\\.png$", filename, ignore.case = TRUE)
  } else {
    identical(device, "png")
  }
  if (!png || !(ggplot2::is_ggplot(plot) || inherits(plot, "ggplot2::ggplot_built"))) {
    return(ggplot2::ggsave(
      filename, plot = plot, device = device, path = path, scale = scale,
      width = width, height = height, units = units, dpi = dpi,
      limitsize = limitsize, bg = bg, create.dir = create.dir, ...
    ))
  }
  filename <- gg_validate_path(path, filename, create.dir)
  dpi <- gg_parse_dpi(dpi)
  dim <- gg_plot_dim(c(width, height), scale = scale, units = units[1], limitsize = limitsize, dpi = dpi)
  # alot_png() takes a NULL `bg` from the built plot's theme, as
  # get_plot_background() would from the plot's.
  out <- alot_png(plot, filename, width = dim[1], height = dim[2], units = "in", dpi = dpi, bg = bg, ...)
  invisible(structure(filename, tier = attr(out, "tier")))
}
