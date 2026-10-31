# Ribbons in the full tier (R6.5a): geom_ribbon(), geom_area(),
# geom_density() and geom_smooth(), with their keys, drawn by alot-core's
# page drawers against ggplot2 on ragg. They have no hybrid drawer: in the
# hybrid tier ggplot2 draws them.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_ribbon <- function(p, label, ..., max = 32, size = list(), tier = "full") {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-ribbons.R", label, b)
  expect_no_warning(
    do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = tier, label = label, cache_key = key))),
    class = "alot_render_fallback"
  )
  if (tier == "full") {
    expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
  }
}

set.seed(2)
band <- data.frame(x = rep(1:12, 2), g = rep(c("a", "b"), each = 12))
band$y <- cumsum(rnorm(24))
band$lo <- band$y - runif(24, 0.5, 2)
band$hi <- band$y + runif(24, 0.5, 2)
rb <- ggplot(band, aes(x, ymin = lo, ymax = hi))

test_that("ribbons draw as ggplot2 draws them", {
  check_ribbon(rb + geom_ribbon(), "ribbon")
  check_ribbon(rb + geom_ribbon(aes(fill = g), alpha = 0.5), "fill by group, alpha")
  check_ribbon(rb + geom_ribbon(aes(group = g), fill = NA, colour = "red"), "outline both")
  for (type in c("upper", "lower", "full")) {
    check_ribbon(rb + geom_ribbon(aes(group = g), colour = "black", linewidth = 1, outline.type = type), paste("outline", type))
  }
  check_ribbon(rb + geom_ribbon(aes(group = g), colour = "blue", linetype = "dashed", linewidth = 0.8), "dashed outline")
  check_ribbon(ggplot(band, aes(y = x, xmin = lo, xmax = hi, group = g)) + geom_ribbon(colour = "black"), "flipped")
  check_ribbon(ggplot(data.frame(x = 1:6, lo = c(1, 3, 1, 3, 1, 3), hi = c(3, 1, 3, 1, 3, 1)), aes(x, ymin = lo, ymax = hi)) +
    geom_ribbon(colour = "black"), "crossing bounds")
  check_ribbon(rb + geom_ribbon(aes(fill = g)) + facet_wrap(vars(g), scales = "free_y"), "facets, free scales")
})

test_that("areas and densities draw as ggplot2 draws them", {
  check_ribbon(ggplot(band, aes(x, abs(y))) + geom_area(), "area")
  check_ribbon(ggplot(band, aes(x, abs(y), fill = g)) + geom_area(colour = "black"), "stacked area, legend")
  check_ribbon(ggplot(data.frame(x = c(1, 3, 5, 2, 4, 6), y = c(1, 2, 1, 2, 3, 2), g = rep(1:2, each = 3)), aes(x, y, fill = factor(g))) +
    geom_area(colour = "black", show.legend = FALSE), "stat_align padding")
  check_ribbon(ggplot(band, aes(abs(y), x)) + geom_area(orientation = "y"), "area flipped")
  check_ribbon(ggplot(faithful, aes(eruptions)) + geom_density(), "density")
  check_ribbon(ggplot(faithful, aes(eruptions, fill = eruptions > 3)) + geom_density(alpha = 0.4), "density fill, legend")
  check_ribbon(ggplot(faithful, aes(eruptions)) + geom_density(outline.type = "full", fill = "grey80"), "density full outline")
  check_ribbon(ggplot(mpg, aes(hwy, colour = drv)) + geom_density(), "density colour legend")
})

test_that("smooths draw as ggplot2 draws them", {
  check_ribbon(ggplot(mpg, aes(displ, hwy)) + geom_point() + geom_smooth(method = "loess", formula = y ~ x), "smooth")
  check_ribbon(ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_smooth(method = "lm", formula = y ~ x), "smooth by group, legend")
  check_ribbon(ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_smooth(method = "lm", formula = y ~ x, se = FALSE), "smooth without se")
  check_ribbon(ggplot(mpg, aes(displ, hwy)) + geom_smooth(method = "lm", formula = y ~ x, linetype = "dashed", fill = "red", alpha = 0.2),
    "smooth styled")
  check_ribbon(ggplot(mpg, aes(hwy, displ)) + geom_smooth(method = "lm", formula = y ~ x, orientation = "y"), "smooth flipped")
  check_ribbon(ggplot(mpg, aes(displ, hwy)) + geom_smooth(method = "lm", formula = y ~ x) + facet_wrap(vars(drv)), "smooth facets")
})

test_that("missing, infinite, empty and single-row ribbon data", {
  gap <- band
  gap$hi[5] <- NA
  # ggplot2 and alot each warn of the removed row.
  suppressWarnings(check_ribbon(ggplot(gap, aes(x, ymin = lo, ymax = hi, group = g)) + geom_ribbon(colour = "black"), "NA gap"))
  b <- ggplot_build(ggplot(gap, aes(x, ymin = lo, ymax = hi, group = g)) + geom_ribbon())
  expect_warning(render_full(b, render_size), "Removed 1 row")
  check_ribbon(ggplot(data.frame(x = 1:4, lo = c(0, -Inf, 1, 0), hi = c(2, 3, Inf, 2)), aes(x, ymin = lo, ymax = hi)) +
    geom_ribbon(colour = "black"), "Inf")
  check_ribbon(rb %+% band[0, ] + geom_ribbon(), "no rows")
  check_ribbon(ggplot(data.frame(x = 1:5, y = c(2L, 4L, 1L, 3L, 5L)), aes(x, y)) + geom_area(), "integers")
  check_ribbon(ggplot(data.frame(x = c("a", "b", "c"), y = 1:3), aes(x, y, group = 1)) + geom_area(), "discrete x")
})

test_that("ribbons the full tier doesn't draw decline to another tier", {
  tier <- function(p) {
    set.seed(1)
    b <- suppressWarnings(suppressMessages(ggplot_build(p)))
    suppressMessages(render_raster(b, render_size)$tier)
  }
  reason <- function(p) {
    set.seed(1)
    attr(render_full(suppressMessages(ggplot_build(p)), render_size), "reason")
  }
  expect_match(reason(rb + geom_ribbon(aes(fill = x))), "vary along a ribbon")
  expect_match(reason(rb + geom_ribbon(aes(colour = x))), "vary along a ribbon")
  expect_match(reason(ggplot(band[1, ], aes(x, ymin = lo, ymax = hi)) + geom_ribbon()), "fewer than two rows")
  expect_match(reason(rb + geom_ribbon(linejoin = "foo")), "linejoin")
  expect_match(reason(rb + geom_ribbon() + coord_polar()), "coord")
  expect_match(reason(rb + geom_ribbon() + coord_polar()), "coord")
  expect_match(reason(rb + geom_ribbon() + coord_cartesian(clip = "off")), "clip")
  sm <- data.frame(x = 1:5, y = 1:5, ymin = c(0, NA, 2, 3, 4), ymax = 2:6)
  expect_match(reason(ggplot(sm, aes(x, y, ymin = ymin, ymax = ymax)) + geom_smooth(stat = "identity")), "NA in a ribbon")
  # The hybrid tier's marks drawer (R7.1) declines as the full tier does.
  expect_identical(tier(rb + geom_ribbon(aes(fill = x))), "ggplot2")
  expect_identical(tier(rb + geom_ribbon(aes(fill = x)) + geom_point(aes(y = hi))), "hybrid")
  cov <- alot_render_coverage(rb + geom_ribbon())
  expect_identical(cov$tier, "full")
  expect_identical(cov$layers$engine, "rust")
})
