library(ggplot2)

uses_rust <- function(p, step = "scale_train") {
  cov <- alot_coverage(p)
  any(cov$step == step & cov$path == "rust")
}

test_that("continuous position training runs in Rust and matches ggplot2", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  expect_true(uses_rust(p))
  expect_build_equal(p)
})

test_that("training handles integers, NA, Inf and multiple scales", {
  df <- data.frame(
    x = c(1L, 5L, NA, 3L, 8L, 2L),
    y = c(0.5, NA, Inf, -Inf, 2, 10),
    g = c("a", "a", "b", "b", "c", "c")
  )
  expect_build_equal(ggplot(df, aes(x, y)) + geom_point())
  expect_build_equal(ggplot(df, aes(x, y)) + geom_point() + facet_wrap(~g, scales = "free"))
  expect_build_equal(ggplot(df, aes(x, y)) + geom_point() + facet_grid(g ~ ., scales = "free_y"))
})

test_that("panels whose values are all non-finite match ggplot2", {
  df <- data.frame(x = c(1, 2, NA, NA), y = c(1, 2, 3, 4), g = c("a", "a", "b", "b"))
  expect_build_equal(
    suppressWarnings(ggplot(df, aes(x, y)) + geom_point() + facet_wrap(~g, scales = "free_x"))
  )
})

test_that("unsupported scales fall back to ggplot2", {
  df <- data.frame(x = as.Date("2024-01-01") + 0:9, y = 1:10)
  p <- ggplot(df, aes(x, y)) + geom_line()
  cov <- alot_coverage(p)
  expect_true(any(cov$class == "ScaleContinuousDate" & cov$path == "ggplot2"))
  expect_build_equal(p)
  expect_build_equal(ggplot(mpg, aes(class, hwy)) + geom_boxplot())
})

test_that("scales that override train() fall back to ggplot2", {
  # Found by the corpus (test-scales.R: ViewScales can make fixed copies).
  b <- ggplot_build(ggplot(mpg, aes(drv, displ)) + geom_boxplot())@layout$panel_params[[1]]
  p <- ggplot(mpg, aes(drv, cyl)) + geom_violin() + annotate("point", x = 15, y = 100) +
    b$y$make_fixed_copy()
  # The fixed y scale censors most rows, so both builds warn.
  cov <- suppressWarnings(alot_coverage(p))
  expect_true(all(cov$path[cov$step == "scale_train" & cov$class == "ScaleContinuousPosition"] == "ggplot2"))
  suppressWarnings(expect_build_equal(p))
})
