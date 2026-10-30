library(ggplot2)

# Panel layout and assignment for FacetWrap and FacetGrid (T5.1). Besides
# expect_build_equal(), check the layer data is identical, so a changed
# PANEL type or level set shows.
expect_facet_equal <- function(p) {
  set.seed(1)
  a <- suppressWarnings(alot_build(p))
  set.seed(1)
  b <- suppressWarnings(ggplot2::ggplot_build(p))
  expect_identical(a@data, b@data)
  suppressWarnings(expect_build_equal(p))
}

facet_paths <- function(p, step = "facet_map_data") {
  cov <- suppressWarnings(alot_coverage(p))
  cov$path[cov$step %in% step]
}
in_rust <- function(p, step = c("facet_compute_layout", "facet_map_data")) {
  paths <- facet_paths(p, step)
  length(paths) > 0 && all(paths == "rust")
}
falls_back <- function(p, step = "facet_map_data") {
  paths <- facet_paths(p, step)
  length(paths) > 0 && all(paths == "ggplot2")
}

set.seed(42)
n <- 120
df <- data.frame(
  x = seq_len(n), y = stats::rnorm(n),
  chr = sample(c(letters[1:4], NA), n, TRUE),
  fct = factor(sample(c("p", "q", "r", NA), n, TRUE), levels = c("r", "q", "p", "unused")),
  ord = factor(sample(c("lo", "mid", "hi"), n, TRUE), levels = c("lo", "mid", "hi"), ordered = TRUE),
  int = sample(1:3, n, TRUE),
  dbl = sample(c(0.5, 1.25, NA, 0.3, 0.1 + 0.2), n, TRUE),
  lgl = sample(c(TRUE, FALSE, NA), n, TRUE),
  date = as.Date("2020-01-01") + sample(0:2, n, TRUE)
)
# A factor with an explicit NA level, some rows coded NA as well.
df$fna <- structure(c(NA, NA, sample(c(1L, 2L, 3L, NA), n - 2, TRUE)),
                    levels = c("u", "v", NA), class = "factor")
point <- ggplot(df, aes(x, y)) + geom_point()

test_that("facet_wrap assigns panels in Rust for every column type", {
  plots <- list(
    point + facet_wrap(~chr),
    point + facet_wrap(~fct),
    point + facet_wrap(~fct, drop = FALSE),
    point + facet_wrap(~ord),
    point + facet_wrap(~fna),
    point + geom_point(data = data.frame(x = 1, y = 1, fna = "u")) + facet_wrap(~fna),
    point + facet_wrap(~int),
    point + facet_wrap(~dbl),
    point + facet_wrap(~lgl),
    point + facet_wrap(~date),
    point + facet_wrap(~ chr + fct),
    point + facet_wrap(vars(int, lgl), dir = "v"),
    point + facet_wrap(vars(big = x > 60)),
    point + facet_wrap(~chr, scales = "free")
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_facet_equal(p)
  }
})

test_that("facet_grid assigns panels in Rust", {
  plots <- list(
    point + facet_grid(chr ~ fct),
    point + facet_grid(. ~ int),
    point + facet_grid(lgl ~ .),
    point + facet_grid(chr + int ~ ord),
    point + facet_grid(fct ~ dbl, drop = FALSE),
    point + facet_grid(chr ~ int, scales = "free", space = "free")
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_facet_equal(p)
  }
})

test_that("layers with different facet values and missing facet variables match ggplot2", {
  other <- data.frame(x = c(1, 2, 3), y = c(0, 1, 2), chr = c("b", "z", "b"))
  no_facet <- data.frame(x = c(10, 20), y = c(1, 2))
  plots <- list(
    # A layer without NA facet values next to one with them, and a value
    # only that layer has.
    point + geom_point(data = other) + facet_wrap(~chr),
    # A layer missing the facet variable is repeated across panels.
    point + geom_point(data = no_facet) + facet_wrap(~chr),
    point + geom_hline(yintercept = 0) + facet_grid(chr ~ int),
    # Missing one of two grid variables.
    point + geom_point(data = other) + facet_grid(chr ~ int),
    point + geom_point(data = other[1, ]) + facet_wrap(~chr)
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_facet_equal(p)
  }
})

test_that("layer layouts match ggplot2", {
  plots <- list(
    point + geom_point(data = df[1:5, ], colour = "red", layout = "fixed_rows") + facet_grid(chr ~ int),
    point + geom_point(data = df[1:5, ], colour = "red", layout = "fixed_cols") + facet_grid(chr ~ int),
    point + geom_point(colour = "red", layout = 2) + facet_wrap(~int),
    point + geom_point(colour = "red", layout = c(1, 3)) + facet_grid(chr ~ int)
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_facet_equal(p)
  }
})

test_that("a single row, integer and double data match ggplot2", {
  one <- data.frame(x = 1L, y = 2L, f = "a")
  p <- ggplot(one, aes(x, y)) + geom_point() + facet_wrap(~f)
  expect_true(in_rust(p))
  expect_facet_equal(p)
  p <- ggplot(one, aes(x, y)) + geom_point() + facet_grid(f ~ .)
  expect_true(in_rust(p))
  expect_facet_equal(p)
})

test_that("a large key space uses the hashed join and matches ggplot2", {
  # 260 x 260 possible combinations exceed the dense table.
  big <- data.frame(x = 1:260, y = 1:260, a = sprintf("a%03d", 1:260), b = sprintf("b%03d", 260:1))
  p <- ggplot(big, aes(x, y)) + geom_point() + facet_wrap(~ a + b)
  expect_true(in_rust(p))
  set.seed(1)
  a <- alot_build(p)
  b <- ggplot2::ggplot_build(p)
  expect_identical(a@data, b@data)
})

test_that("compute_layout combines facet values across layers as ggplot2 does", {
  other <- data.frame(x = 1:4, y = 1:4, chr = c("z", "a", "z", NA), int = c(9L, 1L, 9L, 1L))
  only_chr <- data.frame(x = 1:2, y = 1:2, chr = c("y", "a"))
  plots <- list(
    point + geom_point(data = other) + facet_wrap(~ chr + int),
    point + geom_point(data = other) + facet_wrap(~fct, drop = FALSE),
    point + geom_point(data = other) + facet_grid(chr ~ int, drop = FALSE),
    # A layer with only some of the variables adds its combinations.
    point + geom_point(data = only_chr) + facet_wrap(~ chr + int),
    point + geom_point(data = only_chr) + facet_wrap(~ chr + int, drop = FALSE),
    point + geom_point(data = only_chr) + facet_grid(chr + int ~ lgl),
    point + facet_grid(chr ~ int, as.table = FALSE),
    point + facet_wrap(~chr, as.table = FALSE, dir = "v", ncol = 2)
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_facet_equal(p)
  }

  # Grid margins: the layout runs in Rust, panel assignment falls back.
  p <- point + facet_grid(chr ~ int, margins = TRUE)
  expect_true(in_rust(p, "facet_compute_layout"))
  expect_facet_equal(p)
})

test_that("compute_layout keeps values that only vctrs considers equal apart correctly", {
  # Rust compares bits and string pointers; R's unique0() then merges what
  # vctrs considers equal: 0 and -0, and one string in two encodings.
  e_utf8 <- "caf\u00e9"
  e_latin1 <- iconv(e_utf8, "UTF-8", "latin1")
  expect_false(identical(Encoding(e_utf8), Encoding(e_latin1)))
  odd <- data.frame(
    x = 1:6, y = 1:6,
    dbl = c(0, -0, NaN, NA, 1, 0),
    chr = c(e_utf8, e_latin1, "a", e_latin1, NA, "a")
  )
  for (p in list(
    ggplot(odd, aes(x, y)) + geom_point() + facet_wrap(~dbl),
    ggplot(odd, aes(x, y)) + geom_point() + facet_wrap(~chr),
    ggplot(odd, aes(x, y)) + geom_point() + facet_grid(chr ~ dbl)
  )) {
    expect_true(in_rust(p, "facet_compute_layout"))
    set.seed(1)
    a <- alot_build(p)
    b <- ggplot2::ggplot_build(p)
    expect_identical(a@layout$layout, b@layout$layout)
    expect_identical(a@data, b@data)
  }
})

test_that("unsupported compute_layout cases fall back to ggplot2", {
  # A column type without a Rust key.
  cpx <- data.frame(x = 1:4, y = 1:4, z = complex(real = c(1, 2, 1, 2)))
  p <- ggplot(cpx, aes(x, y)) + geom_point() + facet_wrap(~z)
  expect_true(falls_back(p, "facet_compute_layout"))
  expect_facet_equal(p)

  # An overridden compute_layout.
  wrap <- facet_wrap(~chr)
  p <- point
  p@facet <- ggproto(NULL, wrap, compute_layout = function(self, data, params) {
    ggproto_parent(FacetWrap, self)$compute_layout(data, params)
  })
  expect_true(falls_back(p, "facet_compute_layout"))
  expect_facet_equal(p)

  # Errors come from ggplot2 itself.
  build_error <- function(build, p) tryCatch({ build(p); NULL }, error = conditionMessage)
  for (p in list(
    point + facet_grid(chr ~ chr),
    point + facet_wrap(~nope),
    ggplot(df[0, ], aes(x, y)) + geom_point() + facet_wrap(~chr)
  )) {
    expect_identical(build_error(alot_build, p), build_error(ggplot2::ggplot_build, p))
  }
})

test_that("unsupported cases fall back to ggplot2", {
  # Margins.
  p <- point + facet_grid(chr ~ int, margins = TRUE)
  expect_true(falls_back(p))
  expect_facet_equal(p)
  p <- point + facet_grid(chr + lgl ~ int, margins = "chr")
  expect_true(falls_back(p))
  expect_facet_equal(p)

  # A fixed layer is repeated in every panel; nothing to join.
  p <- ggplot(df, aes(x, y)) + geom_point(layout = "fixed") + facet_wrap(~chr)
  expect_true(falls_back(p))
  expect_facet_equal(p)

  # Empty layer data.
  p <- point + geom_point(data = df[0, ]) + facet_wrap(~chr)
  expect_identical(facet_paths(p), c("rust", "ggplot2"))
  expect_facet_equal(p)

  # A facet subclass, and a FacetWrap whose map_data is overridden.
  MyFacet <- ggproto("MyFacet", FacetWrap)
  p <- point + facet_wrap(~chr)
  p@facet <- ggproto(NULL, MyFacet, params = p@facet$params)
  expect_true(falls_back(p))
  expect_facet_equal(p)
  wrap <- facet_wrap(~chr)
  p <- point
  p@facet <- ggproto(NULL, wrap, map_data = function(data, layout, params) {
    utils::getFromNamespace("map_facet_data", "ggplot2")(data, layout, params)
  })
  expect_identical(class(p@facet)[1], "FacetWrap")
  expect_true(falls_back(p))
  expect_facet_equal(p)

  # facet_null has no kernel.
  expect_true(falls_back(point))
})

test_that("a layout with an overridden setup falls back whole", {
  p <- point + facet_wrap(~chr)
  p@layout <- ggproto(NULL, Layout, setup = function(self, data, plot_data, plot_env) {
    ggproto_parent(Layout, self)$setup(data, plot_data, plot_env)
  })
  cov <- alot_coverage(p)
  expect_identical(cov$path[cov$step == "layout_setup"], "ggplot2")
  expect_length(facet_paths(p), 0)
  expect_facet_equal(p)
})
