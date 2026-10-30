library(ggplot2)

test_that("step_times() times every build step and leaves timing off afterwards", {
  p <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point()
  times <- step_times(p)
  expect_true(all(c("layer_data", "train_position_1", "compute_statistic",
                    "setup_panel_params", "npscales_map", "finish_data") %in% times$step))
  expect_false(anyDuplicated(times$step) > 0)
  expect_true(all(times$seconds >= 0))
  expect_null(timing_env$times)
  expect_build_equal(p)
})

test_that("options(alot.kernels = FALSE) sends every component to ggplot2", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  expect_true(any(alot_coverage(p)$path == "rust"))
  old <- options(alot.kernels = FALSE)
  on.exit(options(old))
  expect_true(all(alot_coverage(p)$path == "ggplot2"))
  expect_build_equal(p)
})
