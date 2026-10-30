library(ggplot2)

test_that("basic geoms match ggplot2", {
  expect_build_equal(ggplot(mtcars, aes(wt, mpg)) + geom_point())
  expect_build_equal(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_line())
  expect_build_equal(ggplot(mpg, aes(class)) + geom_bar())
  expect_build_equal(ggplot(mpg, aes(class, fill = drv)) + geom_bar(position = "dodge"))
  expect_build_equal(ggplot(mtcars, aes(mpg)) + geom_histogram(bins = 20))
  expect_build_equal(ggplot(mtcars, aes(mpg, fill = factor(am))) + geom_density(alpha = 0.3))
  expect_build_equal(ggplot(mpg, aes(class, hwy)) + geom_boxplot())
  expect_build_equal(ggplot(mtcars, aes(wt, mpg)) + geom_point() + geom_smooth(method = "lm"))
  expect_build_equal(ggplot(mtcars, aes(wt, mpg)) + geom_jitter())
  expect_build_equal(ggplot())
})

test_that("facets, coords and scales match ggplot2", {
  base <- ggplot(mpg, aes(displ, hwy, colour = cty)) + geom_point()
  expect_build_equal(base + facet_wrap(~class))
  expect_build_equal(base + facet_grid(drv ~ cyl, scales = "free"))
  expect_build_equal(base + coord_flip())
  expect_build_equal(base + scale_x_log10() + scale_colour_viridis_c())
  expect_build_equal(base + coord_cartesian(xlim = c(2, 5)))
})

test_that("coverage reports every dispatched component", {
  cov <- alot_coverage(ggplot(mtcars, aes(wt, mpg)) + geom_point())
  expect_setequal(cov$class, c("FacetNull", "ScaleContinuousPosition", "StatIdentity", "PositionIdentity"))
  expect_true(all(cov$path %in% c("rust", "ggplot2")))
})
