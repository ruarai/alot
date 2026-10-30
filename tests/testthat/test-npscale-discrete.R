library(ggplot2)

# Discrete non-position training and mapping (T2.4). Besides
# expect_build_equal(), check the layer data is identical, so a changed
# colour, shape or type shows.
expect_np_equal <- function(p) {
  set.seed(1)
  a <- suppressWarnings(alot_build(p))
  set.seed(1)
  b <- suppressWarnings(ggplot2::ggplot_build(p))
  expect_identical(a@data, b@data)
  suppressWarnings(expect_build_equal(p))
}

np_paths <- function(p, step) {
  cov <- suppressWarnings(alot_coverage(p))
  cov$path[cov$step == step & cov$class == "ScaleDiscrete"]
}
in_rust <- function(p, step = c("np_train", "np_map")) {
  paths <- unlist(lapply(step, np_paths, p = p))
  length(paths) > 0 && all(paths == "rust")
}
falls_back <- function(p, step = "np_map") {
  paths <- np_paths(p, step)
  length(paths) > 0 && all(paths == "ggplot2")
}

set.seed(42)
n <- 200
df <- data.frame(
  x = seq_len(n), y = stats::rnorm(n),
  chr = sample(c(letters[1:6], NA), n, TRUE),
  fct = factor(sample(c("p", "q", "r", NA), n, TRUE), levels = c("r", "q", "p", "unused")),
  ord = factor(sample(c("lo", "mid", "hi"), n, TRUE), levels = c("lo", "mid", "hi"), ordered = TRUE),
  lgl = sample(c(TRUE, FALSE, NA), n, TRUE),
  panel = rep(c("A", "B"), length.out = n)
)

test_that("every discrete scale family runs in Rust and matches ggplot2", {
  point <- function(...) ggplot(df, aes(x, y, ...)) + geom_point()
  plots <- list(
    point(colour = chr),
    point(colour = fct) + scale_colour_hue(l = 40, direction = -1),
    point(colour = ord),
    point(colour = chr) + scale_colour_brewer(palette = "Set2"),
    point(fill = fct) + scale_fill_brewer(palette = "Set1", direction = -1),
    point(colour = chr) + scale_colour_grey(),
    point(colour = fct) + scale_colour_viridis_d(option = "C"),
    point(colour = chr) + scale_colour_manual(values = grDevices::rainbow(6)),
    point(colour = chr) + scale_colour_manual(values = c(f = "red", a = "blue", b = "green", c = "black",
                                                         d = "pink", e = "grey", zz = "white")),
    # Named values missing some data values: those map to na.value.
    point(colour = chr) + scale_colour_manual(values = c(a = "red", b = "blue"), na.value = "black"),
    point(colour = chr) + scale_colour_manual(values = c(a = "red", b = "blue", d = "green"), limits = c("b", "a", "c"),
                                              na.value = "grey20"),
    point(shape = fct),
    point(shape = chr) + scale_shape(solid = FALSE),
    point(shape = fct) + scale_shape_manual(values = c(3L, 8L, 15L)),
    point(shape = chr) + scale_shape_manual(values = c(1, 2, 5, 6, 7, 8)),
    point(shape = fct) + scale_shape_manual(values = c("circle", "square", "triangle")),
    point(size = fct) + suppressWarnings(scale_size_discrete()),
    point(alpha = chr) + suppressWarnings(scale_alpha_discrete()),
    ggplot(df, aes(x, y, linetype = chr)) + geom_line(),
    ggplot(df, aes(x, y, linetype = fct)) + geom_line() +
      scale_linetype_manual(values = c("dotted", "22", "solid")),
    point(colour = lgl),
    point(colour = chr) + scale_colour_discrete(),
    # One scale for two aesthetics.
    ggplot(df, aes(x, y, colour = chr, fill = chr)) + geom_point(shape = 21) +
      scale_colour_hue(aesthetics = c("colour", "fill"))
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("NA handling, drop, limits and na.translate match ggplot2", {
  base <- ggplot(df, aes(x, y, colour = fct)) + geom_point()
  plots <- list(
    base + scale_colour_hue(drop = FALSE),
    base + scale_colour_hue(na.translate = FALSE),
    base + scale_colour_hue(na.value = "orange"),
    base + scale_colour_hue(limits = c("q", "zz")),
    base + scale_colour_hue(limits = c("p", NA, "q")),
    base + scale_colour_hue(na.value = NA),
    ggplot(df, aes(x, y, shape = chr)) + geom_point() + scale_shape(na.translate = FALSE),
    ggplot(df, aes(x, y, shape = chr)) + geom_point() + scale_shape_manual(values = 1:6, na.value = 4),
    ggplot(df, aes(x, y, colour = lgl)) + geom_point() + scale_colour_hue(na.translate = FALSE),
    ggplot(df, aes(x, y, colour = chr)) + geom_point() +
      scale_colour_manual(values = c(a = "red"), na.translate = FALSE),
    # No limits left at all: every row gets na.value.
    ggplot(df, aes(x, y, colour = fct)) + geom_point() + scale_colour_hue(limits = c(NA_character_)),
    # All-NA columns.
    ggplot(transform(df, chr = NA_character_), aes(x, y, colour = chr)) + geom_point(),
    ggplot(transform(df, lgl = NA), aes(x, y, colour = lgl)) + geom_point(),
    ggplot(transform(df, fct = factor(NA, levels = "a")), aes(x, y, colour = fct)) + geom_point()
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("single rows, facets, layers and after_scale match ggplot2", {
  plots <- list(
    ggplot(df[1, ], aes(x, y, colour = chr)) + geom_point(),
    ggplot(df[3, ], aes(x, y, shape = fct)) + geom_point(),
    ggplot(df, aes(x, y, colour = chr)) + geom_point() + facet_wrap(~panel),
    ggplot(df, aes(x, y, colour = fct)) + geom_point() + facet_grid(panel ~ ., scales = "free"),
    ggplot(df, aes(x, y, colour = chr)) + geom_point() + geom_line(aes(colour = fct)) +
      scale_colour_hue(),
    ggplot(df, aes(fct, fill = chr)) + geom_bar(),
    ggplot(df, aes(chr, fill = after_stat(as.character(count)))) + geom_bar(),
    ggplot(df, aes(x, y, fill = chr)) + geom_point(shape = 21, aes(colour = after_scale(fill))),
    # Discrete scales alongside a continuous colour scale.
    ggplot(df, aes(x, y, colour = y, shape = chr)) + geom_point()
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("strings that differ only in encoding map as in ggplot2", {
  utf8 <- "café"
  latin1 <- iconv(utf8, "UTF-8", "latin1")
  expect_false(identical(Encoding(utf8), Encoding(latin1)))
  d <- data.frame(x = 1:6, y = 1:6)
  d$g <- c(utf8, latin1, "tea", latin1, utf8, NA)
  plots <- list(
    ggplot(d, aes(x, y, colour = g)) + geom_point(),
    ggplot(d, aes(x, y, colour = g)) + geom_point() + scale_colour_manual(values = stats::setNames(
      c("red", "blue"), c(latin1, "tea")
    ))
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("palette errors and warnings match ggplot2", {
  p <- ggplot(df, aes(x, y, colour = chr)) + geom_point() + scale_colour_manual(values = c("red", "blue"))
  expect_identical(
    tryCatch(alot_build(p), error = conditionMessage),
    tryCatch(ggplot_build(p), error = conditionMessage)
  )
  # RColorBrewer warns once per palette() call.
  big <- data.frame(x = 1:12, y = 1:12, g = letters[1:12])
  p <- ggplot(big, aes(x, y, colour = g, fill = g)) + geom_point(shape = 21) +
    scale_colour_brewer(aesthetics = c("colour", "fill"))
  warnings_of <- function(f) {
    msgs <- character()
    withCallingHandlers(f(p), warning = function(w) {
      msgs <<- c(msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
    msgs
  }
  expect_identical(warnings_of(alot_build), warnings_of(ggplot_build))
  expect_true(in_rust(p))
  expect_np_equal(p)
})

test_that("integer and double palette values keep their type", {
  base <- ggplot(df, aes(x, y, shape = fct)) + geom_point()
  int <- alot_build(base + scale_shape_manual(values = c(1L, 2L, 3L)))@data[[1]]$shape
  dbl <- alot_build(base + scale_shape_manual(values = c(1, 2, 3)))@data[[1]]$shape
  chr <- alot_build(base + scale_shape_manual(values = c("a", "b", "c")))@data[[1]]$shape
  expect_type(int, "integer")
  expect_type(dbl, "double")
  expect_type(chr, "character")
  expect_identical(typeof(alot_build(base)@data[[1]]$shape), typeof(ggplot_build(base)@data[[1]]$shape))
})

test_that("unsupported scales, inputs and results fall back to ggplot2", {
  # An instance overriding map, train or map_df.
  s <- scale_colour_hue()
  s$map <- function(self, x, limits = self$get_limits()) rep("red", length(x))
  p <- ggplot(df, aes(x, y, colour = chr)) + geom_point() + s
  expect_true(falls_back(p))
  expect_true(in_rust(p, "np_train"))
  expect_np_equal(p)

  s <- scale_colour_hue()
  s$train <- function(self, x) self$range$train(x, drop = FALSE)
  p <- ggplot(df, aes(x, y, colour = fct)) + geom_point() + s
  expect_true(falls_back(p, "np_train"))
  expect_true(in_rust(p, "np_map"))
  expect_np_equal(p)

  s <- scale_colour_hue()
  s$map_df <- function(self, df, i = NULL) list(colour = rep("red", nrow(df)))
  p <- ggplot(df, aes(x, y, colour = chr)) + geom_point() + s
  expect_true(falls_back(p))
  expect_np_equal(p)

  # Subclasses: a new class or an identity scale.
  sub <- ggproto("ScaleDiscreteCustom", scale_colour_hue())
  p <- ggplot(df, aes(x, y, colour = chr)) + geom_point() + sub
  cov <- alot_coverage(p)
  expect_true(all(cov$path[cov$class == "ScaleDiscreteCustom" & cov$step %in% c("np_train", "np_map")] ==
                    "ggplot2"))
  expect_np_equal(p)
  p <- ggplot(df, aes(x, y, colour = chr)) + geom_point() + scale_colour_identity()
  cov <- alot_coverage(p)
  expect_true(all(cov$path[cov$class == "ScaleDiscreteIdentity"] == "ggplot2"))

  # A palette returning a list (patterns).
  p <- ggplot(df, aes(x, y, fill = fct)) + geom_col() +
    scale_fill_manual(values = list("red", grid::linearGradient(), "blue"))
  expect_true(in_rust(p, "np_train"))
  expect_true(falls_back(p))
  expect_np_equal(p)

  # A palette whose names() survive into the table (named na.value).
  p <- ggplot(df, aes(x, y, colour = fct)) + geom_point() + scale_colour_hue(na.value = c(nm = "black"))
  expect_true(falls_back(p))
  expect_np_equal(p)

  # Input with extra attributes.
  d <- df
  d$fct <- structure(d$fct, note = "x")
  p <- ggplot(d, aes(x, y, colour = fct)) + geom_point()
  expect_true(falls_back(p, "np_train"))
  expect_true(falls_back(p))
  expect_np_equal(p)

  # Numeric input on a discrete scale: ggplot2 raises the error.
  p <- ggplot(df, aes(x, y, colour = x)) + geom_point() + scale_colour_hue()
  expect_identical(
    tryCatch(alot_build(p), error = conditionMessage),
    tryCatch(ggplot_build(p), error = conditionMessage)
  )
})

test_that("first-row training and lookup handle every key type", {
  x <- c("b", "a", "b", NA, "a", "c")
  expect_identical(rs_discrete_first_rows(x), c(1L, 2L, 4L, 6L))
  f <- factor(x, levels = c("c", "b", "a", "z"))
  expect_identical(rs_discrete_first_rows(f), c(1L, 2L, 4L, 6L))
  expect_identical(rs_discrete_first_rows(c(TRUE, TRUE, NA, FALSE)), c(1L, 3L, 4L))
  expect_identical(rs_discrete_first_rows(character()), integer())
  expect_null(rs_discrete_first_rows(1:3))
  bad <- structure(c(1L, 5L), levels = c("a", "b"), class = "factor")
  expect_null(rs_discrete_first_rows(bad))

  table <- c("C", "B", "A", "Z", "N")
  expect_identical(rs_lookup_discrete(f, table), c("B", "A", "B", "N", "A", "C"))
  expect_identical(rs_lookup_discrete(c(NA, TRUE, FALSE), c(1.5, 2.5, NA)), c(NA, 2.5, 1.5))
  expect_identical(rs_lookup_discrete(c(2L, 1L, 2L), c(7L, NA)), c(NA, 7L, NA))
  expect_identical(rs_lookup_discrete(c(1L, 1L), c(TRUE, NA)), c(TRUE, TRUE))
  expect_identical(rs_lookup_discrete(integer(), character()), character())
  expect_identical(rs_lookup_discrete(f[0], table), character())
  expect_identical(rs_lookup_discrete(logical(), c(1L, 2L, 3L)), integer())
  # Keys outside the table, tables of the wrong size or type: decline.
  expect_null(rs_lookup_discrete(c(1L, 3L), c("a", "b")))
  expect_null(rs_lookup_discrete(c(1L, NA), c("a", "b")))
  expect_null(rs_lookup_discrete(f, table[-1]))
  expect_null(rs_lookup_discrete(TRUE, c("a", "b")))
  expect_null(rs_lookup_discrete(1L, list("a")))
  expect_null(rs_lookup_discrete(1L, c(a = "x")))
  expect_null(rs_lookup_discrete(1.5, "x"))
})
