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

# Discrete position training (T1.1). Besides the build, compare the trained
# ranges themselves: range$range, range$factor and range_c$range of every
# panel scale.
expect_discrete_ranges_equal <- function(p) {
  set.seed(1)
  a <- alot_build(p)@layout
  set.seed(1)
  b <- ggplot2::ggplot_build(p)@layout
  ranges <- function(scales) {
    lapply(scales, function(s) {
      if (!inherits(s, "ScaleDiscretePosition")) return(NULL)
      list(range = s$range$range, factor = s$range$factor, range_c = s$range_c$range)
    })
  }
  expect_identical(ranges(a$panel_scales_x), ranges(b$panel_scales_x))
  expect_identical(ranges(a$panel_scales_y), ranges(b$panel_scales_y))
  expect_build_equal(p)
}

uses_rust_discrete <- function(p) {
  cov <- alot_coverage(p)
  any(cov$step == "scale_train" & cov$class == "ScaleDiscretePosition" & cov$path == "rust")
}

test_that("discrete position training runs in Rust and matches ggplot2", {
  p <- ggplot(mpg, aes(class, hwy)) + geom_boxplot()
  expect_true(uses_rust_discrete(p))
  expect_discrete_ranges_equal(p)
  expect_discrete_ranges_equal(ggplot(mpg, aes(hwy, class)) + geom_point())
  expect_discrete_ranges_equal(ggplot(mpg, aes(drv, fill = class)) + geom_bar(position = "dodge"))
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
    p <- ggplot(df, aes(.data[[v]], y)) + geom_point()
    expect_true(uses_rust_discrete(p))
    expect_discrete_ranges_equal(p)
    expect_discrete_ranges_equal(p + scale_x_discrete(na.translate = FALSE))
    expect_discrete_ranges_equal(p + scale_x_discrete(drop = FALSE))
    expect_discrete_ranges_equal(p + facet_wrap(~g, scales = "free_x"))
    expect_discrete_ranges_equal(p + facet_wrap(~g, scales = "free_x") + scale_x_discrete(drop = FALSE))
    expect_discrete_ranges_equal(ggplot(df, aes(y, .data[[v]])) + geom_point() +
      facet_grid(g ~ ., scales = "free_y"))
  }
})

test_that("factors with an NA level match ggplot2", {
  df <- data.frame(x = factor(c("a", NA, "b"), exclude = NULL), y = 1:3)
  expect_discrete_ranges_equal(ggplot(df, aes(x, y)) + geom_point())
  expect_discrete_ranges_equal(ggplot(df, aes(x, y)) + geom_point() + scale_x_discrete(na.translate = FALSE))
})

test_that("mixed factor and character layers merge as in ggplot2", {
  fct <- data.frame(x = factor(c("m", "z", "a"), levels = c("z", "m", "a", "q")), y = 1:3)
  chr <- data.frame(x = c("b", "z", NA, "0"), y = 4:7)
  lgl <- data.frame(x = c(TRUE, NA), y = 8:9)
  expect_discrete_ranges_equal(ggplot(mapping = aes(x, y)) + geom_point(data = fct) + geom_point(data = chr))
  expect_discrete_ranges_equal(ggplot(mapping = aes(x, y)) + geom_point(data = chr) + geom_point(data = fct))
  expect_discrete_ranges_equal(ggplot(mapping = aes(x, y)) + geom_point(data = chr) + geom_point(data = lgl))
  expect_discrete_ranges_equal(ggplot(mapping = aes(x, y)) + geom_point(data = chr) + geom_point(data = fct) +
    scale_x_discrete(drop = FALSE))
})

test_that("locale-sensitive and mixed-encoding strings match ggplot2", {
  e_utf8 <- "é"
  e_latin1 <- iconv(e_utf8, "UTF-8", "latin1")
  df <- data.frame(
    x = c("b", "B", "a", "A", "_z", "ä", e_latin1, "10", "9", e_utf8, "a"),
    y = seq_len(11)
  )
  p <- ggplot(df, aes(x, y)) + geom_point()
  # testthat collates in "C"; also try a natural-language collation.
  expect_discrete_ranges_equal(p)
  old <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", old), add = TRUE)
  for (loc in c("en_AU.UTF-8", "en_US.UTF-8")) {
    if (!identical(suppressWarnings(Sys.setlocale("LC_COLLATE", loc)), "")) break
  }
  skip_if(Sys.getlocale("LC_COLLATE") %in% c("C", "POSIX"), "no natural-language locale")
  expect_false(identical(sort(c("b", "B", "a")), c("B", "a", "b")))
  expect_discrete_ranges_equal(p)
})

test_that("panels a layer does not reach still train, as in ggplot2", {
  # ScaleDiscretePosition$train has no empty-input guard, so empty slices
  # set range$factor and can leave character(0) or c(Inf, -Inf) ranges.
  df <- data.frame(x = c("a", "b", "c"), y = 1:3, g = c("p", "q", "r"))
  one <- data.frame(x = factor("z"), y = 1, g = "q")
  num <- data.frame(x = 2.5, y = 1, g = "r")
  p <- ggplot(df, aes(x, y)) + geom_point() + facet_wrap(~g, scales = "free_x")
  expect_discrete_ranges_equal(p + geom_point(data = one))
  expect_discrete_ranges_equal(p + geom_point(data = num))
  expect_discrete_ranges_equal(ggplot(one, aes(x, y)) + geom_point() + geom_point(data = df) +
    facet_wrap(~g, scales = "free_x"))
})

test_that("continuous values on a discrete scale train range_c as in ggplot2", {
  df <- data.frame(x = c("a", "b", "c"), y = 1:3, g = c("p", "p", "q"))
  p <- ggplot(df, aes(x, y)) + geom_point()
  expect_discrete_ranges_equal(p + annotate("point", x = 4.5, y = 2))
  expect_discrete_ranges_equal(p + annotate("point", x = c(2L, NA, 7L), y = 2))
  expect_discrete_ranges_equal(p + annotate("point", x = c(NA, Inf, -Inf, 0.25, NaN, 0.25), y = 2))
  expect_discrete_ranges_equal(p + annotate("point", x = c(NA_real_, Inf), y = 2))
  expect_discrete_ranges_equal(p + annotate("rect", xmin = -1, xmax = 0.5, ymin = 1, ymax = 2))
  expect_discrete_ranges_equal(p + annotate("point", x = 4.5, y = 2) + facet_wrap(~g, scales = "free_x"))
  # Stats return mapped_discrete positions, trained in the second pass.
  expect_discrete_ranges_equal(ggplot(mpg, aes(drv, hwy)) + geom_violin() + facet_wrap(~year))
  expect_discrete_ranges_equal(ggplot(mpg, aes(class)) + geom_bar() + coord_flip())
})

test_that("single-row and empty data match ggplot2", {
  expect_discrete_ranges_equal(ggplot(data.frame(x = "a", y = 1), aes(x, y)) + geom_point())
  expect_discrete_ranges_equal(ggplot(data.frame(x = factor(NA), y = 1), aes(x, y)) + geom_point())
  empty <- data.frame(x = character(), y = numeric())
  expect_discrete_ranges_equal(ggplot(empty, aes(x, y)) + geom_point())
  expect_discrete_ranges_equal(ggplot(empty, aes(x, y)) + geom_point() + geom_point(data = data.frame(x = "b", y = 2)))
})

test_that("unsupported discrete input and scales fall back to ggplot2", {
  falls_back <- function(p) {
    cov <- alot_coverage(p)
    cov$path[cov$step == "scale_train" & cov$class == "ScaleDiscretePosition"][1] == "ggplot2"
  }
  df <- data.frame(y = 1:3)
  df$x <- structure(factor(c("a", "b", "a")), class = c("my_factor", "factor"))
  p <- ggplot(df, aes(x, y)) + geom_point()
  expect_true(falls_back(p))
  expect_build_equal(p)

  # A scale instance overriding train() keeps its class but falls back.
  custom <- ggproto(NULL, scale_x_discrete(), train = function(self, x) {
    ggproto_parent(ScaleDiscretePosition, self)$train(x)
  })
  p <- ggplot(mpg, aes(class, hwy)) + geom_point() + custom
  expect_true(falls_back(p))
  expect_build_equal(p)

  # A subclass falls back.
  sub <- ggproto("ScaleDiscretePositionSub", scale_x_discrete())
  p <- ggplot(mpg, aes(class, hwy)) + geom_point() + sub
  cov <- alot_coverage(p)
  expect_true(all(cov$path[cov$class == "ScaleDiscretePositionSub"] == "ggplot2"))
  expect_build_equal(p)
})
