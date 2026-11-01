# geom_sf() in the hybrid tier (S3.2, S3.3, R/render-sf.R): GeomSf's
# per-feature gpar and sf::st_as_grob()'s even-odd paths, polylines and
# points, drawn in Rust as lazy grobs on ggplot2's gtable, against ggplot2
# on ragg. Covers holes, MULTIPOLYGONs, outline-only and fill-only styles,
# (MULTI)LINESTRINGs, (MULTI)POINTs in every shape, line types, ends and
# joins, NA styles, mixed point/line/polygon layers, reversed ranges,
# projected and longlat CRSs, facets, and the cases that decline.

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

lines <- suppressWarnings(sf::st_cast(sf::st_cast(nc[1:25, c("AREA", "g")], "MULTILINESTRING"), "LINESTRING"))
multilines <- sf::st_cast(nc[1:25, c("AREA", "g")], "MULTILINESTRING")
centroids <- sf::st_sf(AREA = nc$AREA, g = nc$g, geometry = suppressWarnings(sf::st_centroid(sf::st_geometry(nc))))
pt <- function(x, y) sf::st_point(as.double(c(x, y)))
shape_grid <- sf::st_sf(
  shape = 0:25,
  geometry = sf::st_sfc(lapply(0:25, function(i) pt(i %% 7, i %/% 7)), crs = 3857)
)
multipoints <- sf::st_sf(
  id = c("a", "b", "c"),
  geometry = sf::st_sfc(
    sf::st_multipoint(cbind(c(0, 1, 2, 3), c(0, 1, 0, 1))),
    pt(1.5, 2),
    sf::st_multipoint(cbind(c(0.5, 2.5), c(1.6, 1.6))),
    crs = 3857
  )
)
zigzag <- function(x0, n = 6) cbind(x0 + seq(0, 1, length.out = n), rep(c(0, 1), length.out = n))
line_shapes <- sf::st_sf(
  id = c("zig", "multi", "long"),
  geometry = sf::st_sfc(
    sf::st_linestring(zigzag(0)),
    sf::st_multilinestring(list(zigzag(1.5), zigzag(1.5)[, 2:1] + c(0, 0.2))),
    sf::st_linestring(cbind(c(-1, 4), c(0.5, 0.6))),
    crs = 3857
  )
)
# Points, lines and polygons interleaved in one sfc: drawn in data order.
mixed <- sf::st_sf(
  id = letters[1:8],
  geometry = sf::st_sfc(
    sf::st_polygon(list(square(0, 0, 3))),
    pt(1, 1),
    sf::st_linestring(cbind(c(-1, 4), c(1, 2))),
    sf::st_multipoint(cbind(c(2, 3, 2.5), c(2, 0.5, 1.2))),
    sf::st_multipolygon(list(list(square(3.5, 2, 1)), list(square(1, 2.5, 1)))),
    sf::st_multilinestring(list(cbind(c(0, 4), c(3.5, 0)), cbind(c(0, 4), c(0, 3.5)))),
    pt(3, 3),
    pt(0.5, 3.2),
    crs = 3857
  )
)

test_that("lines draw as ggplot2 draws them", {
  check_sf(ggplot(lines) + geom_sf(), "linestrings")
  check_sf(ggplot(multilines) + geom_sf(aes(colour = AREA)), "multilinestrings")
  check_sf(ggplot(line_shapes) + geom_sf(aes(colour = id), linewidth = 2), "line shapes")
  check_sf(ggplot(line_shapes) + geom_sf(aes(linewidth = id)) + scale_linewidth_discrete(range = c(0.3, 3)), "linewidth varies")
  check_sf(ggplot(lines) + geom_sf(colour = "#FF000080", linewidth = 1.5, alpha = 0.5), "alpha on lines")
  check_sf(ggplot(lines) + geom_sf(linetype = "dashed"), "dashed lines")
  check_sf(ggplot(line_shapes) + geom_sf(aes(linetype = id), linewidth = 1), "mapped line types on lines")
  check_sf(ggplot(line_shapes) + geom_sf(linetype = "1342", linewidth = 1.5), "hex line type on lines")
  check_sf(ggplot(line_shapes) + geom_sf(linewidth = 4, lineend = "round"), "round ends")
  check_sf(ggplot(line_shapes) + geom_sf(linewidth = 4, lineend = "square", linejoin = "mitre"), "square ends, mitre joins")
  check_sf(ggplot(line_shapes) + geom_sf(linewidth = 4, linejoin = "bevel"), "bevel joins on lines")
  line_shapes$col <- c("red", NA, "blue")
  check_sf(ggplot(line_shapes) + geom_sf(aes(colour = col), na.rm = TRUE) + scale_colour_identity(), "NA colour on lines")
})

test_that("points draw as ggplot2 draws them", {
  check_sf(ggplot(centroids) + geom_sf(), "points")
  check_sf(ggplot(centroids) + geom_sf(aes(colour = AREA, size = AREA)), "points, colour and size")
  check_sf(ggplot(multipoints) + geom_sf(aes(colour = id), size = 4), "multipoints")
  check_sf(ggplot(shape_grid) + geom_sf(aes(shape = shape), size = 5, fill = "orange", colour = "navy") + scale_shape_identity(), "every shape")
  check_sf(ggplot(shape_grid) + geom_sf(aes(shape = shape), size = 6, stroke = 2, fill = "orange", lineend = "round") + scale_shape_identity(), "every shape, round ends")
  check_sf(ggplot(shape_grid) + geom_sf(aes(shape = shape), size = 6, stroke = 2, linejoin = "mitre") + scale_shape_identity(), "every shape, mitre joins")
  check_sf(ggplot(shape_grid) + geom_sf(aes(shape = shape), size = 4, stroke = 0, fill = "orange") + scale_shape_identity(), "every shape, no stroke")
  check_sf(ggplot(shape_grid) + geom_sf(aes(stroke = shape / 5), shape = 21, size = 4, fill = "orange"), "stroke varies")
  check_sf(ggplot(shape_grid) + geom_sf(aes(size = shape / 3), shape = 4) + scale_size_identity(), "size varies")
  check_sf(ggplot(centroids) + geom_sf(shape = "triangle filled", fill = "red", size = 3), "shape name")
  check_sf(ggplot(centroids) + geom_sf(colour = "blue", alpha = 0.3, size = 4), "alpha on points")
  check_sf(ggplot(shape_grid) + geom_sf(shape = 21, size = 5, fill = NA, colour = "black"), "NA fill on points")
  shape_grid$col <- ifelse(shape_grid$shape %% 4 == 0, NA, "darkgreen")
  shape_grid$sz <- ifelse(shape_grid$shape %% 5 == 0, NA, 3)
  check_sf(ggplot(shape_grid) + geom_sf(aes(colour = col, size = sz), na.rm = TRUE) + scale_colour_identity() + scale_size_identity(), "NA colour and size on points")
})

test_that("mixed point, line and polygon layers draw in data order", {
  check_sf(ggplot(mixed) + geom_sf(), "mixed defaults")
  check_sf(ggplot(mixed) + geom_sf(aes(colour = id, fill = id), linewidth = 1.5, size = 5, shape = 21, alpha = 0.6), "mixed styles")
  check_sf(ggplot(mixed[8:1, ]) + geom_sf(aes(colour = id), linewidth = 2, size = 6, shape = 3), "mixed, reversed order")
  check_sf(ggplot(mixed) + geom_sf(aes(linewidth = id), shape = 4, size = 4), "mixed linewidths")
  mixed$lt <- ifelse(sf::st_geometry_type(mixed) %in% c("POINT", "MULTIPOINT"), "solid", "dashed")
  check_sf(ggplot(mixed) + geom_sf(aes(linetype = I(lt)), linewidth = 1), "mixed line types")
  check_sf(ggplot(nc) + geom_sf(aes(fill = AREA)) + geom_sf(data = centroids, colour = "red") + geom_sf(data = lines, colour = "white"), "three layers")
  # Integer coordinates, as sf stores st_point(0:1) (test-geom-sf.R).
  ints <- sf::st_sfc(sf::st_point(0:1), sf::st_linestring(rbind(0:1, 1:2)), sf::st_polygon(list(rbind(0:1, 1:2, 2:1, 0:1))), sf::st_multipoint(cbind(1:2, 3:4)))
  check_sf(ggplot(ints) + geom_sf(colour = "#FF0000FF", fill = "#FF0000FF", alpha = 0.5), "integer coordinates")
})

test_that("lines and points under CRSs, reversed ranges and facets", {
  check_sf(ggplot(centroids) + geom_sf(aes(colour = AREA)) + coord_sf(crs = 32119), "points, projected crs")
  check_sf(ggplot(multilines) + geom_sf(aes(colour = AREA)) + coord_sf(crs = 32119), "lines, projected crs")
  check_sf(ggplot(sf::st_transform(centroids, 4326)) + geom_sf(shape = 4) + coord_sf(crs = 4326), "points, longlat")
  check_sf(ggplot(sf::st_transform(lines, 4326)) + geom_sf() + coord_sf(crs = 4326), "lines, longlat")
  check_sf(ggplot(centroids) + geom_sf(shape = 2, size = 3) + coord_sf(reverse = "y"), "points, reversed y")
  check_sf(ggplot(mixed) + geom_sf(aes(colour = id), size = 3) + coord_sf(reverse = "xy"), "mixed, reversed xy")
  check_sf(ggplot(centroids) + geom_sf(size = 4) + coord_sf(xlim = c(-80, -76), ylim = c(34, 36.5)), "points, zoomed, clipped")
  check_sf(ggplot(lines) + geom_sf(linewidth = 1) + coord_sf(xlim = c(-80, -76), ylim = c(35.5, 37)), "lines, zoomed, clipped")
  check_sf(ggplot(centroids) + geom_sf(aes(colour = AREA)) + facet_wrap(vars(g)), "points, facets")
  check_sf(ggplot(lines) + geom_sf() + facet_grid(rows = vars(g)), "lines, facet grid")
  check_sf(ggplot(centroids[1, ]) + geom_sf(size = 5), "one point")
  check_sf(ggplot(mixed) + geom_sf(aes(colour = id), size = 3, linewidth = 1), "mixed, high resolution", size = list(width = 900, height = 600, res = 300))
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
  expect_match(reason(ggplot(pts) + geom_sf(shape = "a")), "character or unknown pch")
  expect_match(reason(ggplot(pts) + geom_sf(shape = 65)), "unsupported shape")
  expect_match(reason(ggplot(pts) + geom_sf(stroke = NA)), "NA in size or stroke")
  expect_match(reason(ggplot(pts) + geom_sf(linetype = "dashed")), "points with a line type other than solid")
  expect_match(reason(ggplot(mixed) + geom_sf(linetype = "dashed")), "points with a line type other than solid")
  expect_match(reason(ggplot(lines) + geom_sf(linetype = "zz")), "unsupported linetype")
  expect_match(reason(ggplot(lines) + geom_sf(arrow = grid::arrow())), "arrows")
  expect_match(reason(ggplot(lines) + geom_sf(lineend = "squared")), "lineend")
  expect_match(reason(ggplot(pts) + geom_sf(linejoin = "mitred")), "linejoin")
  point_collection <- sf::st_sf(geometry = sf::st_sfc(sf::st_geometrycollection(list(pt(0, 0), sf::st_linestring(cbind(c(0, 1), c(0, 1)))))))
  expect_match(reason(ggplot(point_collection) + geom_sf()), "sfc reader")
  int_na <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(1:2), sf::st_point(c(3L, NA))))
  expect_match(suppressWarnings(reason(ggplot(int_na) + geom_sf())), "sfc reader")
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
  for (p in list(ggplot(pts) + geom_sf(shape = 65), ggplot(nc) + geom_sf() + coord_sf(default_crs = sf::st_crs(4326)))) {
    file <- withr::local_tempfile(fileext = ".png")
    expect_equal(attr(suppressMessages(alot_png(p, file, width = 200, height = 150, units = "px", dpi = 72)), "tier"), "ggplot2")
  }
  # The polygon layer of a plot with a declined point layer is still drawn
  # in Rust.
  cov <- alot_render_coverage(ggplot(nc) + geom_sf() + geom_sf(data = pts, shape = 65))
  expect_equal(cov$tier, "hybrid")
  expect_equal(cov$layers$engine, c("rust", "ggplot2"))
})
