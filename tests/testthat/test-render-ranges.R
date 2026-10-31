# Boxplots, violins and the range geoms in the full tier (R6.5b):
# geom_boxplot(), geom_violin(), geom_crossbar(), geom_errorbar(),
# geom_linerange() and geom_pointrange(), with their keys, drawn by
# alot-core's page drawers against ggplot2 on ragg. They have no hybrid
# drawer: in the hybrid tier ggplot2 draws them.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_range <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-ranges.R", label, b)
  expect_no_warning(
    do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key))),
    class = "alot_render_fallback"
  )
  expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
}

summ <- data.frame(x = c("a", "b", "c", "d"), y = c(2, 3.5, 1, 4), lo = c(1, 2.5, 0.2, 3), hi = c(3, 5, 1.5, 4.8), g = c("p", "q", "p", "q"))
rg <- ggplot(summ, aes(x, y, ymin = lo, ymax = hi))

test_that("boxplots draw as ggplot2 draws them", {
  check_range(ggplot(mpg, aes(class, hwy)) + geom_boxplot(), "boxplot")
  check_range(ggplot(mpg, aes(class, hwy, fill = drv)) + geom_boxplot(), "dodged, fill legend")
  check_range(ggplot(mpg, aes(hwy, class, colour = drv)) + geom_boxplot(), "flipped, colour legend")
  set.seed(3)
  many <- data.frame(g = rep(c("a", "b", "c"), c(60, 120, 90)), f = rep(c("u", "v"), 135), y = rnorm(270))
  check_range(ggplot(many, aes(g, y)) + geom_boxplot(notch = TRUE, notchwidth = 0.3, varwidth = TRUE) +
    facet_wrap(vars(f)), "notches, varwidth, facets")
  check_range(ggplot(mpg, aes(class, hwy)) + geom_boxplot(staplewidth = 0.5, outlier.shape = 21, outlier.fill = "red",
    outlier.size = 3, linewidth = 0.8, alpha = 0.5, fill = "steelblue"), "staples, outlier style")
  check_range(ggplot(mpg, aes(class, hwy)) + geom_boxplot(outlier.shape = NA, whisker.linetype = "dashed",
    median.colour = "red", median.linewidth = 2, box.colour = "blue", staplewidth = 1, staple.colour = "green"), "gp overrides")
  check_range(ggplot(mpg, aes(class, hwy)) + geom_boxplot(outliers = FALSE), "outliers discarded")
  check_range(ggplot(mpg, aes(drv, hwy, linetype = drv)) + geom_boxplot(staplewidth = 0.4), "linetype legend, staple key")
  check_range(ggplot(mpg, aes(hwy, drv, fill = drv)) + geom_boxplot(staplewidth = 0.4), "flipped key")
  check_range(ggplot(mpg, aes(displ, hwy, group = cut_width(displ, 1))) + geom_boxplot(), "continuous x")
})

test_that("violins draw as ggplot2 draws them", {
  check_range(ggplot(mpg, aes(drv, hwy)) + geom_violin(), "violin")
  check_range(ggplot(mpg, aes(drv, hwy, fill = drv)) + geom_violin(alpha = 0.5, colour = "black"), "violin fill legend")
  check_range(ggplot(mpg, aes(hwy, drv)) + geom_violin(), "violin flipped")
  check_range(ggplot(mpg, aes(drv, hwy)) + geom_violin(quantile.linetype = 1, quantile.colour = "red"), "quantile lines")
  check_range(ggplot(mpg, aes(drv, hwy)) + geom_violin(quantiles = c(0.1, 0.5, 0.9), quantile.linetype = "dashed") +
    facet_wrap(vars(year)), "dashed quantiles, facets")
})

test_that("crossbars, errorbars and ranges draw as ggplot2 draws them", {
  check_range(rg + geom_crossbar(), "crossbar")
  check_range(rg + geom_crossbar(aes(fill = g), width = 0.5, linewidth = 1, middle.colour = "red"), "crossbar styled, legend")
  check_range(rg + geom_errorbar(width = 0.3), "errorbar")
  check_range(rg + geom_errorbar(aes(colour = g), width = 0.3, linetype = "dashed", linewidth = 1), "errorbar dashed, legend")
  check_range(ggplot(summ, aes(y = x, x = y, xmin = lo, xmax = hi)) + geom_errorbar(width = 0.2), "errorbar flipped")
  check_range(rg + geom_linerange(aes(colour = g), linewidth = 2), "linerange, legend")
  check_range(ggplot(summ, aes(y = x, xmin = lo, xmax = hi, colour = g)) + geom_linerange(), "linerange flipped, legend")
  check_range(rg + geom_pointrange(aes(colour = g)), "pointrange, legend")
  check_range(rg + geom_pointrange(shape = 21, fill = "white", size = 1, lineend = "round"), "pointrange styled")
  check_range(ggplot(mpg, aes(class, hwy)) + stat_summary(fun.data = mean_se) + facet_wrap(vars(drv), scales = "free_y"),
    "stat_summary, facets")
  check_range(ggplot(mpg, aes(class, hwy)) + stat_summary(fun.data = mean_cl_normal, geom = "errorbar", width = 0.2) +
    stat_summary(fun = mean, geom = "point"), "stat_summary errorbar")
})

test_that("missing, infinite, empty and single-row range data", {
  gap <- summ
  gap$hi[2] <- NA
  # GeomErrorbar keeps the row; grid breaks the polyline at the NA.
  check_range(ggplot(gap, aes(x, y, ymin = lo, ymax = hi)) + geom_errorbar(), "NA row")
  inf <- summ
  inf$hi[1] <- Inf
  check_range(ggplot(inf, aes(x, y, ymin = lo, ymax = hi)) + geom_linerange(), "Inf")
  check_range(rg %+% summ[0, ] + geom_crossbar(), "no rows")
  check_range(rg %+% summ[1, ] + geom_pointrange(), "single row")
  check_range(ggplot(data.frame(x = 1:3, lo = 1:3, hi = 4:6), aes(x, ymin = lo, ymax = hi)) + geom_errorbar(), "integers")
})

test_that("ranges the full tier doesn't draw decline to another tier", {
  reason <- function(p) {
    set.seed(1)
    attr(render_full(suppressMessages(ggplot_build(p)), render_size), "reason")
  }
  expect_match(reason(rg + geom_crossbar() + coord_polar()), "coord")
  expect_match(reason(rg + geom_errorbar() + coord_cartesian(clip = "off")), "clip")
  expect_match(reason(rg + geom_linerange(lineend = "foo")), "lineend")
  expect_match(reason(ggplot(mpg, aes(class, hwy)) + geom_boxplot(notch = TRUE)), "notch outside")
  expect_match(reason(ggplot(mpg, aes(class, hwy)) + geom_boxplot(outlier.shape = "foo")), "point")
  expect_match(reason(ggplot(summ, aes(x, lower = lo, upper = hi, middle = y, ymin = lo, ymax = hi, group = 1)) +
    geom_boxplot(stat = "identity")), "one boxplot per group")
  expect_match(reason(rg + geom_pointrange(shape = "foo")), "point")
  gap <- summ
  gap$hi[2] <- NA
  expect_match(reason(ggplot(gap, aes(x, y, ymin = lo, ymax = hi)) + geom_linerange()), "NA in positions")
  cov <- alot_render_coverage(rg + geom_errorbar())
  expect_identical(cov$tier, "full")
  # The hybrid tier draws them with its marks drawer (R7.1).
  expect_identical(cov$layers$engine, "rust")
})
