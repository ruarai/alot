library(ggplot2)

# Continuous non-position training and colour mapping (T2.3). Besides
# expect_build_equal(), check the layer data is identical: colours are
# strings, so any drift in interpolation or rounding shows as a different
# hex code.
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
  cov$path[cov$step == step & cov$class == "ScaleContinuous"]
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
df <- data.frame(
  x = seq_len(300), y = stats::rnorm(300),
  z = c(stats::rnorm(294), NA, NaN, Inf, -Inf, 0, -0),
  i = c(sample(-5:20, 299, TRUE), NA)
)

test_that("every supported palette runs in Rust and matches ggplot2", {
  base <- ggplot(df, aes(x, y, colour = z)) + geom_point()
  plots <- list(
    base,
    base + scale_colour_continuous(),
    base + scale_colour_gradient(low = "white", high = "darkred"),
    base + scale_colour_gradient2(),
    base + scale_colour_gradient2(midpoint = 1.5, low = "blue", mid = "grey90", high = "red"),
    base + scale_colour_gradientn(colours = grDevices::terrain.colors(10)),
    base + scale_colour_gradientn(colours = c("red", "green", "blue"), values = c(0, 0.2, 1)),
    base + scale_colour_gradientn(colours = c("red", "green", "blue"), values = c(1, 0.1, 0)),
    base + scale_colour_distiller(),
    base + scale_colour_distiller(palette = "RdBu", direction = 1, type = "div"),
    base + scale_colour_viridis_c(),
    base + scale_colour_viridis_c(option = "magma", begin = 0.2, end = 0.9, direction = -1),
    base + scale_colour_fermenter() + scale_colour_viridis_c()
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("translucent palettes keep farver's alpha rules", {
  base <- ggplot(df, aes(x, y, fill = z)) + geom_point(shape = 21)
  plots <- list(
    base + scale_fill_viridis_c(alpha = 0.5),
    base + scale_fill_gradientn(colours = c("#FF000000", "white", "#0000FF80")),
    # Exactly opaque at the low end: several unique values drop the FF.
    base + scale_fill_gradientn(colours = c("red", "#0000FF80")),
    # A single unique value keeps FF (encode_colour()'s length-1 alpha).
    ggplot(data.frame(x = 1:3, y = 1:3, z = 0), aes(x, y, fill = z)) + geom_point(shape = 21) +
      scale_fill_gradientn(colours = c("red", "#0000FF80"), limits = c(0, 1)),
    ggplot(data.frame(x = 1:2, y = 1:2, z = c(0, -0)), aes(x, y, fill = z)) + geom_point(shape = 21) +
      scale_fill_gradientn(colours = c("red", "#0000FF80"), limits = c(0, 1)),
    ggplot(df[1, ], aes(x, y, fill = z)) + geom_point(shape = 21) +
      scale_fill_gradientn(colours = c("red", "#0000FF80"))
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("oob, limits, rescalers and na.value match ggplot2", {
  base <- ggplot(df, aes(x, y, colour = z)) + geom_point()
  plots <- list(
    base + scale_colour_gradient(limits = c(-1, 1)),
    base + scale_colour_gradient(limits = c(-1, 1), oob = scales::squish),
    base + scale_colour_gradient(limits = c(-1, 1), oob = scales::oob_squish_any),
    base + scale_colour_gradient(limits = c(-1, 1), oob = scales::oob_censor_any),
    base + scale_colour_gradient(limits = c(-1, 1), oob = scales::squish_infinite),
    base + scale_colour_gradient(limits = c(-1, 1), oob = scales::oob_keep),
    base + scale_colour_gradient(limits = c(NA, 0.5)),
    base + scale_colour_gradient(limits = c(1, -1)),
    base + scale_colour_gradient(limits = c(2L, 3L)),
    base + scale_colour_gradient(limits = c(1, 1)),
    base + scale_colour_gradient2(limits = c(1, 1)),
    base + scale_colour_gradient2(midpoint = 10),
    base + scale_colour_gradient(na.value = NA),
    base + scale_colour_gradient(na.value = "red"),
    base + scale_colour_gradient(na.value = NA_character_),
    base + scale_colour_gradient(transform = "reverse"),
    # A date colour scale is a ScaleContinuous whose transform makes the
    # data plain numbers before training.
    ggplot(data.frame(x = 1:4, y = 1:4, d = as.Date("2020-01-01") + c(0:2, NA)), aes(x, y, colour = d)) +
      geom_point(),
    ggplot(df, aes(x, y, colour = abs(z) + 0.1)) + geom_point() +
      scale_colour_gradient2(transform = "log10", midpoint = 1)
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
})

test_that("integer, constant, all-NA, empty and single-row data match ggplot2", {
  plots <- list(
    ggplot(df, aes(x, y, colour = i)) + geom_point(),
    ggplot(df, aes(x, y, colour = i)) + geom_point() + scale_colour_gradient2(midpoint = 3L),
    ggplot(df, aes(x, y, colour = 3)) + geom_point(),
    ggplot(df, aes(x, y, colour = NA_real_)) + geom_point(),
    ggplot(df[1, ], aes(x, y, colour = z)) + geom_point(),
    ggplot(df[c(295, 296), ], aes(x, y, colour = z)) + geom_point()
  )
  for (p in plots) {
    expect_true(in_rust(p))
    expect_np_equal(p)
  }
  expect_np_equal(ggplot(df[0, ], aes(x, y, colour = z)) + geom_point())
})

test_that("several layers, panels and aesthetics share the trained scale", {
  p <- ggplot(df, aes(x, y, colour = z)) + geom_point() +
    geom_line(aes(colour = y), data = df[1:50, ]) +
    facet_wrap(~ i %% 3)
  expect_true(in_rust(p))
  expect_np_equal(p)

  p <- ggplot(df, aes(x, y, colour = z, fill = y)) + geom_point(shape = 21) +
    scale_colour_viridis_c(aesthetics = c("colour", "fill"))
  expect_true(in_rust(p))
  expect_np_equal(p)

  # Computed aesthetics: trained and mapped after the stat.
  p <- ggplot(df, aes(y)) + geom_histogram(aes(fill = after_stat(count)), bins = 12)
  expect_true(in_rust(p))
  expect_np_equal(p)
  p <- ggplot(df, aes(x, y)) + geom_bin_2d(bins = 8)
  expect_true(in_rust(p))
  expect_np_equal(p)
})

test_that("colours match farver on a dense grid of rescaled values", {
  # Values on, between and just past the knots of a 7-colour ramp, with
  # alpha, and 1e5 random values: every hex string must be identical.
  knots <- seq(0, 1, length.out = 7)
  grid <- sort(c(knots, knots + 1e-12, knots - 1e-12, stats::runif(1e5), -1e-9, 1 + 1e-9))
  grid_df <- data.frame(x = seq_along(grid), y = 0, z = grid)
  for (pal in list(
    scale_colour_distiller(palette = "Spectral", limits = c(0, 1)),
    scale_colour_viridis_c(alpha = 0.7, limits = c(0, 1)),
    scale_colour_gradientn(colours = c("#00000000", "red", "#FFFF0080"), values = c(0, 0.7, 1),
                           limits = c(0, 1))
  )) {
    p <- ggplot(grid_df, aes(x, y, colour = z)) + geom_point() + pal
    expect_true(in_rust(p))
    expect_identical(alot_build(p)@data[[1]]$colour, ggplot_build(p)@data[[1]]$colour)
  }
})

test_that("mostly distinct and mostly repeated values give the same colours", {
  # Rust colours each row when most of the first 4096 rows are distinct,
  # and each unique value otherwise; both must match upstream's unique().
  set.seed(3)
  n <- 2e4
  big <- data.frame(x = seq_len(n), y = 0, distinct = stats::rnorm(n),
                    repeated = round(stats::rnorm(n), 1),
                    late = c(rep(0.5, 5000), stats::runif(n - 5000)))
  big$repeated[sample(n, 50)] <- NA
  big$distinct[sample(n, 50)] <- NaN
  for (col in c("distinct", "repeated", "late")) {
    for (pal in list(scale_colour_viridis_c(alpha = 0.6), scale_colour_gradient2(midpoint = 0.2))) {
      p <- ggplot(big, aes(x, y, colour = .data[[col]])) + geom_point() + pal
      expect_true(in_rust(p))
      expect_np_equal(p)
    }
  }
})

test_that("unsupported palettes, rescalers, oob and inputs fall back", {
  base <- ggplot(df, aes(x, y, colour = z)) + geom_point()
  plots <- list(
    # A palette that is not pal_gradient_n().
    base + scale_colour_continuous(palette = function(x) ifelse(x > 0.5, "red", "blue")),
    base + scale_colour_gradientn(colours = "red"),
    # `values` with ties would warn inside approxfun().
    base + scale_colour_gradientn(colours = c("red", "green", "blue"), values = c(0, 0.5, 0.5)),
    base + scale_colour_gradient(rescaler = function(x, to = c(0, 1), from = range(x)) {
      scales::rescale(x, to, from)
    }),
    base + scale_colour_gradient(rescaler = scales::rescale_max),
    base + scale_colour_gradient(oob = function(x, range) x),
    # Size has a different palette; training still runs in Rust.
    ggplot(df, aes(x, y, size = z)) + geom_point()
  )
  for (p in plots) {
    expect_true(falls_back(p))
    expect_np_equal(p)
  }
  expect_true(in_rust(plots[[length(plots)]], "np_train"))

  # A na.value vec_assign() cannot cast: the kernel declines and ggplot2
  # raises its error.
  s <- scale_colour_gradient(na.value = 1)
  s$train(c(0, 1))
  expect_null(kernel_np_map_continuous(s, data.frame(colour = c(0, NA))))
  p <- base + scale_colour_gradient(na.value = 1)
  expect_error(alot_build(p), class = "vctrs_error_cast")
  expect_error(ggplot_build(p), class = "vctrs_error_cast")

  # Binned scales have no kernel.
  p <- base + scale_colour_binned()
  expect_true(all(alot_coverage(p)$class != "ScaleContinuous"))
  expect_np_equal(p)
})

test_that("non-numeric input and overriding scales fall back", {
  # Logical colour on a continuous scale.
  p <- ggplot(df, aes(x, y, colour = z > 0)) + geom_point() + scale_colour_gradient()
  expect_true(falls_back(p, "np_train"))
  expect_true(falls_back(p, "np_map"))
  expect_np_equal(p)

  # Classed or attributed numeric input.
  for (x in list(structure(c(1, 2), class = "units"), structure(c(1, 2), extra = TRUE))) {
    d <- data.frame(colour = 1:2)
    d$colour <- x
    s <- scale_colour_gradient()
    if (is.object(x)) expect_null(kernel_np_train_continuous(s, d))
    s$train(c(0, 3))
    expect_null(kernel_np_map_continuous(s, d))
  }

  # A scale whose map, train or rescale is its own.
  own <- function(...) {
    s <- scale_colour_gradient()
    ggproto(NULL, s, ...)
  }
  over_map <- own(map = function(self, x, limits = self$get_limits()) {
    ggproto_parent(ScaleContinuous, self)$map(x, limits)
  })
  over_train <- own(train = function(self, x) ggproto_parent(ScaleContinuous, self)$train(x))
  over_rescale <- own(rescale = function(self, x, limits = self$get_limits(), range = limits) {
    ggproto_parent(ScaleContinuous, self)$rescale(x, limits, range)
  })
  for (s in list(over_map, over_rescale)) {
    p <- ggplot(df, aes(x, y, colour = z)) + geom_point() + s
    expect_true(falls_back(p, "np_map"))
    expect_np_equal(p)
  }
  p <- ggplot(df, aes(x, y, colour = z)) + geom_point() + over_train
  expect_true(falls_back(p, "np_train"))
  expect_np_equal(p)
})
