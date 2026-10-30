# The hybrid tier: point layers rasterised in Rust (R/render.R). Output
# is compared with ggplot2 drawn by ragg pixel by pixel: rendering only has
# to look the same, so edge pixels may differ slightly (anti-aliasing,
# subpixel positions).

capture_rgb <- function(g, width = 400, height = 300, res = 96) {
  cap <- ragg::agg_capture(width = width, height = height, units = "px", res = res)
  on.exit(grDevices::dev.off())
  grid::grid.newpage()
  grid::grid.draw(g)
  grDevices::col2rgb(cap(native = FALSE))
}

# Largest per-pixel difference and the share of pixels differing by more
# than 8 (of 255).
render_diff <- function(p, ...) {
  b <- ggplot2::ggplot_build(p)
  d <- abs(capture_rgb(ggplot2::ggplot_gtable(b), ...) - capture_rgb(hybrid_gtable(b), ...))
  px <- apply(d, 2, max)
  c(max = max(d), share = mean(px > 8))
}

# Width and height from a PNG's IHDR chunk.
png_size <- function(file) {
  bytes <- readBin(file, "raw", 24)
  stopifnot(identical(bytes[13:16], charToRaw("IHDR")))
  c(readBin(bytes[17:20], "integer", endian = "big"), readBin(bytes[21:24], "integer", endian = "big"))
}

panel_children <- function(g) {
  g$grobs[[grep("^panel", g$layout$name)[1]]]$children
}

# Whether the hybrid gtable draws the plot's points in Rust; checks that
# alot_render_coverage() agrees.
uses_rust <- function(p) {
  b <- ggplot2::ggplot_build(p)
  rust <- any(vapply(panel_children(hybrid_gtable(b)), inherits, logical(1), "alot_hybrid_points"))
  cov <- alot_render_coverage(b)
  expect_equal(cov$tier, if (rust) "hybrid" else "ggplot2")
  expect_equal(cov$layers$engine == "rust", rust)
  rust
}

set.seed(1)
d <- data.frame(
  x = runif(300), y = runif(300), c = runif(300),
  s = factor(sample(c("a", "b", "c", "d"), 300, TRUE))
)

test_that("ggplot2's default point renders like ragg", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  expect_true(uses_rust(p))
  expect_lte(render_diff(p)[["max"]], 32)
})

test_that("supported shapes render like ragg", {
  for (shape in c(0:4, 15:17, 19, 20)) {
    p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
      ggplot2::geom_point(shape = shape, size = 4, alpha = 0.5, colour = "steelblue")
    expect_true(uses_rust(p))
    diff <- render_diff(p)
    expect_lte(diff[["max"]], 32)
    expect_lt(diff[["share"]], 0.01)
  }
})

test_that("mapped colour, shape, stroke, facets and log scales render like ragg", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x * 1000 + 1, y, colour = c, shape = s)) +
    ggplot2::geom_point(alpha = 0.3, stroke = 1.5) +
    ggplot2::scale_x_log10() +
    ggplot2::facet_wrap(~s)
  expect_true(uses_rust(p))
  diff <- render_diff(p, width = 600, height = 400, res = 150)
  expect_lte(diff[["max"]], 32)
  expect_lt(diff[["share"]], 0.01)
})

test_that("infinite positions are squished to the panel edge", {
  p <- ggplot2::ggplot(data.frame(x = c(-Inf, 0.5, Inf), y = c(0.5, Inf, -Inf)), ggplot2::aes(x, y)) +
    ggplot2::geom_point(size = 5) +
    ggplot2::lims(x = c(0, 1), y = c(0, 1))
  expect_true(uses_rust(p))
  # Half of each point is clipped at the panel edge, which falls between
  # pixels; the edge pixels there differ more than elsewhere.
  diff <- render_diff(p)
  expect_lte(diff[["max"]], 64)
  expect_lt(diff[["share"]], 0.001)
})

test_that("unsupported layers and coords keep ggplot2's pointsGrob, with a reason", {
  base <- ggplot2::ggplot(d, ggplot2::aes(x, y))
  na <- d
  na$y[1] <- NA
  cases <- list(
    "unsupported shape" = base + ggplot2::geom_point(shape = 21, fill = "red"),
    "unsupported shape" = base + ggplot2::geom_point(shape = "circle filled"),
    "clip is not \"on\"" = base + ggplot2::geom_point() + ggplot2::coord_cartesian(clip = "off"),
    "coord is not an unreversed coord_cartesian()" = base + ggplot2::geom_point() + ggplot2::coord_flip(),
    "NA in x, y, size, stroke or colour" =
      ggplot2::ggplot(na, ggplot2::aes(x, y)) + ggplot2::geom_point(na.rm = TRUE),
    "position scale does not rescale linearly" =
      base + ggplot2::geom_point() + ggplot2::continuous_scale(
        "x", palette = identity, guide = "axis", position = "bottom", super = ggplot2::ScaleContinuousPosition,
        rescaler = function(x, to = c(0, 1), from = range(x)) scales::rescale(x, to, from)
      ),
    "no rows" = ggplot2::ggplot(d[0, ], ggplot2::aes(x, y)) + ggplot2::geom_point(),
    "no Rust drawer for this geom" = base + ggplot2::geom_line()
  )
  for (reason in names(cases)) {
    p <- cases[[reason]]
    expect_false(uses_rust(p))
    expect_equal(alot_render_coverage(p)$layers$reason, reason)
  }
})

test_that("alot_render_coverage() reports each layer", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_line() + ggplot2::geom_point()
  cov <- alot_render_coverage(p)
  expect_equal(cov$tier, "hybrid")
  expect_equal(cov$layers$geom, c("GeomLine", "GeomPoint"))
  expect_equal(cov$layers$engine, c("ggplot2", "rust"))
  expect_equal(cov$layers$reason, c("no Rust drawer for this geom", NA))
})

test_that("non-raster devices draw ggplot2's points", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point(shape = 16)
  g <- hybrid_gtable(ggplot2::ggplot_build(p))
  file <- withr::local_tempfile(fileext = ".pdf")
  grDevices::pdf(file)
  grid::grid.draw(g)
  grDevices::dev.off()
  expect_gt(file.size(file), 0)
})

test_that("alot_png() writes a PNG and closes its device", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = c)) + ggplot2::geom_point(alpha = 0.5)
  file <- withr::local_tempfile(fileext = ".png")
  before <- grDevices::dev.cur()
  expect_no_warning(out <- alot_png(p, file, width = 400, height = 300, units = "px"))
  expect_equal(attr(out, "tier"), "hybrid")
  bytes <- readBin(file, "raw", 8)
  expect_equal(bytes, as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)))
  expect_equal(grDevices::dev.cur(), before)
})

test_that("alot_png() draws unsupported plots with ggplot2", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_line()
  file <- withr::local_tempfile(fileext = ".png")
  before <- grDevices::dev.cur()
  rlang::local_options(rlib_message_verbosity = "verbose")
  expect_message(out <- alot_png(p, file, width = 400, height = 300, units = "px"), "drawing with ggplot2")
  expect_equal(attr(out, "tier"), "ggplot2")
  expect_equal(png_size(file), c(400, 300))
  expect_equal(grDevices::dev.cur(), before)
})

test_that("an internal error in the hybrid tier warns and draws with ggplot2", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  file <- withr::local_tempfile(fileext = ".png")
  before <- grDevices::dev.cur()
  local_mocked_bindings(rs_render_points = function(...) stop("boom"))
  expect_warning(out <- alot_png(p, file, width = 400, height = 300, units = "px"), "boom")
  expect_equal(attr(out, "tier"), "ggplot2")
  expect_gt(file.size(file), 0)
  expect_equal(grDevices::dev.cur(), before)
})
