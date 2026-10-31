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
#' `postscript()` and the like), Quartz devices other than RStudio's plot
#' pane (whose resolution R can't see), rotated viewports and plots whose
#' tier is ggplot2 are drawn from [ggplot2::ggplot_gtable()] instead.
#' Warnings are raised on the first draw only.
#'
#' In RStudio's plot pane the page is rendered at the resolution of the
#' bitmap RStudio draws the pane into: 96 dpi times the screen's device pixel
#' ratio, which includes the display's scaling and RStudio's zoom. Set
#' `options(alot.pixel_ratio = )` to the number of rendered pixels per device
#' pixel to override this in the plot pane.
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

# RStudio's device pixel ratio (screen pixels per CSS pixel, including the
# IDE's zoom), or NULL outside RStudio. RStudio registers rs_devicePixelRatio
# as a native routine of the embedding process (rstudio
# src/cpp/session/modules/SessionGraphics.cpp).
rstudio_pixel_ratio <- function() {
  dpr <- tryCatch(.Call("rs_devicePixelRatio", PACKAGE = "(embedding)"), error = function(e) NULL)
  if (is.numeric(dpr) && length(dpr) == 1 && is.finite(dpr) && dpr > 0) dpr else NULL
}

# Pixels per inch to render the page at on the current device, whose own
# density is `dpi`. RStudio's plot pane forwards drawing to a shadow bitmap
# device opened with res = trunc(96 * dpr) at the pane's CSS size times dpr
# (Mirrors shadowDevDesc, rstudio
# src/cpp/r/session/graphics/RShadowPngGraphicsHandler.cpp), and copies its
# ipr, so the ragg, cairo and windows backends already report that density;
# the Quartz backend reports points (72 dpi) whatever the ratio. The device's
# size in inches is the same for all of them, so the page has the shadow
# device's pixels. Without RStudio's ratio, Quartz is assumed to be retina.
# Other Quartz devices (quartz(), png() on a Mac, RStudio's exports with that
# backend) report points whatever their resolution (ipr 1/72, R
# src/library/grDevices/src/devQuartz.c) and can't capture, so their density
# is unknown: NA, and the plot is drawn from the gtable. Other devices render
# at their own density. `options(alot.pixel_ratio = )` overrides this in the
# plot pane only.
device_res <- function(device = names(grDevices::dev.cur()), dpi = grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1],
                       dpr = if (identical(device, "RStudioGD")) rstudio_pixel_ratio(), system = Sys.info()[["sysname"]]) {
  if (grepl("^quartz", device)) {
    return(NA_real_)
  }
  if (!identical(device, "RStudioGD") || !is.finite(dpi)) {
    return(dpi)
  }
  ratio <- getOption("alot.pixel_ratio")
  if (is.numeric(ratio) && length(ratio) == 1 && is.finite(ratio) && ratio > 0) {
    return(dpi * ratio)
  }
  if (!is.null(dpr)) {
    return(trunc(96 * dpr))
  }
  if (dpi == 72 && identical(system, "Darwin")) {
    return(192)
  }
  dpi
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
  # The device's pixels can be larger than the bitmap behind it (RStudio's
  # Quartz backend reports points). The page is rendered at the bitmap's
  # density and drawn into the same viewport, so it lands 1:1 on the bitmap.
  dev_res <- grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1]
  res <- device_res(dpi = dev_res)
  w <- round(w_in * res)
  h <- round(h_in * res)
  if (vector_device() || tr[1, 2] != 0 || tr[2, 1] != 0 || !is.finite(res) || !is.finite(w) || !is.finite(h) || w < 1 || h < 1) {
    return(quiet(draw_gtable(x$built)))
  }
  built <- x$built
  bg <- plot_background(built)
  out <- quiet(render_raster(built, list(width = w, height = h, units = "px", res = res, bg = bg, scaling = 1)))
  if (is.null(out$raster)) {
    return(quiet(draw_gtable(built)))
  }
  grid::grid.raster(out$raster, x = 0, y = 0, just = c(0, 0), width = grid::unit(1, "npc"), height = grid::unit(1, "npc"), interpolate = res != dev_res)
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
