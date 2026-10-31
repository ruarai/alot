# geom_point() in the full tier (R5.1): single-panel point plots without
# legends, drawn by alot-core's page drawers against ggplot2 on ragg.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_points <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label)))
  expect_null(expect_layout_matches(b, utils::modifyList(render_size, size), label = label))
}

base <- ggplot(mtcars, aes(wt, mpg))

test_that("points draw as ggplot2 draws them", {
  check_points(base + geom_point(), "default points")
  check_points(base + geom_point(size = 4, colour = "red", alpha = 0.4), "size, colour and alpha")
  check_points(base + geom_point(shape = 21, fill = "steelblue", colour = "black", stroke = 2, size = 3), "filled shape")
  check_points(base + geom_point(shape = "square", size = 5), "shape name")
  check_points(base + geom_point(aes(size = hp), show.legend = FALSE), "mapped size")
  check_points(base + geom_point(aes(shape = factor(cyl)), show.legend = FALSE), "mapped shape")
  check_points(base + geom_point() + geom_point(aes(wt, mpg + 3), colour = "blue"), "two layers")
  check_points(base + geom_point() + geom_blank(), "point and blank layers")
})

test_that("scales, expansion, clip and themes", {
  check_points(base + geom_point() + scale_x_log10() + scale_y_log10(), "log scales")
  check_points(base + geom_point() + scale_y_sqrt(), "sqrt scale")
  check_points(base + geom_point() + scale_x_reverse(), "reversed scale")
  check_points(base + geom_point() + coord_cartesian(xlim = c(2, 4), ylim = c(15, 25)), "zoomed, clipped")
  check_points(base + geom_point(size = 6) + coord_cartesian(xlim = c(2, 4), expand = FALSE), "no expansion")
  check_points(base + geom_point() + coord_fixed(), "fixed ratio")
  check_points(base + geom_point() + theme_bw() + labs(title = "Points", x = "Weight"), "theme_bw")
  check_points(
    ggplot(data.frame(d = as.Date("2020-01-01") + 0:9, v = c(3, 1, 4, 1, 5, 9, 2, 6, 5, 3)), aes(d, v)) + geom_point(),
    "dates"
  )
  check_points(
    ggplot(data.frame(x = c("a", "b", "c", "a"), y = c(1, 2, 3, 2)), aes(x, y)) + geom_point(),
    "discrete x"
  )
})

test_that("missing, infinite, empty and single-row data", {
  d <- data.frame(x = c(1, 2, NA, 4, Inf, -Inf, 3), y = c(1, 3, 2, NA, 2, 2, Inf))
  suppressWarnings(check_points(ggplot(d, aes(x, y)) + geom_point(), "NA and Inf"))
  check_points(ggplot(mtcars[1, ], aes(wt, mpg)) + geom_point(), "one row")
  check_points(ggplot(mtcars[0, ], aes(wt, mpg)) + geom_point(), "no rows")
  check_points(ggplot(data.frame(x = 1:5, y = c(2L, 4L, 1L, 3L, 5L)), aes(x, y)) + geom_point(), "integers")
})

test_that("a higher resolution", {
  check_points(base + geom_point(aes(colour = qsec), show.legend = FALSE), "colour scale at 150 dpi",
    size = list(width = 600, height = 450, res = 150))
})

test_that("missing values warn once, as ggplot2 does", {
  withr::local_options(alot.full_tier = TRUE)
  d <- data.frame(x = c(1, NA, 3), y = 1:3)
  b <- suppressWarnings(ggplot_build(ggplot(d, aes(x, y)) + geom_point()))
  expect_warning(out <- render_raster(b, render_size), "Removed 1 row")
  expect_identical(out$tier, "full")
})

test_that("alot_png() uses the full tier for point plots", {
  f <- withr::local_tempfile(fileext = ".png")
  withr::local_options(alot.full_tier = NULL)
  set.seed(1)
  out <- alot_png(base + geom_point(), f, width = 4, height = 3, dpi = 96)
  expect_identical(attr(out, "tier"), "full")
  withr::local_options(alot.full_tier = FALSE)
  expect_identical(attr(alot_png(base + geom_point(), f, width = 4, height = 3, dpi = 96), "tier"), "hybrid")
})

test_that("point plots the full tier doesn't draw decline to another tier", {
  tier <- function(p) {
    set.seed(1)
    b <- suppressWarnings(suppressMessages(ggplot_build(p)))
    suppressMessages(render_raster(b, render_size)$tier)
  }
  # Facets and inside legends drop to the hybrid tier; so do
  # other layers, other layers, clip off, other coords and shapes.
  expect_identical(tier(base + geom_point(aes(colour = factor(cyl))) + theme(legend.position = "inside")), "hybrid")
  expect_identical(tier(base + geom_point() + facet_wrap(vars(cyl))), "hybrid")
  expect_identical(tier(base + geom_point() + geom_smooth(method = "lm", formula = y ~ x)), "hybrid")
  expect_identical(tier(base + geom_point() + coord_cartesian(clip = "off")), "ggplot2")
  expect_identical(tier(base + geom_point() + coord_flip()), "ggplot2")
  expect_identical(tier(base + geom_point() + coord_trans(x = "sqrt")), "ggplot2")
  expect_identical(tier(base + geom_point(shape = 99)), "ggplot2")
  expect_identical(tier(base + geom_point(shape = "a")), "ggplot2")
  expect_identical(tier(base + geom_point(aes(x = I(wt / 6)))), "ggplot2")
})

test_that("the full tier names why it declines a point plot", {
  b <- ggplot_build(base + geom_point(shape = "a"))
  expect_match(attr(render_full(b, render_size), "reason"), "character pch|unsupported shape")
  b <- ggplot_build(base + geom_point() + geom_line())
  expect_match(attr(render_full(b, render_size), "reason"), "layers other than")
})
