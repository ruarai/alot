# Build `p` with both alot and ggplot2 under the same seed and check the
# results are identical.
expect_build_equal <- function(p, seed = 1) {
  set.seed(seed)
  a <- alot_build(p)
  set.seed(seed)
  b <- ggplot2::ggplot_build(p)
  expect_s3_class(a, "ggplot_built")
  expect_equal(a@data, b@data, tolerance = 1e-8)
  expect_equal(a@layout$layout, b@layout$layout)
  expect_equal(a@layout$panel_params, b@layout$panel_params, tolerance = 1e-8)
  expect_equal(a@plot@labels, b@plot@labels)
  expect_no_error(suppressWarnings(ggplot2::ggplot_gtable(a)))
  invisible(a)
}
