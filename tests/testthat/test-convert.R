library(ggplot2)

roundtrip <- function(df, copy) rebuild_frame(rs_convert_roundtrip(df, copy), df)

# One column of each type ggplot2 layer data uses.
all_types <- function(n = 5) {
  i <- seq_len(n)
  df <- data.frame(
    dbl = c(1.5, NA, NaN, Inf, -Inf)[(i - 1) %% 5 + 1],
    int = c(1L, NA, -3L, 4L, .Machine$integer.max)[(i - 1) %% 5 + 1],
    lgl = c(TRUE, NA, FALSE, TRUE, FALSE)[(i - 1) %% 5 + 1],
    chr = c("a", NA, "é", "", "b")[(i - 1) %% 5 + 1],
    fct = factor(c("b", "a", NA, "c", "a")[(i - 1) %% 5 + 1], levels = c("c", "b", "a")),
    ord = factor(c("lo", "hi", "lo", NA, "hi")[(i - 1) %% 5 + 1], levels = c("lo", "hi"), ordered = TRUE),
    date = as.Date("2024-01-01") + c(0, NA, 3, 400, -10)[(i - 1) %% 5 + 1],
    time = as.POSIXct("2024-01-01 12:00", tz = "UTC") + c(0, 1.5, NA, 3600, -1)[(i - 1) %% 5 + 1],
    PANEL = factor(rep(1L, n)),
    group = rep(-1L, n),
    stringsAsFactors = FALSE
  )
  df$x <- ggplot2:::mapped_discrete(c(1, 2, NA, 3, 1)[(i - 1) %% 5 + 1])
  df$outliers <- lapply(i, function(j) seq_len(j - 1))
  df
}

test_that("every column type round-trips unchanged", {
  for (n in c(5, 1, 0)) {
    df <- all_types(n)
    expect_identical(roundtrip(df, copy = FALSE), df)
    expect_identical(roundtrip(df, copy = TRUE), df)
  }
})

test_that("columns are read as the expected views, with NA as missing", {
  info <- rs_convert_inspect(all_types())
  expect_identical(info$kind, c(
    "double", "integer", "logical", "character", "factor", "factor",
    "double", "double", "factor", "integer", "double", "other"
  ))
  # dbl counts NA and NaN; date and time their NA; x its NA.
  expect_identical(info$n_na, c(2L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 0L, 0L, 1L, 0L))
  expect_identical(rs_convert_inspect(data.frame(d = as.Date(c(1L, NA))))$kind, "integer")
})

test_that("ggplot2 layer data round-trips unchanged", {
  plots <- list(
    ggplot(mpg, aes(class, hwy)) + geom_boxplot(),
    ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point() + facet_wrap(~year),
    ggplot(economics, aes(date, unemploy)) + geom_line(),
    ggplot(diamonds[1:200, ], aes(cut, fill = color)) + geom_bar()
  )
  for (p in plots) {
    df <- layer_data(p)
    expect_identical(roundtrip(df, copy = FALSE), df)
    expect_identical(roundtrip(df, copy = TRUE), df)
  }
})

test_that("pass-through columns are not copied", {
  df <- all_types()
  out <- rs_convert_roundtrip(df, FALSE)
  for (nm in names(df)) {
    expect_identical(rlang::obj_address(out[[nm]]), rlang::obj_address(df[[nm]]))
  }
  copied <- rs_convert_roundtrip(df, TRUE)
  expect_false(rlang::obj_address(copied$dbl) == rlang::obj_address(df$dbl))
})

test_that("rebuild_frame orders columns by the template, then appends new ones", {
  template <- data.frame(a = 1:2, b = c("x", "y"), c = c(0.5, 1))
  out <- rebuild_frame(list(new = c(TRUE, FALSE), c = c(2, 3), a = 3:4), template)
  expect_identical(names(out), c("a", "c", "new"))
  expect_identical(out$a, 3:4)

  # Frame attributes come from the template; row count from the columns.
  attr(template, "extra") <- "kept"
  out <- rebuild_frame(list(a = 1:3), template)
  expect_identical(attr(out, "extra"), "kept")
  expect_identical(nrow(out), 3L)
  expect_s3_class(out, "data.frame")
})
