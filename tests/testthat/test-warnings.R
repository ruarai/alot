# Warning and message parity (T0.7): alot_build() must signal the same
# warnings and messages as ggplot_build(), in the same order.
# expect_build_equal() checks this for every plot; the snapshots below pin the
# text for the common cases.
library(ggplot2)

alot_conditions <- function(p) capture_conditions(alot_build(p))$conditions

test_that("capture_conditions() records warnings and messages in order", {
  out <- capture_conditions({
    message("a")
    warning("b")
    1
  })
  expect_equal(out$value, 1)
  expect_identical(out$conditions, c("message: a\n", "warning: b"))
})

test_that("expect_build_equal() fails when the conditions differ", {
  failures <- 0L
  withCallingHandlers(
    with_mocked_bindings(
      expect_build_equal(ggplot(mtcars, aes(wt, mpg)) + geom_point()),
      alot_build = function(p) {
        warning("extra")
        ggplot2::ggplot_build(p)
      }
    ),
    expectation_failure = function(e) {
      failures <<- failures + 1L
      invokeRestart("continue_test")
    }
  )
  expect_equal(failures, 1L)
})

test_that("removed rows warnings match", {
  # StatIdentity builds don't warn: ggplot2 reports missing values in
  # ggplot_gtable(). Stats that drop rows do warn during the build.
  df <- data.frame(x = c(1, NA, 3, 4), y = c(1, 2, NA, 4))
  p <- ggplot(df, aes(x, y)) + geom_boxplot(aes(group = 1))
  expect_build_equal(p)
  expect_snapshot(alot_conditions(p))

  p <- ggplot(df, aes(x)) + geom_histogram(bins = 5) + xlim(2, 4)
  expect_build_equal(p)
  expect_snapshot(alot_conditions(p))
})

test_that("stat_bin's default-bins message matches", {
  p <- ggplot(mtcars, aes(mpg)) + geom_histogram()
  expect_build_equal(p)
  expect_snapshot(alot_conditions(p))
})

test_that("scale warnings match", {
  p <- ggplot(data.frame(x = c(-1, 1, 4), y = 1:3), aes(x, y)) + geom_point() + scale_x_sqrt()
  expect_build_equal(p)
  expect_snapshot(alot_conditions(p))

  p <- ggplot(mtcars, aes(wt, mpg)) + geom_smooth(method = "lm", formula = y ~ x) +
    scale_x_continuous(transform = "log10") + scale_y_continuous(limits = c(15, 25))
  expect_build_equal(p)
  expect_snapshot(alot_conditions(p))
})

test_that("a clean build signals nothing", {
  expect_identical(alot_conditions(ggplot(mtcars, aes(wt, mpg)) + geom_point()), character())
})
