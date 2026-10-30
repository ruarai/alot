library(ggplot2)

# Non-position scale training and mapping (T2.1). The mirror dispatches each
# scale; kernels-npscale.R adds the continuous kernels (T2.3).

np_coverage <- function(p) {
  cov <- alot_coverage(p)
  cov[cov$step %in% c("np_train", "np_map", "train_df", "map_df"), ]
}

test_that("the mirror matches ggplot2 across non-position scale types", {
  df <- data.frame(
    x = c(1, 2, 3, 4, NA, 6), y = c(2L, 4L, 1L, NA, 5L, 3L),
    z = c(0.5, NA, 2, -Inf, 3, 1), g = c("a", "b", "a", NA, "c", "b"),
    f = factor(c("u", "v", "u", "v", "u", "v"))
  )
  plots <- list(
    ggplot(df, aes(x, y, colour = z)) + geom_point(),
    ggplot(df, aes(x, y, colour = g, shape = f)) + geom_point(),
    ggplot(df, aes(x, y, fill = g, alpha = z)) + geom_col(),
    ggplot(df, aes(x, y, size = y, linetype = f)) + geom_line(),
    ggplot(df, aes(x, y, colour = z)) + geom_point() + scale_colour_binned(),
    ggplot(df, aes(x, y, colour = g)) + geom_point() +
      scale_colour_manual(values = c(a = "red", b = "blue", c = "green")),
    ggplot(df, aes(x, y, colour = z)) + geom_point() + scale_colour_viridis_c() +
      facet_wrap(~f),
    ggplot(df, aes(x, y, colour = g)) + geom_point() + geom_line(aes(colour = f)),
    ggplot(df, aes(x)) + geom_histogram(aes(fill = after_stat(count)), bins = 3),
    ggplot(df[0, ], aes(x, y, colour = z)) + geom_point(),
    ggplot(df[1, ], aes(x, y, colour = g)) + geom_point(),
    ggplot(df, aes(x, y, colour = z)) + geom_point() +
      geom_point(aes(colour = NULL), data = df[0, ])
  )
  # Rows with NA are removed with a warning, from both builds.
  suppressWarnings(for (p in plots) {
    expect_build_equal(p)
    set.seed(1)
    a <- alot_build(p)
    set.seed(1)
    b <- ggplot_build(p)
    expect_identical(a@data, b@data)
  })
})

test_that("coverage lists each non-position scale's train and map steps", {
  df <- data.frame(x = 1:4, y = 1:4, z = c(1, 2, 3, 4), g = c("a", "b", "a", "b"))
  p <- ggplot(df, aes(x, y, colour = z, shape = g)) + geom_point() + geom_line()
  cov <- np_coverage(p)
  # Two layers, two scales, both steps.
  expect_setequal(unique(cov$step), c("np_train", "np_map"))
  expect_equal(sum(cov$step == "np_train"), 4)
  expect_equal(sum(cov$step == "np_map"), 4)
  expect_setequal(unique(cov$class), c("ScaleContinuous", "ScaleDiscrete"))
  # The continuous colour scale has kernels (T2.3); the shape scale not yet.
  expect_true(all(cov$path[cov$class == "ScaleContinuous"] == "rust"))
  expect_true(all(cov$path[cov$class == "ScaleDiscrete"] == "ggplot2"))

  # No non-position scales: no steps.
  p <- ggplot(df, aes(x, y)) + geom_point()
  expect_equal(nrow(np_coverage(p)), 0)

  # Empty layer data: ScalesList skips the per-scale calls.
  p <- ggplot(df[0, ], aes(x, y, colour = z)) + geom_point()
  expect_equal(nrow(np_coverage(p)), 0)
})

test_that("a registered kernel's result is used", {
  key_train <- "np_train:ScaleContinuous"
  key_map <- "np_map:ScaleContinuous"
  old <- mget(c(key_train, key_map), envir = kernels)
  on.exit(list2env(old, envir = kernels))
  calls <- 0
  register_kernel("np_train", "ScaleContinuous", function(scale, df) {
    calls <<- calls + 1
    scale$train_df(df = df)
    TRUE
  })
  register_kernel("np_map", "ScaleContinuous", function(scale, df) {
    calls <<- calls + 1
    scale$map_df(df = df)
  })

  df <- data.frame(x = 1:4, y = 1:4, z = c(1, NA, 3, 4), g = c("a", "b", "a", "b"))
  p <- ggplot(df, aes(x, y, colour = z, shape = g)) + geom_point()
  expect_build_equal(p)
  cov <- np_coverage(p)
  expect_equal(cov$path[cov$class == "ScaleContinuous"], c("rust", "rust"))
  expect_equal(cov$path[cov$class == "ScaleDiscrete"], c("ggplot2", "ggplot2"))
  expect_gt(calls, 0)

  # A kernel that declines falls back.
  register_kernel("np_map", "ScaleContinuous", function(scale, df) NULL)
  expect_build_equal(p)
  cov <- np_coverage(p)
  expect_equal(cov$path[cov$class == "ScaleContinuous"], c("rust", "ggplot2"))
})

test_that("a ScalesList overriding train_df or map_df falls back whole", {
  scales <- ggplot2:::scales_list()
  scales$add(scale_colour_continuous())
  scales$add(scale_shape())
  df <- data.frame(colour = c(1, 5, NA), shape = c("a", "b", "a"))

  own <- ggproto(NULL, scales,
    train_df = function(self, df, drop = FALSE) {
      ggproto_parent(ggplot2:::ScalesList, self)$train_df(df)
    },
    map_df = function(self, df) {
      ggproto_parent(ggplot2:::ScalesList, self)$map_df(df)
    }
  )
  old <- trace_env$records
  trace_env$records <- list()
  npscales_train_df(own, df)
  out <- npscales_map_df(own, df)
  recs <- trace_env$records
  trace_env$records <- old
  expect_identical(vapply(recs, `[[`, "", "step"), c("train_df", "map_df"))
  expect_identical(vapply(recs, `[[`, "", "path"), c("ggplot2", "ggplot2"))

  ref <- ggplot2:::scales_list()
  ref$add(scale_colour_continuous())
  ref$add(scale_shape())
  ref$train_df(df)
  expect_identical(out, ref$map_df(df))

  # The plain mirror gives the same result.
  mine <- ggplot2:::scales_list()
  mine$add(scale_colour_continuous())
  mine$add(scale_shape())
  expect_null(npscales_train_df(mine, df[0, ]))
  npscales_train_df(mine, df)
  expect_identical(npscales_map_df(mine, df), out)
  expect_identical(npscales_map_df(mine, df[0, ]), df[0, ])
})
