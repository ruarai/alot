# geom_raster() in the full and hybrid tiers (S1.1, R/render-raster.R):
# GeomRaster$draw_panel()'s colour matrix built in Rust and drawn as ragg's
# drawRaster() draws it with interpolate = FALSE, against ggplot2 on ragg.
# Covers absent and NA cells, reversed and transformed scales,
# coord_fixed(), coord_flip(), facets, cells narrower than a pixel and many
# pixels wide, and the cases that decline.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_raster <- function(p, label, ..., size = list(), tier = "full") {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-raster.R", label, b)
  expect_no_warning(
    suppressMessages(do.call(expect_render_close, c(list(b), size, list(..., tier = tier, label = label, cache_key = key)))),
    class = "alot_render_fallback"
  )
  if (tier == "full") {
    expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
  }
}

set.seed(3)
field <- expand.grid(x = seq(0, 29) * 1.5, y = seq(0, 19) * 0.25)
field$z <- sin(field$x / 5) + cos(field$y * 2) + rnorm(nrow(field), sd = 0.1)
holes <- field[stats::runif(nrow(field)) < 0.7, ]
small <- data.frame(x = rep(c(-1, 1), each = 3), y = rep(-1:1, 2), z = 1:6)

test_that("rasters draw as ggplot2 draws them", {
  check_raster(ggplot(small, aes(x, y, fill = z)) + geom_raster(), "small")
  check_raster(ggplot(small, aes(x, y, fill = z)) + geom_raster() + geom_point(colour = "red"), "with points")
  check_raster(ggplot(field, aes(x, y, fill = z)) + geom_raster(), "field")
  check_raster(ggplot(holes, aes(x, y, fill = z)) + geom_raster(), "absent cells")
  check_raster(ggplot(holes, aes(x, y, fill = z)) + geom_raster() + scale_fill_viridis_c(), "viridis")
  check_raster(ggplot(small, aes(x, y, fill = z)) + geom_raster(hjust = 0, vjust = 1), "hjust and vjust")
  check_raster(ggplot(small, aes(x, y, fill = z)) + geom_raster() + xlim(-2, 2) + ylim(-2, 2), "limits")
  check_raster(ggplot(field, aes(x, y, fill = z)) + geom_raster() + coord_cartesian(xlim = c(10, 30), ylim = c(1, 4)), "zoomed, clipped")
  check_raster(ggplot(field, aes(x, y, fill = z)) + geom_raster(alpha = 1), "alpha 1")
  check_raster(ggplot(small, aes(x, y, fill = factor(z))) + geom_raster(), "discrete fill")
  check_raster(ggplot(expand.grid(x = c("a", "b"), y = c("c", "d")), aes(x, y, fill = interaction(x, y))) + geom_raster(), "discrete positions")
})

test_that("missing, NA, integer, empty and single-cell data", {
  na <- field
  na$z[c(5, 40, 41, 300)] <- NA
  check_raster(ggplot(na, aes(x, y, fill = z)) + geom_raster(), "NA fill as na.value")
  # ggplot2 warns of the rows it removes, as the reference drawing does.
  suppressWarnings(check_raster(ggplot(na, aes(x, y, fill = z)) + geom_raster() + scale_fill_continuous(na.value = NA), "NA fill removed"))
  set.seed(1)
  b <- ggplot_build(ggplot(na, aes(x, y, fill = z)) + geom_raster() + scale_fill_continuous(na.value = NA))
  expect_warning(render_raster(b, render_size), "Removed 4 rows")
  check_raster(ggplot(data.frame(x = c(2L, 4L, 8L), y = 1L, z = 1:3), aes(x, y, fill = z)) + geom_raster(), "integer positions")
  check_raster(ggplot(data.frame(x = c(0, 1, 2.5, 4), y = 0, z = 1:4), aes(x, y, fill = z)) + geom_raster(), "uneven positions")
  check_raster(ggplot(data.frame(x = c(1, 2, 2, 3), y = 0, z = 1:4), aes(x, y, fill = z)) + geom_raster(), "a shared cell")
  check_raster(ggplot(data.frame(x = 1, y = 1, z = 1), aes(x, y, fill = z)) + geom_raster(), "one cell")
  check_raster(ggplot(field[0, ], aes(x, y, fill = z)) + geom_raster(), "no rows")
  check_raster(ggplot(data.frame(x = c(1, 2), y = c(1, 2), f = c("red", "transparent")), aes(x, y, fill = f)) + geom_raster() + scale_fill_identity(), "transparent fill")
})

test_that("scales, coords, facets and sizes", {
  base <- ggplot(holes, aes(x, y, fill = z)) + geom_raster()
  check_raster(base + scale_x_reverse(), "reversed x")
  check_raster(base + scale_y_reverse(), "reversed y")
  check_raster(ggplot(holes, aes(x + 1, exp(y), fill = z)) + geom_raster() + scale_y_log10(), "log y")
  check_raster(base + scale_x_sqrt(), "sqrt x, uneven cells")
  check_raster(base + coord_fixed(), "coord_fixed")
  check_raster(base + coord_flip(), "coord_flip")
  check_raster(ggplot(small, aes(x, y, fill = z)) + geom_raster() + coord_flip(), "coord_flip, small")
  facets <- holes
  facets$g <- ifelse(facets$x > 20, "right", "left")
  check_raster(ggplot(facets, aes(x, y, fill = z)) + geom_raster() + facet_wrap(vars(g)), "facets")
  check_raster(ggplot(facets, aes(x, y, fill = z)) + geom_raster() + facet_wrap(vars(g), scales = "free_x"), "free facets")
  check_raster(ggplot(facets, aes(x, y, fill = z)) + geom_raster() + facet_grid(rows = vars(g)), "facet grid")
  # A cell narrower than a pixel, and one many pixels wide.
  set.seed(4)
  fine <- expand.grid(x = 1:600, y = 1:400)
  fine$z <- sin(fine$x / 40) * cos(fine$y / 25) + rnorm(nrow(fine), sd = 0.2)
  check_raster(ggplot(fine, aes(x, y, fill = z)) + geom_raster(), "cells under a pixel")
  check_raster(ggplot(data.frame(x = 1:2, y = 1, z = 1:2), aes(x, y, fill = z)) + geom_raster(), "wide cells", size = list(width = 333, height = 211))
  check_raster(base, "high resolution", size = list(width = 900, height = 600, res = 300))
})

test_that("rasters draw as ggplot2 draws them in the hybrid tier", {
  withr::local_options(alot.full_tier = FALSE)
  check_raster(ggplot(holes, aes(x, y, fill = z)) + geom_raster(), "hybrid", tier = "hybrid")
  check_raster(ggplot(holes, aes(x, y, fill = z)) + geom_raster() + coord_flip(), "hybrid coord_flip", tier = "hybrid")
  facets <- holes
  facets$g <- ifelse(facets$x > 20, "right", "left")
  check_raster(ggplot(facets, aes(x, y, fill = z)) + geom_raster() + facet_wrap(vars(g)), "hybrid facets", tier = "hybrid")
  # A plotmath title keeps the plot out of the full tier; the raster is
  # still drawn in Rust.
  p <- ggplot(holes, aes(x, y, fill = z)) + geom_raster() + labs(title = quote(alpha^2))
  withr::local_options(alot.full_tier = TRUE)
  cov <- alot_render_coverage(p)
  expect_equal(cov$tier, "hybrid")
  expect_equal(cov$layers$engine, "rust")
  check_raster(p, "hybrid under plotmath", tier = "hybrid")
})

test_that("unsupported rasters decline to another tier, with a reason", {
  base <- ggplot(small, aes(x, y, fill = z))
  reason <- function(p) {
    cov <- suppressWarnings(alot_render_coverage(p))
    expect_false(identical(cov$tier, "full"))
    paste(c(cov$full$reason, cov$layers$reason), collapse = "; ")
  }
  expect_match(reason(base + geom_raster(interpolate = TRUE)), "interpolate = TRUE")
  expect_match(reason(base + geom_raster(alpha = 0.5)), "a partial alpha")
  expect_match(reason(base + geom_raster() + scale_fill_gradient(low = "#FF000080", high = "#0000FF80")), "a partial alpha")
  expect_match(reason(base + geom_raster() + coord_polar()), "coord")
  expect_match(reason(base + geom_raster() + coord_transform(x = "identity")), "draws rects in coord_transform")
  expect_match(reason(base + geom_raster() + coord_cartesian(reverse = "x")), "coord")
  expect_match(reason(base + geom_raster() + coord_cartesian(clip = "off")), "clip")
  expect_match(reason(ggplot(small, aes(x, y)) + geom_raster(fill = grid::linearGradient())), "fill is not a colour vector")
  expect_match(reason(ggplot(small, aes(x, y)) + annotation_raster(matrix("red"), 0, 1, 0, 1) + geom_point()), "no Rust drawer|layers other than")
  # Each declined case falls to a tier that still draws it.
  for (p in list(base + geom_raster(interpolate = TRUE), base + geom_raster(alpha = 0.5), base + geom_raster() + coord_polar())) {
    expect_equal(suppressWarnings(alot_render_coverage(p))$tier, "ggplot2")
    file <- withr::local_tempfile(fileext = ".png")
    expect_equal(attr(suppressMessages(alot_png(p, file, width = 200, height = 150, units = "px", dpi = 72)), "tier"), "ggplot2")
  }
})
