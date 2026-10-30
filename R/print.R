# Mirrors the print/plot method for class_ggplot (ggplot2 4.0.3, R/plot.R),
# with ggplot_build() replaced by alot_build().

#' Build and draw a ggplot with alot
#'
#' The counterpart of `print()` for a ggplot: builds `x` with [alot_build()]
#' instead of [ggplot2::ggplot_build()], then renders it with
#' [ggplot2::ggplot_gtable()] and draws it on the current device.
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

  data <- alot_build(x)

  gtable <- ggplot2::ggplot_gtable(data)
  if (is.null(vp)) {
    grid::grid.draw(gtable)
  } else {
    if (is.character(vp)) grid::seekViewport(vp) else grid::pushViewport(vp)
    grid::grid.draw(gtable)
    grid::upViewport()
  }

  if (isTRUE(getOption("BrailleR.VI")) && rlang::is_installed("BrailleR")) {
    print(asNamespace("BrailleR")$VI(x))
  }

  invisible(x)
}
