# Facets in the full tier: facet_wrap() (R5.2) and facet_grid() (R6.3), the
# panel table, axes on the outer panels (beside empty slots, on every panel
# with free scales or `axes`), strips at every position, inside or outside,
# `switch`, free scales and `space = "free"`, against ggplot2 on ragg and
# grid's boxes.

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

test_that("free scales and axes on every panel", {
  check_facet(base + facet_wrap(~cyl, scales = "free"), "free")
  check_facet(base + facet_wrap(~cyl, scales = "free_x"), "free x")
  check_facet(base + facet_wrap(~cyl, scales = "free_y", ncol = 2), "free y, empty slot")
  check_facet(base + facet_wrap(~carb, scales = "free", ncol = 4), "free, empty slots")
  check_facet(base + facet_wrap(~cyl, nrow = 1, scales = "free_x", space = "free_x"), "free space x")
  check_facet(base + facet_wrap(~cyl, ncol = 1, scales = "free_y", space = "free_y"), "free space y")
  check_facet(base + facet_wrap(~cyl, axes = "all"), "axes all")
  check_facet(base + facet_wrap(~carb, ncol = 4, axes = "all_x"), "axes all x, empty slots")
  check_facet(base + facet_wrap(~carb, ncol = 4, axes = "all", axis.labels = "margins"), "axis labels at the margins")
  check_facet(base + facet_wrap(~carb, ncol = 4, axes = "all_y", axis.labels = "all_x", dir = "v"), "axis labels by column")
  check_facet(base + facet_wrap(~cyl, scales = "free") + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"), "free, axes top and right")
  check_facet(ggplot(mtcars, aes(factor(gear), mpg)) + geom_point() + facet_wrap(~cyl, scales = "free_x"), "free discrete x")
  check_facet(ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars))) + geom_text(size = 2) + facet_wrap(~cyl, scales = "free"), "free scales, text")
  check_facet(ggplot(mtcars, aes(factor(gear))) + geom_bar(fill = "steelblue") + facet_wrap(~cyl, scales = "free_y"), "free y, bars")
  check_facet(ggplot(economics_long, aes(date, value)) + geom_line() + facet_wrap(~variable, scales = "free_y", ncol = 1), "free y, lines",
    size = list(width = 400, height = 600))
})

test_that("facet_grid()", {
  check_facet(base + facet_grid(am ~ cyl), "rows and columns")
  check_facet(base + facet_grid(. ~ cyl), "columns")
  check_facet(base + facet_grid(cyl ~ .), "rows")
  check_facet(base + facet_grid(rows = vars(am), cols = vars(gear)), "vars")
  check_facet(base + facet_grid(vs + am ~ cyl), "two row variables")
  check_facet(base + facet_grid(am ~ cyl + vs, labeller = label_both), "two column variables, label_both")
  check_facet(base + facet_grid(vs + am ~ cyl, labeller = labeller(.multi_line = FALSE)), "one line for two variables")
  check_facet(base + facet_grid(am ~ cyl, margins = TRUE), "margins")
  check_facet(base + facet_grid(am ~ cyl, as.table = FALSE), "bottom to top")
  check_facet(base + facet_grid(am ~ cyl, scales = "free"), "free")
  check_facet(base + facet_grid(am ~ cyl, scales = "free_x", space = "free_x"), "free space x")
  check_facet(base + facet_grid(cyl ~ am, scales = "free", space = "free"), "free space")
  check_facet(base + facet_grid(am ~ cyl, axes = "all"), "axes all")
  check_facet(base + facet_grid(am ~ cyl, axes = "all", axis.labels = "margins"), "axis labels at the margins")
  check_facet(base + facet_grid(am ~ cyl, axes = "all_y", axis.labels = "all_x"), "axes all y")
  check_facet(base + facet_grid(am ~ cyl) + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"), "axes top and right")
  check_facet(base + facet_grid(am ~ cyl) + coord_fixed(ratio = 0.1), "fixed ratio")
  check_facet(base + facet_grid(am ~ cyl, scales = "free", space = "free") + coord_fixed(ratio = 0.1), "free space, fixed ratio")
  check_facet(base + facet_grid(am ~ cyl) + theme(aspect.ratio = 0.5), "aspect ratio")
  check_facet(base + facet_grid(am ~ cyl) + theme(panel.spacing.x = unit(1, "cm")), "spacing")
  check_facet(ggplot(mtcars, aes(wt, mpg, colour = factor(gear))) + geom_point() + facet_grid(am ~ cyl) + labs(title = "T"), "legend and title")
  check_facet(ggplot(mtcars, aes(factor(gear))) + geom_bar() + facet_grid(am ~ cyl, scales = "free_y"), "bars")
  check_facet(base + facet_grid(am ~ cyl), "150 dpi", size = list(width = 600, height = 450, res = 150))
  for (theme in list(theme_bw(), theme_classic(), theme_dark(), theme_linedraw())) {
    check_facet(base + facet_grid(am ~ cyl) + theme, "complete theme")
  }
})

test_that("strip positions, switch and placement", {
  for (pos in c("top", "bottom", "left", "right")) {
    check_facet(base + facet_wrap(~cyl, strip.position = pos), paste("strips", pos))
    check_facet(base + facet_wrap(~cyl, strip.position = pos) + theme(strip.placement = "outside"), paste("strips", pos, "outside"))
    check_facet(base + facet_wrap(~carb, ncol = 4, strip.position = pos, scales = "free"), paste("strips", pos, "free"))
  }
  check_facet(base + facet_wrap(~cyl, strip.position = "bottom") + theme(strip.placement = "outside", strip.switch.pad.wrap = unit(1, "cm")),
    "outside, padding")
  check_facet(base + facet_wrap(~cyl, strip.position = "left") + scale_y_continuous(position = "right") + theme(strip.placement = "outside"),
    "outside, no axis there")
  check_facet(base + facet_wrap(~cyl + am, strip.position = "left"), "two variables left")
  check_facet(base + facet_wrap(~cyl + am, strip.position = "right"), "two variables right")
  check_facet(base + facet_wrap(~cyl + am), "two variables top")
  check_facet(base + facet_wrap(~cyl + am, strip.position = "bottom"), "two variables bottom")
  for (sw in c("x", "y", "both")) {
    check_facet(base + facet_grid(am ~ cyl, switch = sw), paste("switch", sw))
    check_facet(base + facet_grid(am ~ cyl, switch = sw) + theme(strip.placement = "outside"), paste("switch", sw, "outside"))
  }
  check_facet(base + facet_grid(vs + am ~ cyl, switch = "y"), "two variables left, grid")
  check_facet(base + facet_grid(am ~ cyl) + theme(strip.placement = "outside"), "outside, top and right")
  check_facet(base + facet_grid(am ~ cyl, switch = "both") + theme(strip.placement = "outside", strip.switch.pad.grid = unit(0.5, "cm")),
    "outside, padding, grid")
  check_facet(base + facet_grid(am ~ cyl, switch = "x") + scale_x_continuous(position = "top") + theme(strip.placement = "outside"),
    "outside, no axis there, grid")
  check_facet(base + facet_grid(am ~ cyl) + theme(strip.text.y = element_text(angle = 0)), "horizontal row strips")
  check_facet(base + facet_grid(am ~ cyl) + theme(strip.background.y = element_rect(fill = "yellow"), strip.text.x = element_text(size = 14)),
    "strip elements")
  check_facet(base + facet_grid(am ~ cyl) + theme(strip.clip = "off"), "unclipped strips")
  # Strip text larger than its strip, clipped to it.
  check_facet(base + facet_wrap(~carb, ncol = 4) + coord_fixed(), "clipped strip text")
  check_facet(base + facet_grid(am ~ cyl, labeller = labeller(am = c(`0` = "automatic transmission", `1` = "manual"))) +
    theme(strip.text.y = element_text(size = 30)), "clipped row strips")
  check_facet(base + facet_grid(vs + am ~ gear, margins = TRUE), "margins, clipped")
  check_facet(ggplot(mpg, aes(drv, model)) + geom_point() + facet_grid(manufacturer ~ ., scales = "free", space = "free") +
    theme(strip.text.y = element_text(angle = 0)), "free space, many rows", size = list(width = 500, height = 700))
})

test_that("facets alot doesn't draw fall back", {
  declined <- function(p) {
    b <- suppressWarnings(ggplot_build(p))
    attr(layout_boxes_rust(b, 400, 300, 96), "reason")
  }
  expect_match(declined(ggplot(data.frame(x = 1:6, y = 1:6, g = c("a", "a", "b", "b", NA, "c")), aes(x, y)) + geom_point() + facet_wrap(~g)), "plain text")
  b <- suppressWarnings(ggplot_build(base + facet_wrap(~cyl, labeller = label_bquote(alpha^.(cyl)))))
  expect_false(is.null(attr(render_full(b, render_size), "reason")))
  expect_match(declined(base + facet_grid(am ~ cyl, labeller = label_bquote(rows = alpha^.(am)))), "not plain text")
  expect_match(declined(base + facet_wrap(~cyl) + theme(strip.text = element_blank())), "blank strips")
  expect_match(declined(base + facet_grid(am ~ cyl) + theme(strip.text.y = element_blank())), "blank strips")
  # ggplot2 warns and leaves these axes out.
  expect_match(declined(base + facet_wrap(~carb, ncol = 4, strip.position = "bottom") + theme(strip.placement = "outside")), "outside strips")
  # ggplot2 aborts on these.
  expect_match(declined(base + facet_wrap(~cyl, scales = "free") + coord_fixed()), "fixed coord")
  b <- suppressWarnings(ggplot_build(base + facet_wrap(~cyl) + coord_flip()))
  expect_false(is.null(attr(render_full(b, render_size), "reason")))
})

test_that("facets laid out but drawn by the hybrid tier match grid's layout", {
  for (p in list(
    base + facet_wrap(~cyl, scales = "free") + coord_flip(),
    base + facet_grid(am ~ cyl, scales = "free_y") + coord_flip()
  )) {
    b <- suppressWarnings(ggplot_build(p))
    expect_null(expect_layout_matches(b))
  }
})
