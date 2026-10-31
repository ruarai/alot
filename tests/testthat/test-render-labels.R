# Labels, polygons and annotations in the full tier (R6.5d): geom_label()
# (labelGrob()'s rounded box and text), geom_polygon() without subgroups
# and annotate() layers of the geoms the full tier draws, drawn by
# alot-core's page drawers against ggplot2 on ragg. They have no hybrid
# drawer for labels: in the hybrid tier ggplot2 draws them.
# geom_raster(), polygon subgroups and unusual label options decline.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_lab <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-labels.R", label, b)
  expect_no_warning(
    do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key))),
    class = "alot_render_fallback"
  )
  expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
}

labs_df <- data.frame(x = c(1, 2, 3, 4), y = c(1, 3, 2, 4), lab = c("alpha", "Beta", "gamma y", "Q"), g = c("a", "b", "a", "b"))
lp <- ggplot(labs_df, aes(x, y, label = lab))

test_that("labels draw as ggplot2 draws them", {
  check_lab(lp + geom_label(), "label")
  check_lab(lp + geom_label(aes(fill = g)), "label fill legend")
  check_lab(lp + geom_label(aes(colour = g), linewidth = 1, label.r = unit(0.4, "lines"), size = 6), "label colour legend, border")
  check_lab(lp + geom_label(label.padding = unit(c(2, 6, 1, 4), "pt"), linewidth = 0, alpha = 0.5, fill = "red"), "label padding, no border")
  check_lab(lp + geom_label(hjust = 0, vjust = 1, fontface = "bold"), "label justified, bold")
  check_lab(lp + geom_label(aes(angle = x * 15)), "label rotated")
  check_lab(lp + geom_label(border.colour = "blue", text.colour = "red", linetype = "dashed"), "label border and text colours")
  check_lab(lp + geom_label(size = 12) + geom_point(), "label overlapping")
  check_lab(lp + geom_label() + facet_wrap(vars(g), scales = "free"), "label facets")
})

test_that("missing, empty, single-row and integer label data", {
  na <- labs_df
  na$y[2] <- NA
  suppressWarnings(check_lab(ggplot(na, aes(x, y, label = lab)) + geom_label(), "label with NA"))
  check_lab(lp %+% labs_df[0, ] + geom_label() + geom_point(), "label no rows")
  check_lab(lp %+% labs_df[1, ] + geom_label(), "label single row")
  check_lab(ggplot(data.frame(x = 1:3, y = 3:1, l = c("p", "q", "r")), aes(x, y, label = l)) + geom_label(), "label integers")
  check_lab(ggplot(mpg, aes(class, hwy, label = drv)) + geom_label(data = mpg[1:20, ], size = 3), "label discrete x")
})

poly <- data.frame(
  x = c(1, 2, 1.5, 2, 3, 3, 2.2, 0.5, 1, 1, 0.5),
  y = c(1, 1, 2, 2, 2, 3, 1.5, 3, 3, 3.6, 3.6),
  g = rep(c("a", "b", "c"), c(3, 4, 4))
)
pp <- ggplot(poly, aes(x, y, group = g))

test_that("polygons draw as ggplot2 draws them", {
  check_lab(pp + geom_polygon(), "polygon")
  check_lab(pp + geom_polygon(aes(fill = g), colour = "black", linewidth = 1, alpha = 0.6), "polygon fill legend")
  check_lab(pp + geom_polygon(aes(colour = g), fill = NA, linetype = "dashed", linejoin = "mitre"), "polygon colour legend, dashed")
  check_lab(pp + geom_polygon(fill = "grey60") + facet_wrap(vars(g), scales = "free"), "polygon facets")
  check_lab(ggplot(poly[1, ], aes(x, y)) + geom_polygon() + geom_point(), "polygon single row")
  check_lab(ggplot(data.frame(x = c(1L, 3L, 2L), y = c(1L, 1L, 3L)), aes(x, y)) + geom_polygon(), "polygon integers")
})

test_that("annotate() layers draw as their geoms do", {
  pts <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  check_lab(pts + annotate("text", x = 4, y = 25, label = "Some text", colour = "red"), "annotate text")
  check_lab(pts + annotate("label", x = 4, y = 25, label = "A label"), "annotate label")
  check_lab(pts + annotate("rect", xmin = 3, xmax = 4.2, ymin = 12, ymax = 21, alpha = .2), "annotate rect")
  check_lab(pts + annotate("segment", x = 2.5, xend = 4, y = 15, yend = 25, colour = "blue"), "annotate segment")
  check_lab(pts + annotate("pointrange", x = 3.5, y = 20, ymin = 12, ymax = 28, colour = "red", size = 1.5), "annotate pointrange")
  check_lab(pts + annotate("polygon", x = c(2, 3, 2.5), y = c(15, 15, 25), fill = "orange", alpha = 0.5), "annotate polygon")
  check_lab(pts + aes(colour = factor(cyl)) + annotate("label", x = 4, y = 30, label = "no legend"), "annotate without legend")
  check_lab(pts + annotate("text", x = 3, y = 30, label = "every panel") + facet_wrap(vars(cyl)), "annotate in every panel")
})

test_that("labels, polygons and rasters the full tier doesn't draw decline to another tier", {
  reason <- function(p) {
    set.seed(1)
    attr(render_full(suppressWarnings(suppressMessages(ggplot_build(p))), render_size), "reason")
  }
  expect_match(reason(lp + geom_label(parse = TRUE)), "plotmath")
  expect_match(reason(lp + geom_label(label.padding = unit(0.1, "npc"))), "label.padding")
  expect_match(reason(lp + geom_label(label.r = unit(0.1, "snpc"))), "label.padding or label.r")
  expect_match(reason(ggplot(data.frame(x = 1, y = 1, l = "two\nlines"), aes(x, y, label = l)) + geom_label()), "multi-line")
  expect_match(reason(lp + geom_label(border.colour = c("red", "blue"))), "border.colour")
  expect_match(reason(lp + geom_label(aes(fill = g), key_glyph = "label") + guides(fill = guide_legend(override.aes = list(angle = 45)))), "label key")
  expect_match(reason(lp + geom_label() + coord_polar()), "coord")
  hole <- data.frame(x = c(0, 4, 4, 0, 1, 2, 2, 1), y = c(0, 0, 4, 4, 1, 1, 2, 2), s = rep(1:2, each = 4))
  expect_match(reason(ggplot(hole, aes(x, y, subgroup = s)) + geom_polygon()), "subgroups")
  na <- poly
  na$x[2] <- NA
  expect_match(reason(ggplot(na, aes(x, y, group = g)) + geom_polygon()), "NA in x or y")
  expect_match(reason(ggplot(faithfuld, aes(waiting, eruptions, fill = density)) + geom_raster()), "layers other than")
  cov <- alot_render_coverage(lp + geom_label())
  expect_identical(cov$tier, "full")
  cov <- alot_render_coverage(pp + geom_polygon())
  expect_identical(cov$tier, "full")
})
