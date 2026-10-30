library(ggplot2)

# Position mapping (T1.2). Besides expect_build_equal(), check the layer data
# is identical, which also tells NA from NaN and integer from double.
expect_map_equal <- function(p) {
  set.seed(1)
  a <- alot_build(p)
  set.seed(1)
  b <- ggplot2::ggplot_build(p)
  expect_identical(a@data, b@data)
  expect_build_equal(p)
}

map_paths <- function(p, class) {
  cov <- alot_coverage(p)
  cov$path[cov$step == "scale_map" & cov$class == class]
}
maps_in_rust <- function(p, class) {
  paths <- map_paths(p, class)
  length(paths) > 0 && all(paths == "rust")
}
# Some map of `class` fell back. Not all need to: x and y share a class,
# and the second pass maps what the stat returned (mapped_discrete values
# on a discrete scale, which the kernel handles).
map_falls_back <- function(p, class) {
  any(map_paths(p, class) == "ggplot2")
}

cont <- "ScaleContinuousPosition"
disc <- "ScaleDiscretePosition"

test_that("continuous position mapping runs in Rust and matches ggplot2", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  expect_true(maps_in_rust(p, cont))
  expect_map_equal(p)
  expect_map_equal(ggplot(mtcars, aes(wt, mpg)) + geom_smooth(method = "lm", formula = y ~ x))
  expect_map_equal(ggplot(mtcars, aes(mpg)) + geom_histogram(bins = 10))
})

test_that("each oob function matches ggplot2, with NA, NaN, Inf and integers", {
  df <- data.frame(
    x = c(1L, 5L, NA, 3L, 8L, 2L, 10L, 4L),
    y = c(0.5, NA, Inf, -Inf, 2, 10, NaN, -3),
    g = rep(c("a", "b"), 4)
  )
  oobs <- list(scales::censor, scales::squish, scales::squish_infinite, scales::oob_keep,
    scales::oob_censor_any, scales::oob_squish_any)
  for (oob in oobs) {
    p <- ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) +
      scale_x_continuous(limits = c(2, 8), oob = oob) +
      scale_y_continuous(limits = c(0, 5), oob = oob)
    expect_true(maps_in_rust(p, cont))
    expect_map_equal(p)
    expect_map_equal(p + facet_wrap(~g, scales = "free"))
    expect_map_equal(p + scale_y_continuous(limits = c(5, 0), oob = oob))
  }
  # Default limits, and limits with an NA end taken from the range.
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE))
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) +
    scale_y_continuous(limits = c(NA, 1), oob = scales::squish))
})

test_that("na.value replaces NA and NaN as in ggplot2", {
  df <- data.frame(x = c(1, NA, NaN, 4, 100), y = c(NA_integer_, 2L, 3L, 4L, 5L))
  for (na in list(0, 7L, NA, NA_real_, -Inf)) {
    p <- ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) +
      scale_x_continuous(limits = c(0, 10), na.value = na) +
      scale_y_continuous(na.value = na)
    expect_true(maps_in_rust(p, cont))
    expect_map_equal(p)
  }
})

test_that("transformed continuous scales match ggplot2", {
  df <- data.frame(x = c(0.1, 1, 10, 100, NA, 0, -1), y = 1:7)
  # Both builds warn about the NaN and -Inf the transforms produce.
  suppressWarnings(expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) + scale_x_log10()))
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) + scale_y_reverse(limits = c(6, 2)))
  suppressWarnings(expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) +
    scale_x_sqrt(limits = c(0, 50))))
})

test_that("continuous mapping across panels, layers and range aesthetics", {
  df <- data.frame(x = c(1, 2, 3, 4, 5, 6), y = c(2, 4, 1, 8, 3, 9), g = rep(c("p", "q", "r"), 2))
  p <- ggplot(df, aes(x, y)) + geom_point() + geom_line() +
    geom_rect(aes(xmin = x - 1, xmax = x + 1, ymin = 0, ymax = y), alpha = 0.2)
  expect_map_equal(p)
  expect_map_equal(p + facet_wrap(~g))
  expect_map_equal(p + facet_wrap(~g, scales = "free") + scale_x_continuous(limits = c(1.5, 5)))
  expect_map_equal(p + facet_grid(g ~ ., scales = "free_y") + coord_flip())
})

test_that("single-row and empty data match ggplot2", {
  expect_map_equal(ggplot(data.frame(x = 1, y = 2), aes(x, y)) + geom_point())
  expect_map_equal(ggplot(data.frame(x = NA_real_, y = 2), aes(x, y)) + geom_point(na.rm = TRUE))
  expect_map_equal(ggplot(data.frame(x = numeric(), y = numeric()), aes(x, y)) + geom_point())
  expect_map_equal(ggplot(data.frame(x = character(), y = numeric()), aes(x, y)) + geom_point())
  expect_map_equal(ggplot(data.frame(x = numeric(), y = numeric()), aes(x, y)) + geom_point() +
    geom_point(data = data.frame(x = 3, y = 1)))
})

test_that("unsupported continuous scales and oob functions fall back to ggplot2", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  expect_true(map_falls_back(p + scale_y_continuous(oob = function(x, range) x), cont))
  expect_map_equal(p + scale_y_continuous(oob = function(x, range) x))
  # allow_lambda() turns a formula into a new function.
  expect_true(map_falls_back(p + scale_y_continuous(oob = ~ scales::censor(.x, .y)), cont))
  expect_true(map_falls_back(p + scale_y_continuous(na.value = "a"), cont))
  expect_map_equal(p + scale_y_continuous(na.value = "a"))

  custom <- ggproto(NULL, scale_y_continuous(), map = function(self, x, limits = self$get_limits()) {
    ggproto_parent(ScaleContinuousPosition, self)$map(x, limits)
  })
  expect_true(map_falls_back(p + custom, cont))
  expect_map_equal(p + custom)

  sub <- ggproto("ScaleContinuousPositionSub", scale_y_continuous())
  expect_true(map_falls_back(p + sub, "ScaleContinuousPositionSub"))
  expect_map_equal(p + sub)

  df <- data.frame(x = as.Date("2024-01-01") + 0:4, y = 1:5)
  expect_true(map_falls_back(ggplot(df, aes(x, y)) + geom_point(), "ScaleContinuousDate"))
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point())
  expect_map_equal(ggplot(mtcars, aes(wt, mpg)) + geom_point() + scale_x_binned())
})

test_that("discrete position mapping runs in Rust and matches ggplot2", {
  p <- ggplot(mpg, aes(class, hwy)) + geom_boxplot()
  expect_true(maps_in_rust(p, disc))
  expect_map_equal(p)
  expect_map_equal(ggplot(mpg, aes(hwy, class)) + geom_point())
  expect_map_equal(ggplot(mpg, aes(drv, fill = class)) + geom_bar(position = "dodge"))
  expect_map_equal(ggplot(mpg, aes(drv, hwy)) + geom_violin() + facet_wrap(~year))
  expect_map_equal(ggplot(mpg, aes(class)) + geom_bar() + coord_flip())
})

test_that("factor, character and logical input with NA match ggplot2", {
  df <- data.frame(
    f = factor(c("b", NA, "a", "b", "c", NA), levels = c("c", "b", "a", "unused")),
    o = factor(c("lo", "hi", "lo", NA, "mid", "hi"), levels = c("lo", "mid", "hi"), ordered = TRUE),
    s = c("b", NA, "a", "b", "C", "a"),
    l = c(TRUE, NA, FALSE, TRUE, TRUE, FALSE),
    y = c(1, 2, 3, 4, 5, 6),
    g = c("p", "p", "q", "q", "r", "r")
  )
  for (v in c("f", "o", "s", "l")) {
    p <- ggplot(df, aes(.data[[v]], y)) + geom_point(na.rm = TRUE)
    expect_true(maps_in_rust(p, disc))
    expect_map_equal(p)
    expect_map_equal(p + scale_x_discrete(na.translate = FALSE))
    expect_map_equal(p + scale_x_discrete(drop = FALSE))
    expect_map_equal(p + facet_wrap(~g, scales = "free_x"))
    expect_map_equal(p + facet_wrap(~g, scales = "free_x") + scale_x_discrete(drop = FALSE))
    expect_map_equal(ggplot(df, aes(y, .data[[v]])) + geom_point(na.rm = TRUE) +
      facet_grid(g ~ ., scales = "free_y"))
  }
})

test_that("discrete limits and palettes match ggplot2", {
  df <- data.frame(x = c("a", "b", "c", "a", NA), y = 1:5)
  p <- ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE)
  expect_map_equal(p + scale_x_discrete(limits = c("c", "a")))
  expect_map_equal(p + scale_x_discrete(limits = c("c", NA, "a", "zz")))
  expect_map_equal(p + scale_x_discrete(limits = rev))
  expect_map_equal(p + scale_x_discrete(palette = function(n) seq_len(n) * 2.5))
  expect_map_equal(p + scale_x_discrete(palette = function(n) rev(seq_len(n + 2))))
  expect_true(maps_in_rust(p + scale_x_discrete(palette = function(n) seq_len(n) * 2.5), disc))
})

test_that("factors with an NA level and mixed encodings match ggplot2", {
  df <- data.frame(x = factor(c("a", NA, "b"), exclude = NULL), y = 1:3)
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point())
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point(na.rm = TRUE) + scale_x_discrete(na.translate = FALSE))

  e_utf8 <- "é"
  e_latin1 <- iconv(e_utf8, "UTF-8", "latin1")
  df <- data.frame(x = c("b", e_latin1, "a", e_utf8, "b", e_latin1), y = 1:6)
  p <- ggplot(df, aes(x, y)) + geom_point()
  expect_true(maps_in_rust(p, disc))
  expect_map_equal(p)
  lv <- data.frame(x = factor(c(e_latin1, "b")), y = 7:8)
  expect_map_equal(p + geom_point(data = lv))
})

test_that("mixed factor, character and continuous layers match ggplot2", {
  fct <- data.frame(x = factor(c("m", "z", "a"), levels = c("z", "m", "a", "q")), y = 1:3)
  chr <- data.frame(x = c("b", "z", NA, "0"), y = 4:7)
  lgl <- data.frame(x = c(TRUE, NA), y = 8:9)
  p <- ggplot(mapping = aes(x, y)) + geom_point(data = fct) + geom_point(data = chr)
  expect_map_equal(p)
  expect_map_equal(p + geom_point(data = lgl))
  expect_map_equal(p + annotate("point", x = c(2L, NA, 7L), y = 2, na.rm = TRUE))
  expect_map_equal(p + annotate("rect", xmin = -1, xmax = 0.5, ymin = 1, ymax = 2))
  expect_map_equal(p + annotate("point", x = c(NA, Inf, -Inf, 0.25, NaN), y = 2, na.rm = TRUE))
})

test_that("single-row and empty discrete data match ggplot2", {
  expect_map_equal(ggplot(data.frame(x = "a", y = 1), aes(x, y)) + geom_point())
  expect_map_equal(ggplot(data.frame(x = factor(NA), y = 1), aes(x, y)) + geom_point())
  expect_map_equal(ggplot(data.frame(x = NA, y = 1), aes(x, y)) + geom_point())
  empty <- data.frame(x = character(), y = numeric())
  expect_map_equal(ggplot(empty, aes(x, y)) + geom_point() + geom_point(data = data.frame(x = "b", y = 2)))
})

test_that("unsupported discrete input and scales fall back to ggplot2", {
  # AsIs columns never reach the scales (.ignore_data()); check anyway.
  df <- data.frame(x = I(c("a", "b")), y = 1:2, z = c("p", "q"))
  expect_map_equal(ggplot(df, aes(x, y)) + geom_point() + geom_point(aes(z, y)))

  df <- data.frame(y = 1:3)
  df$x <- structure(factor(c("a", "b", "a")), class = c("my_factor", "factor"))
  p <- ggplot(df, aes(x, y)) + geom_point()
  expect_true(map_falls_back(p, disc))
  expect_map_equal(p)

  p <- ggplot(mpg, aes(class, hwy)) + geom_point()
  # Numeric limits on a discrete scale.
  # (ggplot2 also warns that the guide is perpendicular.)
  expect_true(suppressWarnings(map_falls_back(p + scale_x_discrete(limits = function(x) seq_along(x)), disc)))
  # A named palette.
  named <- function(n) stats::setNames(seq_len(n), letters[seq_len(n)])
  expect_true(map_falls_back(p + scale_x_discrete(palette = named), disc))
  expect_map_equal(p + scale_x_discrete(palette = named))
  # Palette errors are raised by ggplot2's own method.
  short <- p + scale_x_discrete(palette = function(n) 1)
  expect_identical(
    tryCatch(alot_build(short), error = conditionMessage),
    tryCatch(ggplot_build(short), error = conditionMessage)
  )

  custom <- ggproto(NULL, scale_x_discrete(), map = function(self, x, limits = self$get_limits()) {
    ggproto_parent(ScaleDiscretePosition, self)$map(x, limits)
  })
  expect_true(map_falls_back(p + custom, disc))
  expect_map_equal(p + custom)

  sub <- ggproto("ScaleDiscretePositionSub", scale_x_discrete())
  expect_true(map_falls_back(p + sub, "ScaleDiscretePositionSub"))
  expect_map_equal(p + sub)
})

test_that("a layout overriding map_position falls back whole", {
  p <- ggplot(mpg, aes(class, hwy)) + geom_point()
  layout <- ggproto(NULL, Layout, map_position = function(self, data) {
    ggproto_parent(Layout, self)$map_position(data)
  })
  p@layout <- layout
  cov <- alot_coverage(p)
  expect_true(any(cov$step == "map_position" & cov$path == "ggplot2"))
  expect_false(any(cov$step == "scale_map"))
  expect_map_equal(p)
})

test_that("scales_map() mirrors scale_apply() with kernels off", {
  # The fallback path itself, on interleaved panels and an unmapped panel.
  scales <- lapply(1:3, function(i) scale_x_continuous(limits = c(0, i))$clone())
  df <- data.frame(x = c(0.5, 2.5, 1.5, -1, 3, NA))
  id <- c(1L, 3L, 2L, 1L, 3L, 1L)
  old <- options(alot.kernels = FALSE)
  on.exit(options(old))
  off <- scales_map(df, c(x = "x"), id, scales)
  options(alot.kernels = TRUE)
  on <- scales_map(df, c(x = "x"), id, scales)
  ref <- utils::getFromNamespace("scale_apply", "ggplot2")(df, c(x = "x"), "map", id, scales)
  expect_identical(off, ref)
  expect_identical(on, ref)
})
