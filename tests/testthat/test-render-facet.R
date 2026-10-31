# Fixed-scale facet_wrap() in the full tier (R5.2): the panel table, axes on
# the outer panels (and beside empty slots), strips on top and panel spacing,
# against ggplot2 on ragg and grid's boxes.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_facet <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-facet.R", label, b)
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key)))
  expect_null(expect_layout_matches(b, utils::modifyList(render_size, size), label = label, cache_key = key))
}

base <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

test_that("panel grids, empty slots and direction", {
  check_facet(base + facet_wrap(~cyl), "three panels")
  check_facet(base + facet_wrap(~carb), "six panels")
  check_facet(base + facet_wrap(~gear, ncol = 1), "one column")
  check_facet(base + facet_wrap(~gear, nrow = 1), "one row")
  check_facet(base + facet_wrap(~carb, ncol = 4), "empty slots at the end")
  check_facet(base + facet_wrap(~carb, ncol = 4, dir = "v"), "by column")
  check_facet(base + facet_wrap(~carb, ncol = 4, as.table = FALSE), "bottom to top")
  check_facet(base + facet_wrap(~carb, dir = "rb", ncol = 4), "right to left")
  check_facet(base + facet_wrap(~gear, ncol = 2), "an empty corner")
  check_facet(base + facet_wrap(~interaction(cyl, gear), ncol = 5), "many panels")
  check_facet(base + facet_wrap(~am), "two panels")
  check_facet(base + facet_wrap(vars(cyl), drop = FALSE), "vars")
  check_facet(base + facet_wrap(~cyl, scales = "fixed", shrink = FALSE), "fixed scales")
})

test_that("strips, spacing and themes", {
  check_facet(base + facet_wrap(~cyl, labeller = label_both), "label_both")
  check_facet(base + facet_wrap(~cyl, labeller = labeller(cyl = c(`4` = "four\ncylinders", `6` = "six", `8` = "eight"))), "two-line strips")
  check_facet(base + facet_wrap(~ rownames(mtcars)[1:32 %% 3 + 1]), "long labels")
  check_facet(base + facet_wrap(~cyl) + theme(panel.spacing = unit(1, "cm")), "spacing")
  check_facet(base + facet_wrap(~cyl) + theme(panel.spacing.x = unit(0, "pt"), panel.spacing.y = unit(20, "pt")), "spacing x and y")
  check_facet(base + facet_wrap(~cyl) + theme(strip.text = element_text(size = 18, face = "bold", hjust = 0)), "big strip text")
  check_facet(base + facet_wrap(~cyl) + theme(strip.background = element_rect(fill = "yellow", colour = "red", linewidth = 2)), "strip background")
  check_facet(base + facet_wrap(~cyl) + theme(strip.text = element_text(margin = margin(10, 10, 10, 10))), "strip margins")
  check_facet(base + facet_wrap(~cyl) + theme(strip.clip = "off"), "unclipped strips")
  check_facet(base + facet_wrap(~cyl) + theme(axis.ticks.length = unit(0.5, "cm")), "long ticks")
  check_facet(base + facet_wrap(~cyl) + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"), "axes top and right")
  check_facet(base + facet_wrap(~carb, ncol = 4) + scale_x_continuous(position = "top"), "top axes beside empty slots")
  check_facet(base + facet_wrap(~carb, ncol = 4) + scale_y_continuous(position = "right"), "right axes beside empty slots")
  check_facet(base + facet_wrap(~cyl) + guides(x = "none"), "no x axis")
  check_facet(base + facet_wrap(~cyl) + labs(title = "Facets", subtitle = "S", caption = "C", tag = "A"), "titles")
  check_facet(base + facet_wrap(~cyl) + coord_fixed(), "fixed ratio")
  check_facet(base + facet_wrap(~gear, ncol = 2) + coord_fixed(), "fixed ratio, empty slot", size = list(width = 800, height = 600))
  check_facet(base + facet_wrap(~cyl) + coord_cartesian(clip = "on", xlim = c(2, 4)), "zoomed")
  for (theme in list(theme_bw(), theme_classic(), theme_minimal(), theme_dark(), theme_light(), theme_linedraw())) {
    check_facet(base + facet_wrap(~cyl) + theme, "complete theme")
  }
  check_facet(base + facet_wrap(~cyl), "150 dpi", size = list(width = 600, height = 450, res = 150))
})

test_that("points, legends and scales across panels", {
  check_facet(ggplot(mtcars, aes(wt, mpg, colour = factor(gear))) + geom_point() + facet_wrap(~cyl), "colour legend")
  check_facet(ggplot(mtcars, aes(wt, mpg, colour = qsec, shape = factor(am))) + geom_point(alpha = 0.5) + facet_wrap(~cyl) +
    theme(legend.position = "bottom"), "colourbar and legend")
  check_facet(base + facet_wrap(~cyl) + scale_x_log10() + scale_y_sqrt(), "transformed scales")
  check_facet(base + aes(size = hp) + facet_wrap(~cyl, ncol = 2), "size legend")
  check_facet(ggplot(mtcars, aes(factor(cyl), mpg)) + geom_point() + facet_wrap(~gear), "discrete x")
  suppressWarnings(check_facet(ggplot(data.frame(x = c(1, NA, 3, 4), y = c(2, 3, Inf, 1), g = c("a", "a", "b", "b")), aes(x, y)) + geom_point() + facet_wrap(~g), "NA and Inf"))
  check_facet(ggplot(mtcars, aes(wt, mpg)) + geom_point() + facet_wrap(~cyl, drop = FALSE) + geom_blank(), "blank layer")
  check_facet(ggplot(mtcars[mtcars$cyl == 4, ], aes(wt, mpg)) + geom_point() + facet_wrap(~cyl), "one panel")
  check_facet(ggplot(mtcars, aes(wt, mpg)) + geom_point() + facet_wrap(~factor(cyl, levels = c(4, 6, 8, 10)), drop = FALSE), "panel without data")
  check_facet(base + facet_wrap(vars(cyl), labeller = "label_value", strip.position = "top"), "strip position top")
})

test_that("facets alot doesn't draw fall back", {
  declined <- function(p) {
    b <- suppressWarnings(ggplot_build(p))
    attr(layout_boxes_rust(b, 400, 300, 96), "reason")
  }
  expect_match(declined(base + facet_wrap(~cyl, scales = "free")), "free scales")
  expect_match(declined(base + facet_wrap(~cyl, scales = "free_x")), "free scales")
  expect_match(declined(base + facet_wrap(~cyl, space = "free_x", scales = "free_x")), "free scales")
  expect_match(declined(base + facet_wrap(~cyl, axes = "all")), "axes on every panel")
  # Strip text wider than its strip, which ggplot2 clips.
  b <- suppressWarnings(ggplot_build(base + facet_wrap(~carb, ncol = 4) + coord_fixed()))
  expect_match(attr(render_full(b, render_size), "reason"), "not one the Rust drawer reads")
  expect_match(declined(base + facet_wrap(~cyl, strip.position = "bottom")), "strips not on top")
  expect_match(declined(base + facet_wrap(~cyl, strip.position = "left")), "strips not on top")
  expect_match(declined(base + facet_wrap(~cyl) + theme(strip.placement = "outside")), "strips not on top")
  expect_match(declined(base + facet_wrap(~cyl + gear)), "more than one variable")
  expect_match(declined(ggplot(data.frame(x = 1:6, y = 1:6, g = c("a", "a", "b", "b", NA, "c")), aes(x, y)) + geom_point() + facet_wrap(~g)), "plain text")
  b <- suppressWarnings(ggplot_build(base + facet_wrap(~cyl, labeller = label_bquote(alpha^.(cyl)))))
  expect_false(is.null(attr(render_full(b, render_size), "reason")))
  expect_match(declined(base + facet_grid(. ~ cyl)), "more than one panel")
  expect_match(declined(base + facet_wrap(~cyl) + theme(strip.text = element_blank())), "blank strips")
  b <- suppressWarnings(ggplot_build(base + facet_wrap(~cyl) + coord_flip()))
  expect_false(is.null(attr(render_full(b, render_size), "reason")))
})
