# Coords and secondary axes in the full tier (R6.6): coord_flip() (the
# geoms decompose in data space, then the marks' axes swap as
# CoordFlip$transform() flips them), coord_fixed()/aspect.ratio and
# secondary axes (sec_axis(), dup_axis(), axes on the top and right),
# against ggplot2 on ragg and grid's boxes. coord_transform() draws points
# and text (no munching); the munched geoms decline.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_coord <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-coords.R", label, b)
  expect_no_warning(
    do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key))),
    class = "alot_render_fallback"
  )
  expect_null(expect_layout_matches(b, utils::modifyList(render_size, size), label = label, cache_key = key))
}

declined <- function(p) {
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  attr(render_full(b, render_size), "reason")
}

pts <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

test_that("coord_flip() draws as ggplot2 draws it", {
  check_coord(pts + coord_flip(), "flipped points")
  check_coord(ggplot(mpg, aes(class)) + geom_bar() + coord_flip(), "flipped bars")
  check_coord(ggplot(mpg, aes(class, fill = drv)) + geom_bar(position = "dodge") + coord_flip(), "flipped dodged bars, legend")
  check_coord(ggplot(mpg, aes(class, hwy)) + geom_boxplot() + coord_flip(), "flipped boxplot")
  check_coord(ggplot(mpg, aes(hwy, class)) + geom_boxplot() + coord_flip(), "horizontal boxplot flipped back")
  check_coord(ggplot(economics, aes(date, unemploy)) + geom_line() + coord_flip(), "flipped line")
  check_coord(ggplot(economics, aes(date, unemploy)) + geom_area(alpha = 0.5) + coord_flip(), "flipped area")
  check_coord(ggplot(mpg, aes(displ, hwy)) + geom_smooth(method = "lm", formula = y ~ x) + coord_flip(), "flipped smooth")
  check_coord(pts + geom_hline(yintercept = 20) + geom_vline(xintercept = 3) + geom_abline(intercept = 37, slope = -5) + coord_flip(),
    "flipped reference lines")
  check_coord(pts + geom_text(aes(label = rownames(mtcars)), size = 2) + coord_flip(), "flipped text")
  check_coord(pts + geom_label(aes(label = as.character(cyl))) + coord_flip(), "flipped labels")
  check_coord(ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_wrap(~drv) + coord_flip(), "flipped facets")
  check_coord(ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_grid(year ~ drv) + coord_flip(), "flipped grid")
  check_coord(pts + coord_flip(ylim = c(10, 30), expand = FALSE), "flipped limits, no expansion")
  check_coord(pts + scale_x_continuous(sec.axis = dup_axis()) + coord_flip(), "flipped secondary axis")
  check_coord(ggplot(mtcars, aes(factor(cyl), mpg)) + geom_violin() + geom_point() + coord_flip(), "flipped violin")
  check_coord(ggplot(mtcars, aes(factor(cyl), mpg)) + geom_pointrange(stat = "summary", fun.data = mean_se) + coord_flip(),
    "flipped pointrange")
})

test_that("fixed ratios and aspect ratios draw as ggplot2 draws them", {
  check_coord(pts + coord_fixed(ratio = 0.2), "fixed ratio")
  check_coord(pts + coord_equal(), "coord_equal")
  check_coord(pts + theme(aspect.ratio = 2), "tall aspect ratio")
  check_coord(pts + theme(aspect.ratio = 0.3), "wide aspect ratio")
  check_coord(pts + coord_fixed() + facet_wrap(~am), "fixed facets")
})

test_that("secondary axes draw as ggplot2 draws them", {
  check_coord(pts + scale_y_continuous(sec.axis = sec_axis(~ . * 2, name = "doubled")), "sec_axis transform")
  check_coord(pts + scale_x_continuous(sec.axis = dup_axis()), "dup_axis x")
  check_coord(pts + scale_y_continuous(sec.axis = sec_axis(~ . / 3, breaks = c(4, 6, 8))), "sec_axis breaks, no name")
  check_coord(pts + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"), "primary axes top and right")
  check_coord(ggplot(mpg, aes(class, hwy)) + geom_point() + scale_x_discrete(sec.axis = dup_axis()), "discrete dup_axis")
  check_coord(pts + scale_y_continuous(sec.axis = sec_axis(~ . * 1.6, name = "km/l")) + facet_wrap(~am), "sec_axis facets")
  check_coord(pts + scale_y_continuous(sec.axis = dup_axis()) + theme(axis.text.y.right = element_text(colour = "red", angle = 90)),
    "secondary axis theme")
})

test_that("coord_transform() points and text draw as ggplot2 draws them", {
  check_coord(pts + coord_transform(x = "log10"), "log10 x")
  check_coord(pts + coord_transform(x = "sqrt", y = "reverse"), "sqrt x, reversed y")
  check_coord(ggplot(diamonds[1:2000, ], aes(carat, price)) + geom_point(alpha = 0.3) + coord_transform(x = "log10", y = "log10"),
    "log-log")
  check_coord(pts + geom_text(aes(label = rownames(mtcars)), size = 2) + coord_transform(y = "log10"), "text")
  check_coord(pts + facet_wrap(~cyl, scales = "free") + coord_transform(x = "log2"), "free facets")
  check_coord(pts + coord_transform(x = "log10", xlim = c(2, 5)), "limits")
  check_coord(ggplot(mpg, aes(class, hwy)) + geom_point() + coord_transform(y = "sqrt"), "discrete x")
})

test_that("coords the full tier doesn't draw decline", {
  expect_match(declined(pts + geom_line() + coord_transform(x = "log10")), "munches")
  expect_match(declined(ggplot(mpg, aes(class)) + geom_bar() + coord_transform(y = "log10")), "munches")
  expect_match(declined(ggplot(data.frame(a = c(1, 2, 0), b = c(10, 6, 4)), aes(a, b)) + geom_point() + coord_transform(x = "log")),
    "infinite")
  expect_match(declined(pts + coord_flip() + geom_rug()), "rug")
  expect_match(declined(pts + coord_cartesian(reverse = "x")), "coord")
  expect_match(declined(pts + coord_polar()), "coord")
})
