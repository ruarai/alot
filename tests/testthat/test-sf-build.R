# The sf build steps (S2.1, R/sf.R): mirrors of LayerSf, StatSf and
# CoordSf, and CoordSf$setup_data's same-CRS skip.
skip_if_not_installed("sf")
library(ggplot2)

sf_steps <- c("setup_layer", "compute_geom_1", "compute_geom_2", "stat",
              "coord_setup_params", "coord_setup_data", "coord_record_bbox",
              "setup_panel_params")

sf_paths <- function(p) {
  cov <- alot_coverage(p)
  cov <- cov[cov$step %in% sf_steps, ]
  tapply(cov$path, cov$step, function(x) paste(unique(x), collapse = "+"))
}

nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
nc_3857 <- sf::st_transform(nc, 3857)

square <- function(x0, y0, d = 1) {
  sf::st_polygon(list(rbind(c(x0, y0), c(x0 + d, y0), c(x0 + d, y0 + d), c(x0, y0 + d), c(x0, y0))))
}
pts <- sf::st_sf(
  v = c(1, NA, 3),
  g = c("a", "b", "b"),
  geometry = sf::st_sfc(sf::st_point(c(-80, 35)), sf::st_point(c(-79, 36)), sf::st_point(c(-78, 35.5)), crs = 4326)
)
lines <- sf::st_sf(
  v = 1:2,
  geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-81, 34), c(-79, 36))),
    sf::st_multilinestring(list(rbind(c(-80, 34), c(-78, 35)), rbind(c(-77, 35), c(-76, 36)))),
    crs = 4326
  )
)

test_that("every sf build step runs as a mirror and matches ggplot2", {
  p <- ggplot(nc) + geom_sf(aes(fill = AREA))
  paths <- sf_paths(p)
  expect_setequal(names(paths), sf_steps)
  expect_true(all(paths == "rust"))
  expect_build_equal(p)
})

test_that("sf layers match ggplot2 across geometry types, NA and facets", {
  expect_build_equal(ggplot(pts) + geom_sf(aes(colour = v)))
  expect_build_equal(ggplot(lines) + geom_sf(aes(linewidth = v)))
  expect_build_equal(ggplot(nc[1, ]) + geom_sf())
  expect_build_equal(ggplot(nc) + geom_sf(aes(fill = SID74 > 5)) + geom_sf(data = pts) + geom_sf(data = lines))
  expect_build_equal(ggplot(pts) + geom_sf(aes(colour = g)) + facet_wrap(~g))
  nc$half <- ifelse(seq_len(nrow(nc)) <= 50, "north", "south")
  expect_build_equal(ggplot(nc) + geom_sf() + facet_grid(half ~ .))
  expect_build_equal(ggplot(nc) + geom_sf(show.legend = "point", aes(fill = AREA)))
  expect_build_equal(ggplot(nc) + stat_sf(aes(fill = AREA)))
  expect_build_equal(ggplot(nc) + geom_sf(aes(fill = AREA)) + scale_y_reverse())
  # A mixed sfc_GEOMETRY column.
  mixed <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0, 0)), square(1, 1), crs = 3857))
  expect_build_equal(ggplot(mixed) + geom_sf())
})

test_that("empty sf layers match ggplot2", {
  expect_build_equal(ggplot(nc[0, ]) + geom_sf())
  expect_build_equal(ggplot(nc) + geom_sf() + geom_sf(data = pts[0, ]))
})

test_that("coord_sf() settings match ggplot2", {
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(crs = 3857))
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(crs = sf::st_crs(32617)))
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(xlim = c(-82, -78), ylim = c(34, 36), expand = FALSE))
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(crs = 3857, default_crs = 4326, xlim = c(-82, -78)))
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(crs = 3857, default_crs = 4326, lims_method = "box", xlim = c(-82, -78), ylim = c(34, 36)))
  expect_build_equal(ggplot(nc) + geom_sf() + coord_sf(label_axes = "-NE-", reverse = "xy"))
  expect_build_equal(ggplot(nc) + geom_sf() + scale_x_continuous(breaks = c(-82, -78)) + scale_y_continuous(breaks = NULL))
  df <- data.frame(x = c(-80, -78), y = c(35, 36))
  expect_build_equal(ggplot(nc) + geom_sf() + geom_point(aes(x, y), data = df) + coord_sf(default_crs = 4326))
  expect_build_equal(ggplot(df, aes(x, y)) + geom_point() + coord_sf())
})

test_that("a layer in another CRS is transformed as ggplot2 transforms it", {
  # nc is NAD27; pts and lines are WGS 84, and nc_3857 is projected.
  expect_build_equal(ggplot(nc) + geom_sf() + geom_sf(data = pts) + geom_sf(data = nc_3857, fill = NA))
  expect_build_equal(ggplot(nc_3857) + geom_sf() + geom_sf(data = lines))
})

test_that("the same-CRS skip applies only where st_transform() returns its input", {
  # Each case: the sfc, the coord's crs, and whether the skip applies. For
  # every case where it does, st_transform() must return the sfc unchanged.
  g <- sf::st_geometry(nc)
  g_3857 <- sf::st_geometry(nc_3857)
  named <- g
  names(named) <- seq_along(g)
  precise <- g_3857
  sf::st_precision(precise) <- 100
  stale <- g
  stale[[1]][[1]][[1]][1, 1] <- 0 # nested assignment keeps the old bbox
  ring_attr <- g
  attr(ring_attr[[1]][[1]][[1]], "id") <- 1
  sfg_attr <- g
  attr(sfg_attr[[1]], "id") <- 1
  cases <- list(
    nad27 = list(g, sf::st_crs(g), TRUE),
    mercator = list(g_3857, 3857, TRUE),
    mercator_crs = list(g_3857, sf::st_crs(3857), TRUE),
    points = list(sf::st_geometry(pts), sf::st_crs(4326), TRUE),
    lines_mixed_multi = list(sf::st_geometry(lines), 4326, TRUE),
    mixed = list(sf::st_sfc(sf::st_point(c(0, 0)), square(1, 1), crs = 3857), 3857, TRUE),
    multipoint = list(sf::st_sfc(sf::st_multipoint(rbind(c(0, 0), c(1, 2))), crs = 3857), 3857, TRUE),
    hole = list(sf::st_sfc(sf::st_polygon(list(square(0, 0, 4)[[1]], square(1, 1)[[1]])), crs = 3857), 3857, TRUE),
    other_crs = list(g, sf::st_crs(4326), FALSE),
    character_crs = list(g_3857, "EPSG:3857", FALSE),
    na_crs = list(sf::st_set_crs(g, NA), NA, FALSE),
    geocentric = list(sf::st_sfc(sf::st_point(c(1, 2)), crs = 4978), 4978, FALSE),
    names = list(named, sf::st_crs(g), FALSE),
    precision = list(precise, 3857, FALSE),
    stale_bbox = list(stale, sf::st_crs(g), FALSE),
    ring_attr = list(ring_attr, sf::st_crs(g), FALSE),
    sfg_attr = list(sfg_attr, sf::st_crs(g), FALSE),
    empty = list(sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(), crs = 4326), 4326, FALSE),
    integer = list(sf::st_sfc(sf::st_point(c(1L, 2L)), crs = 4326), 4326, FALSE),
    xyz = list(sf::st_sfc(sf::st_point(c(1, 2, 3)), crs = 4326), 4326, FALSE),
    infinite = list(sf::st_sfc(sf::st_point(c(Inf, 2)), crs = 3857), 3857, FALSE),
    collection = list(sf::st_sfc(sf::st_geometrycollection(list(sf::st_point(c(1, 2)))), crs = 4326), 4326, FALSE),
    no_features = list(sf::st_sfc(crs = 4326), 4326, FALSE)
  )
  for (name in names(cases)) {
    x <- cases[[name]][[1]]
    crs <- cases[[name]][[2]]
    expect_identical(sfc_transform_is_noop(x, sf_noop_target(crs)), cases[[name]][[3]], label = name)
    if (cases[[name]][[3]]) {
      expect_identical(sf::st_transform(x, crs = crs), x, label = name)
    }
  }
})

test_that("layers the skip declines still match ggplot2", {
  precise <- nc_3857
  sf::st_precision(precise) <- 1
  expect_build_equal(ggplot(precise) + geom_sf())
  named <- nc
  names(named$geometry) <- seq_len(nrow(nc))
  expect_false(sfc_transform_is_noop(named$geometry, sf::st_crs(nc)))
  expect_build_equal(ggplot(named) + geom_sf())
  with_empty <- sf::st_sf(v = 1:2, geometry = sf::st_sfc(sf::st_point(c(1, 2)), sf::st_point(), crs = 3857))
  expect_build_equal(ggplot(with_empty) + geom_sf())
  xyz <- sf::st_sf(v = 1, geometry = sf::st_sfc(sf::st_point(c(1, 2, 3)), crs = 4326))
  expect_build_equal(ggplot(xyz) + geom_sf())
})

test_that("sf components that override mirrored methods fall back to ggplot2", {
  coord <- ggproto(NULL, coord_sf(), setup_data = function(data, params) data)
  p <- ggplot(nc) + geom_sf() + coord
  expect_equal(sf_paths(p)[["coord_setup_data"]], "ggplot2")
  expect_build_equal(p)

  coord <- ggproto(NULL, coord_sf(), record_bbox = function(self, xmin, xmax, ymin, ymax) {
    ggproto_parent(CoordSf, self)$record_bbox(xmin, xmax, ymin, ymax)
  })
  p <- ggplot(nc) + geom_sf() + coord
  expect_equal(sf_paths(p)[["coord_record_bbox"]], "ggplot2")
  expect_build_equal(p)

  # A subclass with its own name never reaches the CoordSf kernels.
  MyCoordSf <- ggproto("MyCoordSf", CoordSf)
  p <- ggplot(nc) + geom_sf() + ggproto(NULL, MyCoordSf, crs = NULL, limits = list(), expand = TRUE,
                                        default = FALSE, clip = "on", datum = sf::st_crs(4326),
                                        label_axes = list(top = "-", right = "-", bottom = "E", left = "N"),
                                        label_graticule = character(), ndiscr = 100, lims_method = "orthogonal")
  paths <- sf_paths(p)
  expect_true(all(paths[c("coord_setup_params", "coord_setup_data", "coord_record_bbox", "setup_panel_params")] == "ggplot2"))
  expect_build_equal(p)

  stat <- ggproto("MyStatSf", StatSf)
  p <- ggplot(nc) + geom_sf(stat = stat)
  expect_equal(sf_paths(p)[["stat"]], "ggplot2")
  expect_build_equal(p)

  stat <- ggproto(NULL, StatSf, compute_panel = function(self, data, scales, coord) {
    ggproto_parent(StatSf, self)$compute_panel(data, scales, coord)
  })
  p <- ggplot(nc) + geom_sf(stat = stat)
  expect_equal(sf_paths(p)[["stat"]], "ggplot2")
  expect_build_equal(p)

  layer <- geom_sf()[[1]]
  layer$compute_geom_1 <- function(self, data) {
    ggproto_parent(ggplot2:::LayerSf, self)$compute_geom_1(data)
  }
  p <- ggplot(nc) + layer
  paths <- sf_paths(p)
  expect_equal(paths[["compute_geom_1"]], "ggplot2")
  expect_equal(paths[["setup_layer"]], "rust")
  expect_build_equal(p)
})

test_that("geom_sf() under non-sf coords matches ggplot2", {
  p <- ggplot(nc) + geom_sf() + coord_cartesian()
  paths <- sf_paths(p)
  expect_equal(paths[["stat"]], "rust")
  expect_false("coord_setup_data" %in% names(paths))
  suppressWarnings(expect_build_equal(p))
})
