library(ggplot2)

test_that("alot_print draws the plot and returns it invisibly", {
  p <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point() + facet_wrap(~am)
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  expect_invisible(out <- alot_print(p))
  expect_identical(out, p)
  expect_identical(last_plot(), p)
  # The page is one grob, which draws ggplot2's gtable of the alot build on a
  # vector device.
  expect_true(any(grepl("^alot_page", grid::grid.ls(print = FALSE)$name)))
})

test_that("alot_print draws into a viewport", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 2)))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  expect_equal(sum(grepl("^alot_page", grid::grid.ls(print = FALSE)$name)), 2)
})

test_that("alot_print rejects non-ggplot input", {
  expect_error(alot_print(1), "ggplot object")
})

# alot_print() on raster devices (the plot pane): the page is rendered at the
# size of the device each time the plot is drawn, so replaying it on a device
# of another size, as RStudio does when the pane is resized, renders again.
capture_device <- function(width, height, res = 96) {
  cap <- ragg::agg_capture(width = width, height = height, res = res)
  grDevices::dev.control("enable")
  cap
}

# The pixels of the page `render_raster()` makes (the unmocked one).
real_render_raster <- render_raster
page_at <- function(built, width, height, res = 96) {
  size <- list(width = width, height = height, units = "px", res = res, bg = "white", scaling = 1)
  as.integer(real_render_raster(built, size)$raster)
}

test_that("alot_print renders at the device's size and again at each replay", {
  p <- ggplot(mtcars, aes(wt, mpg, colour = qsec)) + geom_point() + facet_wrap(~cyl)
  built <- alot_build(p)
  cap <- capture_device(700, 500)
  alot_print(p)
  drawn <- cap(native = TRUE)
  rec <- grDevices::recordPlot()
  grDevices::dev.off()
  expect_identical(dim(drawn), c(500L, 700L))
  expect_identical(as.integer(drawn), page_at(built, 700, 500))

  for (size in list(c(400, 300, 96), c(900, 400, 96), c(600, 450, 192))) {
    cap2 <- capture_device(size[1], size[2], size[3])
    grDevices::replayPlot(rec)
    replayed <- cap2(native = TRUE)
    grDevices::dev.off()
    expect_identical(dim(replayed), as.integer(size[2:1]))
    expect_identical(as.integer(replayed), page_at(built, size[1], size[2], size[3]))
  }
})

test_that("alot_print sizes the page to a viewport", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  sizes <- list()
  local_mocked_bindings(render_raster = function(built, size) {
    sizes[[length(sizes) + 1L]] <<- c(size$width, size$height)
    real_render_raster(built, size)
  })
  cap <- capture_device(800, 400)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 2)))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  grDevices::dev.off()
  expect_equal(sizes, list(c(400, 400), c(400, 400)))
})

test_that("alot_print draws the gtable where there is no raster page", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  local_mocked_bindings(render_raster = function(built, size) stop("no raster on a vector device"))
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off())
  expect_no_error(alot_print(p))
  expect_true(any(grepl("^alot_page", grid::grid.ls(print = FALSE)$name)))
})

test_that("alot_print draws the gtable for the ggplot2 tier", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  local_mocked_bindings(render_raster = function(built, size) list(tier = "ggplot2", raster = NULL))
  cap <- capture_device(300, 200)
  alot_print(p)
  drawn <- cap(native = TRUE)
  grDevices::dev.off()
  expect_gt(mean(as.integer(drawn) != -1L), 0.1)
})

test_that("a replay repeats no warnings", {
  p <- ggplot(data.frame(x = c(1, NA, 3), y = 1:3), aes(x, y)) + geom_point()
  cap <- capture_device(300, 200)
  expect_warning(alot_print(p), "missing")
  rec <- grDevices::recordPlot()
  grDevices::dev.off()
  cap2 <- capture_device(400, 300)
  expect_no_warning(grDevices::replayPlot(rec))
  grDevices::dev.off()
})

test_that("options(alot.autoprint) sends ggplot's print to alot_print", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  calls <- 0
  local_mocked_bindings(alot_print = function(x, ...) calls <<- calls + 1)
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off())
  withr::local_options(alot.autoprint = TRUE)
  print(p)
  plot(p)
  expect_equal(calls, 2)
  options(alot.autoprint = FALSE)
  print(p)
  expect_equal(calls, 2)
})

test_that("the page is rendered at the density of RStudio's bitmap", {
  withr::local_options(alot.pixel_ratio = NULL)
  # Other devices render at their own density, whatever the ratio.
  expect_equal(device_res("agg_capture", 96, 2, "Darwin"), 96)
  expect_equal(device_res("png", 72, NULL, "Darwin"), 72)
  # Quartz devices report points whatever their resolution: unknown.
  expect_identical(device_res("quartz_off_screen", 72, NULL, "Darwin"), NA_real_)
  expect_identical(device_res("quartz", 72, 2, "Darwin"), NA_real_)
  # RStudio: trunc(96 * dpr), whichever density the backend reports.
  expect_equal(device_res("RStudioGD", 192, 2, "Darwin"), 192)
  expect_equal(device_res("RStudioGD", 72, 2, "Darwin"), 192)
  expect_equal(device_res("RStudioGD", 72, 1, "Darwin"), 96)
  expect_equal(device_res("RStudioGD", 72, 2.2, "Darwin"), 211)
  expect_equal(device_res("RStudioGD", 120, 1.25, "Windows"), 120)
  expect_equal(device_res("RStudioGD", 86, 0.9, "Linux"), 86)
  # Without the ratio: Quartz is assumed retina, other backends are right.
  expect_equal(device_res("RStudioGD", 72, NULL, "Darwin"), 192)
  expect_equal(device_res("RStudioGD", 86, NULL, "Darwin"), 86)
  expect_equal(device_res("RStudioGD", 72, NULL, "Linux"), 72)
  expect_null(rstudio_pixel_ratio())
  # The option overrides the ratio in the plot pane only.
  withr::local_options(alot.pixel_ratio = 3)
  expect_equal(device_res("RStudioGD", 72, 2, "Darwin"), 216)
  expect_equal(device_res("agg_capture", 96, NULL, "Linux"), 96)
  withr::local_options(alot.pixel_ratio = "x")
  expect_equal(device_res("RStudioGD", 72, 1.5, "Linux"), 144)
})

test_that("alot_print renders at the ratio and draws it into the device's size", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  sizes <- list()
  local_mocked_bindings(render_raster = function(built, size) {
    sizes[[length(sizes) + 1L]] <<- c(size$width, size$height, size$res)
    real_render_raster(built, size)
  })
  ratio <- 1
  local_mocked_bindings(device_res = function(dpi, ...) dpi * ratio)
  cap <- capture_device(400, 300)
  alot_print(p)
  ratio <- 2
  alot_print(p)
  drawn <- cap(native = TRUE)
  grDevices::dev.off()
  expect_equal(sizes, list(c(400, 300, 96), c(800, 600, 192)))
  expect_identical(dim(drawn), c(300L, 400L))
})
