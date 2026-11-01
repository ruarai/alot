# geom_sf() polygons in the hybrid tier (S3.2, R/render-sf.R): GeomSf's
# per-feature gpar and sf::st_as_grob()'s even-odd paths, drawn in Rust as
# lazy grobs on ggplot2's gtable, against ggplot2 on ragg. Covers holes,
# MULTIPOLYGONs, outline-only and fill-only styles, line types, NA fill and
# colour, reversed ranges, projected and longlat CRSs, facets, and the cases
# that decline.

skip_on_cran()
skip_if_not_installed("sf")
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_sf <- function(p, label, ..., size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  cov <- suppressWarnings(alot_render_coverage(b))
  expect_equal(cov$tier, "hybrid", label = label)
  expect_equal(cov$layers$engine[cov$layers$geom == "GeomSf"], rep("rust", sum(cov$layers$geom == "GeomSf")), label = label)
  key <- render_case_key("test-render-sf.R", label, b)
  # ggplot2's own grob for a panel Rust declined at draw time would match
  # the reference trivially: make it fail instead.
  local_mocked_bindings(hybrid_fallback_grob = function(x) stop("a lazy grob fell back to ggplot2"))
  expect_no_warning(
    suppressMessages(do.call(expect_render_close, c(list(b), size, list(..., tier = "hybrid", label = label, cache_key = key)))),
    class = "alot_render_fallback"
  )
  # The hybrid tier keeps ggplot2's gtable; alot's own page layout declines
  # coord_sf() until the full tier draws it (S5).
  expect_equal(expect_layout_matches(b, utils::modifyList(render_size, size), label = label, cache_key = key), "coord not laid out")
}

nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
nc$g <- rep(c("a", "b"), length.out = nrow(nc))

ring <- function(x, y, r, n = 24) {
  t <- seq(0, 2 * pi, length.out = n + 1)
  m <- cbind(x + r * cos(t), y + r * sin(t))
  m[n + 1, ] <- m[1, ]
  m
}
square <- function(x, y, s) cbind(c(x, x + s, x + s, x, x), c(y, y, y + s, y + s, y))
shapes <- sf::st_sf(
  id = c("donut", "multi", "square"),
  geometry = sf::st_sfc(
    sf::st_polygon(list(ring(0, 0, 3), ring(0, 0, 1.5), ring(1, 1, 0.4))),
    sf::st_multipolygon(list(list(square(4, -1, 2)), list(square(5, 0, 2), square(5.5, 0.5, 0.5)))),
    sf::st_polygon(list(square(-2, -5, 9))),
    crs = 3857
  )
)

test_that("polygons draw as ggplot2 draws them", {
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)), "choropleth")
  check_sf(ggplot(nc) + geom_sf(), "defaults")
  check_sf(ggplot(shapes) + geom_sf(aes(fill = id), alpha = 0.6), "holes and multipolygons")
  check_sf(ggplot(shapes[c(3, 1, 2), ]) + geom_sf(aes(fill = id), colour = "black", linewidth = 1.2), "data order")
  check_sf(ggplot(nc) + geom_sf(fill = NA, colour = "grey20"), "outline only")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA), colour = NA), "fill only")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA), colour = "#0000FF80", linewidth = 0.8), "translucent outline")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA), alpha = 0.4), "alpha")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA), linewidth = 0), "zero linewidth")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + geom_sf(data = nc[1:5, ], fill = NA, colour = "red", linewidth = 1), "two layers")
})

test_that("line types, ends, joins and NA styles", {
  check_sf(ggplot(nc) + geom_sf(fill = NA, linetype = "dashed"), "dashed")
  check_sf(ggplot(shapes) + geom_sf(aes(linetype = id), fill = NA, linewidth = 1), "mapped line types")
  check_sf(ggplot(shapes) + geom_sf(fill = NA, linetype = "1342", linewidth = 1.5), "hex line type")
  check_sf(ggplot(shapes) + geom_sf(fill = "grey80", linetype = "blank"), "blank line type")
  check_sf(ggplot(shapes) + geom_sf(fill = NA, linewidth = 3, linejoin = "mitre", lineend = "square"), "mitre joins")
  check_sf(ggplot(shapes) + geom_sf(fill = NA, linewidth = 3, linejoin = "bevel"), "bevel joins")
  na <- nc
  na$AREA[c(3, 40, 77)] <- NA
  check_sf(ggplot(na) + geom_sf(aes(fill = AREA)), "NA fill as na.value")
  check_sf(ggplot(na) + geom_sf(aes(fill = AREA)) + scale_fill_continuous(na.value = NA), "NA fill transparent")
  shapes$col <- c("red", NA, "blue")
  shapes$fill <- c(NA, "orange", "#00800080")
  check_sf(ggplot(shapes) + geom_sf(aes(colour = col, fill = fill), linewidth = 1) + scale_colour_identity() + scale_fill_identity(), "NA colour and fill")
})

test_that("CRSs, reversed ranges, limits, facets and sizes", {
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + coord_sf(crs = 32119), "projected crs")
  check_sf(ggplot(sf::st_transform(nc, 3857)) + geom_sf(aes(fill = AREA)), "projected data")
  check_sf(ggplot(sf::st_transform(nc, 4326)) + geom_sf(aes(fill = AREA)) + coord_sf(crs = 4326), "longlat")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + coord_sf(reverse = "x"), "reversed x")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + coord_sf(reverse = "xy"), "reversed xy")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + coord_sf(xlim = c(-80, -76), ylim = c(34, 36.5)), "zoomed, clipped")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + coord_sf(expand = FALSE), "no expansion")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + facet_wrap(vars(g)), "facets")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + facet_grid(rows = vars(g)), "facet grid")
  check_sf(ggplot(nc[1, ]) + geom_sf(), "one feature")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)), "high resolution", size = list(width = 900, height = 600, res = 300))
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)), "odd size", size = list(width = 333, height = 211))
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + labs(title = quote(alpha^2)), "plotmath title")
})

test_that("coord_sf() without breaks", {
  # The empty graticule's view scales have no breaks to report (render_ir()).
  p <- ggplot(nc) + geom_sf() + scale_x_continuous(breaks = NULL) + scale_y_continuous(breaks = NULL)
  ir <- render_ir(ggplot_build(p))
  expect_null(ir$scales[[1]]$x$major)
  check_sf(p, "no breaks")
  check_sf(ggplot(nc) + geom_sf() + coord_sf(datum = NA), "no datum")
})

test_that("unsupported sf layers decline to ggplot2, with a reason", {
  reason <- function(p) {
    cov <- suppressWarnings(alot_render_coverage(p))
    expect_equal(cov$tier, "ggplot2")
    paste(cov$layers$reason, collapse = "; ")
  }
  pts <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-80, 35)), sf::st_point(c(-78, 36)), crs = sf::st_crs(nc)))
  mixed <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(square(0, 0, 1))), sf::st_point(c(2, 2))))
  collection <- sf::st_sf(geometry = sf::st_sfc(sf::st_geometrycollection(list(sf::st_polygon(list(square(0, 0, 1)))))))
  empty <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(square(0, 0, 1))), sf::st_polygon()))
  xyz <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(cbind(square(0, 0, 1), 0)))))
  expect_match(reason(ggplot(pts) + geom_sf()), "features other than polygons")
  expect_match(reason(ggplot(mixed) + geom_sf()), "features other than polygons")
  expect_match(reason(ggplot(collection) + geom_sf()), "sfc reader")
  expect_match(suppressWarnings(reason(ggplot(empty) + geom_sf())), "sfc reader")
  expect_match(reason(ggplot(xyz) + geom_sf()), "sfc reader")
  expect_match(reason(ggplot(nc) + geom_sf() + coord_sf(default_crs = sf::st_crs(4326))), "default_crs")
  expect_match(reason(ggplot(nc) + geom_sf() + coord_sf(clip = "off")), "clip")
  expect_match(reason(ggplot(nc) + geom_sf(fill = grid::linearGradient())), "fill is not a colour vector")
  expect_match(reason(ggplot(nc) + geom_sf(linetype = "zz")), "unsupported linetype")
  expect_match(reason(ggplot(nc) + geom_sf(arrow = grid::arrow())), "arrows")
  # A legend-only layer's geometry is a character (LayerSf$compute_geom_2).
  b <- ggplot_build(ggplot(nc) + geom_sf())
  data <- b@data[[1]]
  data$geometry <- "other"
  expect_equal(sf_decline(b@plot@layers[[1]], data, b@layout), "geometry is not an sfc")
  # Each declined case still draws, with ggplot2.
  for (p in list(ggplot(pts) + geom_sf(), ggplot(nc) + geom_sf() + coord_sf(default_crs = sf::st_crs(4326)))) {
    file <- withr::local_tempfile(fileext = ".png")
    expect_equal(attr(suppressMessages(alot_png(p, file, width = 200, height = 150, units = "px", dpi = 72)), "tier"), "ggplot2")
  }
  # The polygon layer of a plot with a point layer is still drawn in Rust.
  cov <- alot_render_coverage(ggplot(nc) + geom_sf() + geom_sf(data = pts))
  expect_equal(cov$tier, "hybrid")
  expect_equal(cov$layers$engine, c("rust", "ggplot2"))
})
