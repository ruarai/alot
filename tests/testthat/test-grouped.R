library(ggplot2)

# A trivial stat and position whose compute methods have Rust twins
# (rs_grouped_test_stat / rs_grouped_test_position in alot-r/src/lib.rs),
# registered for these tests only.
StatAlotTest <- ggproto("StatAlotTest", Stat,
  required_aes = c("x", "y"),
  compute_group = function(data, scales, cols = c("x", "y")) {
    rlang::inject(data_frame0(!!!lapply(data[cols], vctrs::vec_data), n = nrow(data)))
  }
)
data_frame0 <- gg_data_frame0

PositionAlotTest <- ggproto("PositionAlotTest", Position,
  compute_panel = function(data, params, scales) {
    data$y <- data$y + nrow(data)
    data
  }
)

kernel_stat_test <- function(stat, data, params, layout) {
  stat_compute_grouped(stat, data, params, function(data, params) {
    rs_grouped_test_stat(data, params$cols %||% c("x", "y"))
  })
}
kernel_position_test <- function(position, data, params, layout) {
  position_compute_grouped(data, function(data) rs_grouped_test_position(data, "y"))
}
register_kernel("stat", "StatAlotTest", kernel_stat_test)
register_kernel("position", "PositionAlotTest", kernel_position_test)
withr::defer(
  rm(list = c("stat:StatAlotTest", "position:PositionAlotTest"), envir = kernels),
  teardown_env()
)

stat_test <- function(..., cols = c("x", "y"), position = "identity") {
  # Without x the kernel output does not suit geom_point().
  geom <- if ("x" %in% cols) "point" else "blank"
  layer(stat = StatAlotTest, geom = geom, position = position,
        params = list(cols = cols, ...))
}

warnings_of <- function(expr) {
  msgs <- character()
  withCallingHandlers(expr, warning = function(w) {
    msgs <<- c(msgs, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  msgs
}

expect_same_warnings <- function(p) {
  expect_identical(warnings_of(alot_build(p)), warnings_of(ggplot_build(p)))
}

uses_rust <- function(p, step) {
  cov <- suppressWarnings(alot_coverage(p))
  any(cov$step == step & cov$path == "rust")
}

# Shuffled rows over 3 panels, several groups, and a column constant per group.
set.seed(42)
df <- data.frame(
  x = runif(60),
  y = rnorm(60),
  f = sample(c("b", "a", "c"), 60, TRUE),
  g = sample(c("u", "v"), 60, TRUE)
)
df$k <- factor(toupper(df$g), levels = c("V", "U"))

test_that("group index orders rows as dapply() and split() do", {
  data <- data.frame(
    row = 1:9,
    PANEL = factor(c(3, 1, 3, 1, 1, 3, 3, 1, 3), levels = 1:4),
    group = c(2L, -1L, -1L, 7L, -1L, 2L, 1000000L, 7L, -1L)
  )
  expected <- gg_dapply(data, "PANEL", function(d) {
    gg_data_frame0(row = unlist(split(d$row, d$group), use.names = FALSE))
  })$row
  ix <- rs_group_index(data, TRUE)
  expect_identical(ix$order, expected)
  expect_identical(ix$offsets, c(0L, 2L, 4L, 6L, 8L, 9L))
  expect_identical(ix$panel, c(1L, 1L, 2L, 2L, 2L))

  # Panels only, as Position$compute_layer splits.
  expected <- gg_dapply(data, "PANEL", function(d) gg_data_frame0(row = d$row))$row
  expect_identical(rs_group_index(data, FALSE)$order, expected)

  # Sparse group ids take the hashed path.
  data$group <- c(.Machine$integer.max, -.Machine$integer.max, 0L, 5L, 5L, 0L, 1L, 2L, 3L)
  expected <- gg_dapply(data, "PANEL", function(d) {
    gg_data_frame0(row = unlist(split(d$row, d$group), use.names = FALSE))
  })$row
  expect_identical(rs_group_index(data, TRUE)$order, expected)

  expect_null(rs_group_index(transform(data, group = replace(group, 2, NA)), TRUE))
  expect_null(rs_group_index(transform(data, PANEL = as.integer(PANEL)), TRUE))
  expect_null(rs_group_index(transform(data, group = as.double(group)), TRUE))
})

test_that("the driver reproduces Stat$compute_layer across panels and groups", {
  plots <- list(
    ggplot(df, aes(x, y, colour = g, shape = k)) + stat_test() + facet_wrap(~f),
    # No discrete variables: group = -1 everywhere.
    ggplot(df, aes(x, y)) + stat_test() + facet_grid(f ~ .),
    ggplot(df, aes(x, y, colour = g)) + stat_test(),
    # Discrete x (mapped_discrete) is carried; the kernel returns y and n only.
    ggplot(df, aes(f, y, fill = k)) + stat_test(cols = "y"),
    ggplot(df[1, ], aes(x, y)) + stat_test(),
    ggplot(df, aes(x, y, colour = g, group = interaction(g, f))) + stat_test() + facet_wrap(~f)
  )
  for (p in plots) {
    expect_true(uses_rust(p, "stat"))
    expect_build_equal(p)
  }
})

test_that("compute_layer output matches directly, including dropped columns", {
  layout <- ggplot_build(ggplot(df, aes(x, y)) + facet_wrap(~f))@layout
  data <- data.frame(
    x = c(1, 2, 3, 4, 5, 6),
    y = c(6, 5, 4, 3, 2, 1),
    PANEL = factor(c(2, 1, 2, 1, 2, 1), levels = 1:3),
    group = c(1L, 1L, 1L, 2L, 2L, 2L),
    colour = c("red", "red", "red", "blue", "blue", "blue"),
    # Constant within panel 1's groups, not within panel 2's.
    size = c(1, 2, 3, 2, 1, 2),
    alpha = c(NA, 0.5, NA, 0.5, 0.5, 0.5),
    stringsAsFactors = FALSE
  )
  params <- list(na.rm = FALSE, cols = "y")
  for (dropped_aes in list(character(), c("x", "size"))) {
    stat <- ggproto(NULL, StatAlotTest, dropped_aes = dropped_aes)
    expected <- warnings_of(want <- stat$compute_layer(data, params, layout))
    got_warnings <- warnings_of(got <- kernel_stat_test(stat, data, params, layout))
    expect_equal(got, want)
    expect_identical(got_warnings, expected)
  }
  expect_true(anyNA(got$size))
})

test_that("warnings match ggplot2's", {
  df2 <- df
  df2$y[c(3, 10)] <- c(NA, Inf)
  # remove_missing() and the dropped-aesthetics warning (x varies by group).
  p <- ggplot(df2, aes(x, y, colour = g)) + stat_test(cols = "y") + facet_wrap(~f)
  expect_true(uses_rust(p, "stat"))
  expect_same_warnings(p)
  suppressWarnings(expect_build_equal(p))
  expect_same_warnings(ggplot(df2, aes(x, y)) + stat_test(na.rm = TRUE))
})

test_that("unsupported input falls back to ggplot2", {
  falls_back <- function(p) {
    expect_false(uses_rust(p, "stat"))
    suppressWarnings(expect_build_equal(p))
  }
  # A character column: the test kernel declines.
  falls_back(ggplot(df, aes(x, y, colour = g)) + stat_test(cols = c("y", "colour")))
  # Everything removed as missing.
  falls_back(ggplot(transform(df, y = NA_real_), aes(x, y)) + stat_test())

  layout <- ggplot_build(ggplot(df, aes(x, y)))@layout
  data <- data.frame(x = c(1, 2), y = c(3, 4), PANEL = factor(c(1, 1)), group = c(1L, 1L))
  params <- list(na.rm = FALSE)
  run <- function(data) kernel_stat_test(StatAlotTest, data, params, layout)
  expect_false(is.null(run(data)))
  expect_null(run(transform(data, group = c(1L, NA))))
  expect_null(run(transform(data, group = c(1, 1))))
  data$when <- as.POSIXlt(c("2024-01-01", "2024-01-02"), tz = "UTC")
  expect_null(run(data))
  data$when <- NULL
  data$l <- list(1, 2)
  expect_null(run(data))
  data$l <- NULL
  # Same text in two encodings: vctrs would compare it translated.
  data$label <- c(enc2utf8("caf\u00e9"), iconv("caf\u00e9", "UTF-8", "latin1"))
  expect_null(run(data))
  data$label <- c(enc2utf8("caf\u00e9"), "cafe")
  expect_false(is.null(suppressWarnings(run(data))))
})

test_that("the driver reproduces Position$compute_layer", {
  pos <- ggproto(NULL, PositionAlotTest)
  plots <- list(
    ggplot(df, aes(x, y, colour = g)) + geom_point(position = pos) + facet_wrap(~f),
    ggplot(df, aes(f, y)) + geom_point(position = pos),
    ggplot(df, aes(x, y, colour = g)) + stat_test(position = pos) + facet_grid(g ~ f)
  )
  for (p in plots) {
    expect_true(uses_rust(p, "position"))
    expect_build_equal(p)
  }
})
