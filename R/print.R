# Mirrors the print/plot method for class_ggplot (ggplot2 4.0.3, R/plot.R),
# with ggplot_build() replaced by alot_build() and the gtable drawn by an
# alot_page grob, which renders the page with the best tier at the size the
# device gives it each time it is drawn.

#' Build and draw a ggplot with alot
#'
#' The counterpart of `print()` for a ggplot: builds `x` with [alot_build()]
#' instead of [ggplot2::ggplot_build()], then draws it on the current device.
#'
#' On a raster device (RStudio's plot pane, a window, a PNG device) the page
#' is rendered by the best tier alot has for the plot (see
#' [alot_render_coverage()]) at the device's size in pixels and drawn as a
#' raster. The plot is a grid grob that renders each time it is drawn, so
#' when the device is resized, or RStudio replays the plot to export it,
#' the plot is laid out and rendered again at the new size. Only the built
#' plot is kept between draws. Vector devices (`pdf()`, `svg()`,
#' `postscript()` and the like), rotated viewports and plots whose tier is
#' ggplot2 are drawn from [ggplot2::ggplot_gtable()] instead. Warnings are
#' raised on the first draw only.
#'
#' On a screen with more pixels than the device reports (a retina display),
#' set `options(alot.pixel_ratio = 2)` (the number of screen pixels per
#' device pixel) so the page is rendered at the screen's density.
#'
#' With `options(alot.autoprint = TRUE)`, printing a ggplot (including
#' autoprinting `p` at the console) calls `alot_print()`.
#'
#' @param x A ggplot object.
#' @param newpage Draw a new (empty) page first?
#' @param vp Viewport to draw the plot in, or the name of one to seek.
#' @param ... Not used.
#' @return Invisibly returns `x`.
#' @export
alot_print <- function(x, newpage = is.null(vp), vp = NULL, ...) {
  ggplot2::set_last_plot(x)
  if (newpage) grid::grid.newpage()

  # Record dependency on 'ggplot2' on the display list
  # (AFTER grid.newpage())
  grDevices::recordGraphics(
    requireNamespace("ggplot2", quietly = TRUE),
    list(),
    getNamespace("ggplot2")
  )

  grob <- alot_page_grob(alot_build(x))
  if (is.null(vp)) {
    grid::grid.draw(grob)
  } else {
    if (is.character(vp)) grid::seekViewport(vp) else grid::pushViewport(vp)
    grid::grid.draw(grob)
    grid::upViewport()
  }

  if (isTRUE(getOption("BrailleR.VI")) && rlang::is_installed("BrailleR")) {
    print(asNamespace("BrailleR")$VI(x))
  }

  invisible(x)
}

# A grob that draws a built plot at the size of the viewport it is drawn in,
# every time it is drawn (see drawDetails.alot_page). `state` counts the
# draws.
alot_page_grob <- function(built) {
  grid::grob(built = built, state = new.env(), name = grid::grobName(prefix = "alot_page"), cl = "alot_page")
}

# Devices that draw vector graphics: a raster page is not drawn on them.
vector_device <- function() {
  grepl("^(pdf|postscript|cairo_pdf|cairo_ps|svg|svglite|xfig|pictex|tikz|devSVG|win\\.metafile|emf)", names(grDevices::dev.cur()))
}

# Screen pixels per device pixel: `options(alot.pixel_ratio = 2)` for a
# retina screen, 1 otherwise.
device_pixel_ratio <- function() {
  ratio <- getOption("alot.pixel_ratio", 1)
  if (is.numeric(ratio) && length(ratio) == 1 && is.finite(ratio) && ratio >= 1) ratio else 1
}

# Mirrors ggplot2's print method's drawing of the gtable, which lays the
# plot out on the device with ggplot_gtable().
draw_gtable <- function(built) {
  grid::grid.draw(ggplot2::ggplot_gtable(built))
}

#' @exportS3Method grid::drawDetails
drawDetails.alot_page <- function(x, recording) {
  state <- x$state
  state$draws <- (state$draws %||% 0L) + 1L
  # Replays (resizes, exports) repeat the first draw's warnings.
  quiet <- function(expr) {
    if (state$draws > 1L) suppressWarnings(expr) else expr
  }
  tr <- grid::current.transform()
  w_in <- grid::convertWidth(grid::unit(1, "npc"), "in", valueOnly = TRUE)
  h_in <- grid::convertHeight(grid::unit(1, "npc"), "in", valueOnly = TRUE)
  # The device's pixels are logical on a high-density screen: RStudio's plot
  # pane on a retina Mac reports half the pixels it shows, and scales up a
  # raster drawn at that size. The page is rendered at the screen's density
  # and drawn into the same viewport, so the device scales it down.
  ratio <- device_pixel_ratio()
  res <- grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1] * ratio
  w <- round(w_in * res)
  h <- round(h_in * res)
  if (vector_device() || tr[1, 2] != 0 || tr[2, 1] != 0 || !is.finite(res) || !is.finite(w) || !is.finite(h) || w < 1 || h < 1) {
    return(quiet(draw_gtable(x$built)))
  }
  built <- x$built
  bg <- gg_get_plot_background(built@plot, NULL)
  out <- quiet(render_raster(built, list(width = w, height = h, units = "px", res = res, bg = bg, scaling = 1)))
  if (is.null(out$raster)) {
    return(quiet(draw_gtable(built)))
  }
  grid::grid.raster(out$raster, x = 0, y = 0, just = c(0, 0), width = grid::unit(1, "npc"), height = grid::unit(1, "npc"), interpolate = FALSE)
}

# options(alot.autoprint = TRUE): ggplot2's print and plot methods for
# ggplot call alot_print(). Installed when alot loads; with the option off
# they call the methods they replaced.
install_autoprint <- function() {
  class <- ggplot2::class_ggplot
  name <- "ggplot2::ggplot"
  print_original <- utils::getS3method("print", name)
  plot_original <- utils::getS3method("plot", name)
  S7::method(print, class) <- function(x, ...) {
    if (isTRUE(getOption("alot.autoprint"))) alot_print(x, ...) else print_original(x, ...)
  }
  S7::method(plot, class) <- function(x, ...) {
    if (isTRUE(getOption("alot.autoprint"))) alot_print(x, ...) else plot_original(x, ...)
  }
}
