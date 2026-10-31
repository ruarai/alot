# Core geoms in the full tier (R6.1): line, path, step, col/bar, rect, tile
# and text, drawn by alot-core's page drawers against ggplot2 on ragg, and
# step in the hybrid tier.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_geom <- function(p, label, ..., max = 32, size = list(), tier = "full") {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = tier, label = label)))
  if (tier == "full") {
    expect_null(expect_layout_matches(b, utils::modifyList(render_size, size), label = label))
  }
}

set.seed(2)
walk <- data.frame(x = 1:12, y = cumsum(rnorm(12)), g = rep(c("a", "b"), each = 6))
base <- ggplot(walk, aes(x, y))

test_that("lines and paths draw as ggplot2 draws them", {
  check_geom(base + geom_line(), "line")
  check_geom(base + geom_path(), "path")
  check_geom(base + geom_line(colour = "red", linewidth = 2, alpha = 0.5), "colour, width and alpha")
  check_geom(base + geom_line(linetype = "dashed", linewidth = 1), "dashed")
  check_geom(base + geom_line(linetype = "1343"), "hex line type")
  check_geom(base + geom_line(linewidth = 3, lineend = "round", linejoin = "round"), "round ends")
  check_geom(base + geom_line(linewidth = 3, lineend = "square", linejoin = "bevel"), "square ends, bevel joins")
  check_geom(base + geom_line(linewidth = 3, linejoin = "mitre", linemitre = 2), "mitre limit")
  check_geom(ggplot(walk, aes(x, y, group = g)) + geom_line(), "groups")
  check_geom(ggplot(walk, aes(x, y, colour = g)) + geom_line(show.legend = FALSE), "colour by group")
  check_geom(ggplot(walk, aes(x, y, linetype = g, linewidth = g)) + geom_line(show.legend = FALSE), "linetype and width by group")
  check_geom(ggplot(data.frame(x = c(3, 1, 2, 5, 4), y = c(1, 2, 3, 2, 1)), aes(x, y)) + geom_path(), "path in data order")
  check_geom(base + geom_line() + geom_point(), "line and points")
  check_geom(ggplot(walk, aes(x, exp(y))) + geom_line() + scale_y_log10(), "log scale")
  check_geom(base + geom_line() + facet_wrap(vars(g)), "facets")
})

test_that("missing, infinite, empty and single-row data", {
  gap <- walk
  gap$y[5] <- NA
  suppressWarnings(check_geom(ggplot(gap, aes(x, y)) + geom_line(), "NA gap"))
  gap$y[c(1, 12)] <- NA
  suppressWarnings(check_geom(ggplot(gap, aes(x, y)) + geom_line(), "NA at the ends"))
  check_geom(ggplot(data.frame(x = 1:4, y = c(1, Inf, 3, 2)), aes(x, y)) + geom_line(), "Inf")
  check_geom(ggplot(walk[0, ], aes(x, y)) + geom_line(), "no rows")
  expect_message(
    check_geom(ggplot(walk[1, ], aes(x, y)) + geom_line(), "one row"),
    "Each group consists of only one observation"
  )
  check_geom(ggplot(data.frame(x = 1:5, y = c(2L, 4L, 1L, 3L, 5L)), aes(x, y)) + geom_line(), "integers")
  check_geom(ggplot(data.frame(x = c("a", "b", "c"), y = 1:3), aes(x, y, group = 1)) + geom_line(), "discrete x")
})

test_that("steps draw as ggplot2 draws them, in both tiers", {
  for (dir in c("hv", "vh", "mid")) {
    check_geom(base + geom_step(direction = dir), paste("step", dir))
  }
  check_geom(ggplot(walk, aes(y, x)) + geom_step(orientation = "y"), "step, y orientation")
  check_geom(ggplot(walk, aes(x, y, colour = g)) + geom_step(show.legend = FALSE), "steps by group")
  check_geom(base + geom_step(linewidth = 2, colour = "blue"), "step width and colour")
  check_geom(ggplot(walk[1, ], aes(x, y)) + geom_step(), "one row")
  withr::local_options(alot.full_tier = FALSE)
  check_geom(base + geom_step(), "hybrid step", tier = "hybrid")
  check_geom(ggplot(walk, aes(x, y, colour = g)) + geom_step(direction = "mid"), "hybrid steps by group", tier = "hybrid")
})

test_that("bars, columns, rects and tiles draw as ggplot2 draws them", {
  check_geom(base + geom_col(), "col")
  check_geom(base + geom_col(fill = "steelblue", colour = "black"), "outlined col")
  check_geom(base + geom_col(fill = "steelblue", colour = "black", linewidth = 2, linejoin = "round"), "thick round outline")
  check_geom(base + geom_col(alpha = 0.4, fill = "red"), "alpha")
  check_geom(base + geom_col(width = 0.5), "width")
  check_geom(ggplot(mtcars, aes(factor(cyl))) + geom_bar(), "bar")
  check_geom(ggplot(mtcars, aes(factor(cyl), fill = factor(gear))) + geom_bar(show.legend = FALSE), "stacked bars")
  check_geom(ggplot(mtcars, aes(factor(cyl), fill = factor(gear))) + geom_bar(position = "dodge", show.legend = FALSE), "dodged bars")
  check_geom(ggplot(mtcars, aes(mpg)) + geom_histogram(bins = 8), "histogram")
  check_geom(ggplot(data.frame(x = c("a", "b", "c"), y = c(-1, 2, 3)), aes(x, y)) + geom_col(), "negative values")
  check_geom(ggplot(mtcars, aes(y = factor(cyl))) + geom_bar(), "horizontal bars")
  check_geom(ggplot() + annotate("rect", xmin = 1, xmax = 3, ymin = 1, ymax = 2, fill = "grey30") + xlim(0, 4) + ylim(0, 3), "annotated rect")
  check_geom(ggplot(data.frame(xmin = c(1, 3), xmax = c(2, 5), ymin = c(1, 2), ymax = c(3, 4)), aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)) + geom_rect(fill = NA, colour = "red"), "outline rects")
  grid <- expand.grid(x = 1:10, y = 1:8)
  grid$z <- grid$x * grid$y
  check_geom(ggplot(grid, aes(x, y, fill = z)) + geom_tile(show.legend = FALSE), "tiles")
  check_geom(ggplot(grid, aes(x, y, fill = z)) + geom_tile(colour = "white", show.legend = FALSE), "outlined tiles")
  check_geom(ggplot(grid, aes(x, y)) + geom_tile(width = 0.5, height = 0.5), "small tiles")
  check_geom(base + geom_col() + facet_wrap(vars(g)), "facets")
  check_geom(ggplot(mtcars, aes(factor(cyl))) + geom_bar() + scale_y_sqrt(), "sqrt scale")
})

test_that("missing, infinite, empty and single-row rect data", {
  d <- data.frame(x = c(1, 2, 3, NA), y = c(2, NA, 3, 1))
  suppressWarnings(check_geom(ggplot(d, aes(x, y)) + geom_col(), "NA"))
  check_geom(ggplot(data.frame(xmin = 1, xmax = Inf, ymin = -Inf, ymax = 2), aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)) + geom_rect() + xlim(0, 3) + ylim(0, 3), "Inf")
  check_geom(ggplot(walk[0, ], aes(x, y)) + geom_col(), "no rows")
  check_geom(ggplot(walk[1, ], aes(x, y)) + geom_col(), "one row")
})

test_that("text draws as ggplot2 draws it", {
  d <- data.frame(x = c(1, 2, 3, 4), y = c(2, 4, 3, 1), lab = c("alpha", "Beta", "gamma", "Delta"))
  txt <- ggplot(d, aes(x, y, label = lab))
  check_geom(txt + geom_text(), "text")
  check_geom(txt + geom_text(size = 8, colour = "red"), "size and colour")
  check_geom(txt + geom_text(alpha = 0.4), "alpha")
  check_geom(txt + geom_text(angle = 45), "angle 45")
  check_geom(txt + geom_text(angle = 90, hjust = 0), "angle 90")
  check_geom(txt + geom_text(hjust = 0, vjust = 1), "justification")
  check_geom(txt + geom_text(hjust = "inward", vjust = "inward"), "inward")
  check_geom(txt + geom_text(hjust = "outward", vjust = "outward", angle = 30), "outward, rotated")
  check_geom(txt + geom_text(fontface = "bold"), "bold")
  check_geom(txt + geom_text(fontface = "bold.italic", family = "serif"), "bold italic serif")
  check_geom(txt + geom_text(aes(fontface = rep(1:2, 2), size = y), show.legend = FALSE), "mapped face and size")
  check_geom(txt + geom_text(size = 12, size.unit = "pt"), "size in points")
  check_geom(txt + geom_text(lineheight = 0.8, aes(label = c("one\ntwo", "a", "b\nc\nd", "e"))), "several lines")
  check_geom(txt + geom_text(aes(colour = lab), show.legend = FALSE), "colours")
  check_geom(txt + geom_text() + geom_point(), "text and points")
  check_geom(txt + geom_text(nudge_x = 0.2), "nudged")
  check_geom(txt + geom_text(size = 14, angle = 20) + coord_cartesian(xlim = c(1.5, 3.5)), "clipped by the panel")
  check_geom(txt + geom_text() + facet_wrap(vars(c(1, 1, 2, 2))), "facets")
  check_geom(ggplot(d, aes(x, y, label = lab)) + geom_col() + geom_text(vjust = -0.3), "labelled columns")
  check_geom(txt + geom_text(aes(label = c("é", "ü", "ñ", "ß"))), "accents")
  check_geom(ggplot(d, aes(x, y, label = factor(lab))) + geom_text(), "factor labels")
  check_geom(txt + geom_text(aes(label = c("", "x", "", "y"))), "empty labels")
  check_geom(txt + geom_text(size = 6) + theme_bw(base_size = 16), "theme_bw")
})

test_that("missing and empty text data", {
  d <- data.frame(x = c(1, 2, NA, 4), y = c(2, 4, 3, 1), lab = c("a", NA, "c", "d"))
  b <- suppressWarnings(ggplot_build(ggplot(d, aes(x, y, label = lab)) + geom_text()))
  expect_warning(out <- render_raster(b, render_size), "Removed 2 rows")
  expect_identical(out$tier, "full")
  check_geom(ggplot(d[0, ], aes(x, y, label = lab)) + geom_text(), "no rows")
  check_geom(ggplot(d[1, ], aes(x, y, label = lab)) + geom_text(), "one row")
})

test_that("layers and plots the full tier doesn't draw decline to another tier", {
  tier <- function(p) {
    set.seed(1)
    b <- suppressWarnings(suppressMessages(ggplot_build(p)))
    suppressMessages(render_raster(b, render_size)$tier)
  }
  d <- data.frame(x = c(1, 2, 3), y = c(2, 4, 3), lab = c("a", "b", "c"))
  txt <- ggplot(d, aes(x, y, label = lab))
  # The hybrid tier draws text with ggplot2, so a text-only plot drops to
  # ggplot2 and one with points to the hybrid.
  expect_identical(tier(txt + geom_text(check_overlap = TRUE)), "ggplot2")
  expect_identical(tier(txt + geom_text(parse = TRUE)), "ggplot2")
  expect_identical(tier(txt + geom_text(aes(label = y))), "ggplot2")
  expect_identical(tier(txt + geom_text(aes(label = c("a", "漢", "c")))), "ggplot2")
  expect_identical(tier(txt + geom_text(family = "mono", fontface = "bold") + geom_point()), "full")
  expect_identical(tier(txt + geom_text(aes(label = c("a", "漢", "c"))) + geom_point()), "hybrid")
  expect_identical(tier(txt + geom_line(arrow = grid::arrow())), "ggplot2")
  expect_identical(tier(ggplot(d, aes(x, y, colour = c(1, 2, 2))) + geom_line()), "ggplot2")
  expect_identical(tier(ggplot(d, aes(x, y, colour = c(1, 2, 2))) + geom_line(show.legend = FALSE) + geom_point()), "hybrid")
  expect_identical(tier(txt + geom_col(linetype = "dashed", colour = "black")), "ggplot2")
  expect_identical(tier(txt + geom_line() + geom_label()), "hybrid")
  expect_identical(tier(txt + geom_col() + coord_flip()), "ggplot2")
  expect_identical(tier(txt + geom_col() + coord_cartesian(clip = "off")), "ggplot2")
  expect_identical(tier(ggplot(d, aes(x, y, group = 1, colour = lab)) + geom_line()), "ggplot2")
})

test_that("the full tier names why it declines a layer", {
  b <- ggplot_build(ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars))) + geom_text(check_overlap = TRUE) + geom_point())
  expect_match(attr(render_full(b, render_size), "reason"), "check_overlap")
  cov <- alot_render_coverage(ggplot(mtcars, aes(wt, mpg)) + geom_line() + geom_step())
  expect_identical(cov$tier, "full")
  expect_identical(cov$layers$engine, c("rust", "rust"))
})
