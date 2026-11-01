# The sfc reader and CoordSf$transform's rescale (S3.1): sfc_geometry() and
# rescale01() (alot-r src/sf.rs, alot-core src/sf/geometry.rs), through the
# rs_sf_rescale01() test hook, against sf::st_coordinates() of ggplot2's
# sf_rescale01() (R/coord-sf.R).
skip_if_not_installed("sf")
library(ggplot2)

expect_rescale_equal <- function(x, x_range, y_range) {
  got <- rs_sf_rescale01(x, x_range, y_range)
  expect_false(is.null(got))
  res <- gg_sf_rescale01(x, x_range, y_range)
  # st_coordinates() takes one geometry type at a time, so per feature.
  want <- lapply(seq_along(res), function(i) sf::st_coordinates(res[i])[, c("X", "Y"), drop = FALSE])
  want <- unname(do.call(rbind, want))
  # Bit for bit: sf adds `-min` then multiplies by `1 / range` (sf
  # src/ops.cpp), and the reader does the same.
  expect_identical(got, want)
}

square <- function(x0, y0, d = 1) {
  rbind(c(x0, y0), c(x0 + d, y0), c(x0 + d, y0 + d), c(x0, y0 + d), c(x0, y0))
}
# One feature of each type, shifted by `d` and scaled by `k`. Built from
# plain matrices: sf's arithmetic (Ops.sfg) sets a class on each matrix,
# which the reader declines.
make_features <- function(d = c(0, 0), k = 1) {
  m <- function(...) sweep(rbind(...) * k, 2, d, "+")
  sq <- function(x0, y0, w = 1) m(square(x0, y0, w) / k)
  list(
    point = sf::st_point(c(-80.25, 35.1) * k + d),
    multipoint = sf::st_multipoint(m(c(-81, 34.5), c(-79.3, 36.2), c(-78.1, 35))),
    linestring = sf::st_linestring(m(c(-81, 34), c(-79.7, 36.4), c(-77.9, 35.3))),
    multilinestring = sf::st_multilinestring(list(
      m(c(-82, 34), c(-80, 35)),
      m(c(-79, 36), c(-78.5, 34.2), c(-77, 36.6))
    )),
    polygon = sf::st_polygon(list(sq(-81, 34, 2), sq(-80.5, 34.5, 0.5))),
    multipolygon = sf::st_multipolygon(list(
      list(sq(-84, 33.9, 1.3)),
      list(sq(-78, 35, 1.7), sq(-77.6, 35.2, 0.3))
    ))
  )
}
features <- make_features()
shifted <- make_features(c(0.5, -0.25))
scaled <- make_features(k = 0.99)
ranges <- list(x = c(-84.4, -75.2), y = c(33.6, 36.9))
rev_ranges <- list(
  none = ranges,
  x = list(x = rev(ranges$x), y = ranges$y),
  y = list(x = ranges$x, y = rev(ranges$y)),
  xy = list(x = rev(ranges$x), y = rev(ranges$y))
)

test_that("each geometry type rescales as sf_rescale01() does, reversed or not", {
  for (type in names(features)) {
    for (r in names(rev_ranges)) {
      sfc <- sf::st_sfc(features[[type]], crs = 4326)
      expect_rescale_equal(sfc, rev_ranges[[r]]$x, rev_ranges[[r]]$y)
      # Several features of one type.
      sfc <- sf::st_sfc(features[[type]], shifted[[type]], scaled[[type]])
      expect_rescale_equal(sfc, rev_ranges[[r]]$x, rev_ranges[[r]]$y)
    }
  }
})

test_that("a mixed sfc_GEOMETRY rescales in data order", {
  sfc <- sf::st_sfc(rev(features), crs = 4326)
  expect_s3_class(sfc, "sfc_GEOMETRY")
  for (r in rev_ranges) expect_rescale_equal(sfc, r$x, r$y)
})

test_that("panel ranges from a built coord_sf() plot, including reverse", {
  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  nc_3857 <- sf::st_transform(nc, 3857)
  for (reverse in c("none", "x", "y", "xy")) {
    for (d in list(nc, nc_3857)) {
      b <- ggplot_build(ggplot(d) + geom_sf() + coord_sf(reverse = reverse))
      pp <- b$layout$panel_params[[1]]
      # As CoordSf$transform passes them to sf_rescale01().
      x_range <- switch(reverse, xy = , x = rev, identity)(pp$x_range)
      y_range <- switch(reverse, xy = , y = rev, identity)(pp$y_range)
      expect_rescale_equal(sf::st_geometry(d), x_range, y_range)
    }
  }
})

test_that("integer coordinates are read as the doubles sf_rescale01() gives", {
  # The build path's walker stays strict (rs_sfc_plain_xy()).
  sfc <- sf::st_sfc(
    sf::st_point(0:1), sf::st_linestring(rbind(0:1, 1:2)), sf::st_polygon(list(rbind(0:1, 1:2, 2:1, 0:1))),
    sf::st_multipoint(cbind(1:2, 3:4)), sf::st_multilinestring(list(cbind(1:3, 4:6)))
  )
  expect_null(rs_sfc_plain_xy(sfc))
  expect_equal(rs_sfc_render_types(sfc), c(1L, 3L, 5L, 2L, 4L))
  expect_rescale_equal(sfc, c(-0.1, 3.3), c(0.7, 6.2))
  expect_rescale_equal(sfc, c(3.3, -0.1), c(6.2, 0.7))
  expect_null(rs_sfc_render_types(sf::st_sfc(sf::st_geometrycollection(list(sf::st_point(0:1))))))
})

test_that("unsupported geometry declines", {
  r <- ranges
  declines <- function(x) expect_null(rs_sf_rescale01(x, r$x, r$y))
  pt <- features$point
  declines(sf::st_sfc(crs = 4326))
  declines(sf::st_sfc(pt, sf::st_point()))
  declines(sf::st_sfc(sf::st_polygon()))
  declines(sf::st_sfc(sf::st_multipolygon()))
  declines(sf::st_sfc(sf::st_linestring()))
  declines(sf::st_sfc(sf::st_geometrycollection(list(pt))))
  declines(sf::st_sfc(pt, sf::st_geometrycollection(list(pt))))
  declines(sf::st_sfc(sf::st_point(c(1, 2, 3))))
  declines(sf::st_sfc(sf::st_point(c(1, 2, 3), dim = "XYM")))
  declines(sf::st_sfc(sf::st_linestring(cbind(1:2 + 0.5, 3:4 + 0.5, 5:6 + 0.5))))
  declines(sf::st_sfc(sf::st_polygon(list(cbind(square(0, 0), 0)))))
  declines(sf::st_sfc(sf::st_point(c(NA_real_, 1))))
  declines(sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(Inf, 1)))))
  declines(sf::st_sfc(sf::st_point(c(1L, NA))))
  # sf's arithmetic leaves a class on each matrix.
  declines(sf::st_sfc(features$polygon + c(1, 1)))
  # Ranges where st_normalize() errors.
  sfc <- sf::st_sfc(pt)
  expect_null(rs_sf_rescale01(sfc, c(1, 1), r$y))
  expect_error(gg_sf_rescale01(sfc, c(1, 1), r$y), "positive range")
  expect_null(rs_sf_rescale01(sfc, r$x, c(NA, 1)))
  expect_null(rs_sf_rescale01(sfc, r$x, c(0, Inf)))
})
