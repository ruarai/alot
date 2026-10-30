library(ggplot2)

# Scale transforms (T1.3). Besides expect_build_equal(), check the layer data
# is identical and that both builds raise the same warnings, calls included.
capture_warnings <- function(expr) {
  w <- list()
  value <- withCallingHandlers(expr, warning = function(c) {
    w[[length(w) + 1L]] <<- c
    invokeRestart("muffleWarning")
  })
  list(value = value, warnings = w)
}

expect_transform_equal <- function(p) {
  set.seed(1)
  a <- capture_warnings(alot_build(p))
  set.seed(1)
  b <- capture_warnings(ggplot2::ggplot_build(p))
  expect_identical(a$value@data, b$value@data)
  expect_identical(a$warnings, b$warnings)
  suppressWarnings(expect_build_equal(p))
}

transform_paths <- function(p) {
  cov <- suppressWarnings(alot_coverage(p))
  cov$path[cov$step == "scale_transform"]
}
transforms_in_rust <- function(p) {
  paths <- transform_paths(p)
  length(paths) > 0 && all(paths == "rust")
}
transform_falls_back <- function(p) any(transform_paths(p) == "ggplot2")

bits <- function(x) {
  r <- writeBin(as.double(x), raw(), endian = "little")
  vapply(split(r, rep(seq_along(x), each = 8)), function(b) paste(rev(b), collapse = ""), "")
}

test_that("Rust's log10, sqrt and reverse match R's bit for bit", {
  set.seed(42)
  tiny <- .Machine$double.xmin
  grid <- c(
    0, -0, Inf, -Inf, NA, NaN, -NA_real_, -NaN, Inf - Inf,
    5e-324, 2 * 5e-324, 2^-1060, tiny / 3, tiny * (1 - 2^-52), tiny,
    -5e-324, -tiny, .Machine$double.xmax, -.Machine$double.xmax,
    10^(-320:308), -10^(-5:5), 1 + (-5:5) * .Machine$double.eps,
    2^(-1074:1023),
    stats::runif(1e5, -10, 10),
    exp(stats::runif(1e5, -740, 709)),
    5e-324 * sample.int(2^20, 1e4)
  )
  refs <- list(
    list(code = 0L, fn = scales::transform_log10()$transform),
    list(code = 1L, fn = scales::transform_sqrt()$transform),
    list(code = 2L, fn = scales::transform_reverse()$transform)
  )
  for (ref in refs) {
    expected <- suppressWarnings(ref$fn(grid))
    out <- rs_transform(grid, ref$code)
    expect_identical(bits(out$x), bits(expected))

    ints <- c(NA, 0L, 1L, -1L, .Machine$integer.max, -.Machine$integer.max, sample.int(1e6, 1e3) - 5e5L)
    expected <- suppressWarnings(ref$fn(ints))
    out <- rs_transform(ints, ref$code)
    expect_identical(out$x, expected)
    expect_identical(bits(out$x), bits(expected))
  }
})

test_that("the NaN warning and check_transformation() warning match ggplot2", {
  dfi <- data.frame(x = c(1L, 10L, 100L, NA, 0L, -1L, 3L), y = 1:7)
  dfd <- data.frame(x = c(0.1, 1, 10, 100, NA, 0, -1), y = 1:7)
  # Both warnings, finiteness only (log10(0), sqrt never), and none.
  for (sc in list(scale_x_log10(), scale_x_sqrt(), scale_x_reverse())) {
    for (df in list(dfi, dfd)) {
      p <- ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) + sc
      expect_true(transforms_in_rust(p))
      expect_transform_equal(p)
    }
  }
  w <- capture_warnings(alot_build(ggplot(dfi, aes(x, y)) + geom_point(na.rm = TRUE) + scale_x_log10()))
  expect_identical(vapply(w$warnings, conditionMessage, ""),
    c("NaNs produced", "log-10 transformation introduced infinite values."))
  expect_transform_equal(ggplot(data.frame(x = c(0L, 1L), y = 1:2), aes(x, y)) + geom_point() + scale_x_log10())
  expect_transform_equal(ggplot(data.frame(x = c(-4, 4), y = 1:2), aes(x, y)) + geom_point(na.rm = TRUE) +
    scale_x_sqrt())
  # A single row takes R's scalar path, whose warning call differs, so it
  # falls back.
  for (x in list(-1, -1L, 0, c(-1L, 4L))) {
    for (sc in list(scale_x_log10(), scale_x_sqrt())) {
      p <- ggplot(data.frame(x = x, y = 1), aes(x, y)) + geom_point(na.rm = TRUE) + sc
      expect_identical(transforms_in_rust(p), length(x) > 1)
      expect_transform_equal(p)
    }
  }
})

test_that("NA, Inf, integer, empty and single-row data match ggplot2", {
  df <- data.frame(
    x = c(1L, NA, 3L, 100L, 7L, 2L),
    y = c(NA, Inf, -Inf, 2.5, NaN, 1e-300),
    g = c("a", "a", "b", "b", "c", "c")
  )
  for (sx in list(scale_x_log10(), scale_x_sqrt(), scale_x_reverse())) {
    for (sy in list(scale_y_log10(), scale_y_sqrt(), scale_y_reverse())) {
      p <- ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) + sx + sy
      expect_true(transforms_in_rust(p))
      expect_transform_equal(p)
      expect_transform_equal(p + facet_wrap(~g, scales = "free"))
    }
  }
  expect_transform_equal(ggplot(data.frame(x = 5, y = 2L), aes(x, y)) + geom_point() + scale_x_log10() +
    scale_y_reverse())
  expect_transform_equal(ggplot(data.frame(x = numeric(), y = numeric()), aes(x, y)) + geom_point() +
    scale_x_log10())
  expect_transform_equal(ggplot(data.frame(x = numeric(), y = numeric()), aes(x, y)) + geom_point() +
    geom_point(data = data.frame(x = 3, y = 1)) + scale_x_sqrt())
})

test_that("transforms across layers, range aesthetics, stats and non-position scales", {
  df <- data.frame(x = c(1, 2, 4, 8, 16, 32), y = c(2, 4, 1, 8, 3, 9), g = rep(c("p", "q", "r"), 2))
  p <- ggplot(df, aes(x, y)) + geom_point() + geom_line() +
    geom_rect(aes(xmin = x / 2, xmax = x * 2, ymin = 1, ymax = y), alpha = 0.2)
  expect_transform_equal(p + scale_x_log10())
  expect_transform_equal(p + scale_y_sqrt() + scale_x_reverse())
  expect_transform_equal(p + scale_x_log10() + facet_wrap(~g) + coord_flip())
  expect_transform_equal(ggplot(mtcars, aes(mpg)) + geom_histogram(bins = 10) + scale_x_log10())
  expect_transform_equal(ggplot(mtcars, aes(wt, mpg)) + geom_smooth(method = "lm", formula = y ~ x) +
    scale_y_log10())
  expect_transform_equal(ggplot(mpg, aes(class, hwy)) + geom_boxplot() + scale_y_sqrt())
  expect_transform_equal(ggplot(mtcars, aes(wt, mpg)) + geom_point() + scale_x_binned(transform = "log10"))

  q <- ggplot(mtcars, aes(wt, mpg, colour = as.integer(hp), size = disp)) + geom_point() +
    scale_colour_gradient(transform = "log10") + scale_size(transform = "sqrt")
  expect_true(transforms_in_rust(q))
  expect_transform_equal(q)
  expect_transform_equal(ggplot(mtcars, aes(wt, mpg, fill = hp)) + geom_point(shape = 21) +
    scale_fill_binned(transform = "reverse"))
  expect_transform_equal(ggplot(mtcars, aes(wt, mpg, alpha = hp)) + geom_point() +
    scale_alpha_continuous(transform = "log10"))
})

test_that("an identity transform is skipped as in ggplot2, with no dispatch", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point() + scale_x_continuous(transform = "identity")
  expect_identical(transform_paths(p), character())
  expect_transform_equal(p)
})

test_that("unsupported transforms, scales and inputs fall back to ggplot2", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  others <- list(
    scales::transform_log(2), scales::transform_log(exp(1)), scales::transform_log1p(),
    scales::transform_reciprocal(), scales::transform_exp(), scales::transform_pseudo_log(),
    # Recognised names with other functions, and a lookalike closure.
    scales::new_transform("log-10", function(x) log(x, 10), function(x) 10^x),
    scales::new_transform("sqrt", function(x) sqrt(x), function(x) x^2),
    scales::new_transform("reverse", function(x) -x, function(x) -x),
    scales::new_transform("log-10", local({
      base <- 10
      function(x) log(x, base)
    }), function(x) 10^x)
  )
  # Integer x, which every recognised transform would handle.
  p_int <- ggplot(mtcars, aes(as.integer(hp), mpg)) + geom_point()
  for (tr in others) {
    q <- p_int + scale_x_continuous(transform = tr)
    expect_true(transform_falls_back(q))
    suppressWarnings(expect_transform_equal(q))
  }
  expect_true(transforms_in_rust(p + scale_x_log10()))
  # A log transform whose `base` is not 10 under the log-10 name.
  renamed <- scales::transform_log(2)
  renamed$name <- "log-10"
  q <- p_int + scale_x_continuous(transform = renamed)
  expect_true(transform_falls_back(q))

  custom <- ggproto(NULL, scale_x_sqrt(), transform = function(self, x) sqrt(x))
  expect_true(transform_falls_back(p + custom))
  expect_transform_equal(p + custom)
  custom_df <- ggproto(NULL, scale_x_sqrt(), transform_df = function(self, df) {
    ggproto_parent(ScaleContinuousPosition, self)$transform_df(df)
  })
  expect_true(transform_falls_back(p + custom_df))
  expect_transform_equal(p + custom_df)

  sub <- ggproto("ScaleContinuousPositionSub", scale_x_sqrt())
  expect_true(transform_falls_back(p + sub))
  expect_transform_equal(p + sub)

  df <- data.frame(x = as.Date("2024-01-01") + 0:4, y = 1:5)
  q <- ggplot(df, aes(x, y)) + geom_point() + scale_y_reverse()
  cov <- alot_coverage(q)
  expect_identical(cov$path[cov$step == "scale_transform" & cov$class == "ScaleContinuousDate"], "ggplot2")
  expect_transform_equal(q)

  # Columns with attributes and non-numeric columns.
  scales <- ggplot2:::scales_list()
  scales$add(scale_x_sqrt())
  scales$add(scale_y_reverse())
  for (df in list(
    data.frame(x = I(c(1, 10)), y = c(4, 9)),
    list2DF(list(x = c(a = 1, b = 10), y = c(4, 9))),
    list2DF(list(x = structure(c(1, 10), foo = "bar"), y = c(4, 9))),
    data.frame(x = c(TRUE, FALSE), y = c(4, 9))
  )) {
    old <- trace_env$records
    trace_env$records <- list()
    out <- suppressWarnings(scales_transform_df(scales, df))
    recs <- trace_env$records
    trace_env$records <- old
    expect_identical(recs[[1]]$path, "ggplot2")
    expect_identical(recs[[2]]$path, "rust")
    expect_identical(out, suppressWarnings(scales$transform_df(df)))
  }

  # A ScalesList that overrides transform_df falls back whole.
  own <- ggproto(NULL, scales, transform_df = function(self, df) {
    ggproto_parent(ggplot2:::ScalesList, self)$transform_df(df)
  })
  df <- data.frame(x = c(1, 10), y = c(4, 9))
  expect_identical(scales_transform_df(own, df), scales$transform_df(df))
})
