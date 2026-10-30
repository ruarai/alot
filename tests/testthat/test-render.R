# The hybrid tier: point layers rasterised in Rust (R/render.R). Output
# is compared with ggplot2 drawn by ragg pixel by pixel with
# expect_render_close() (helper-render.R): rendering only has to look the
# same, so edge pixels may differ slightly (anti-aliasing, subpixel
# positions).

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
  expect_render_close(p, tier = "hybrid")
})

test_that("supported shapes render like ragg", {
  for (shape in c(0:4, 15:17, 19, 20)) {
    p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
      ggplot2::geom_point(shape = shape, size = 4, alpha = 0.5, colour = "steelblue")
    expect_true(uses_rust(p))
    expect_render_close(p, tier = "hybrid")
  }
})

test_that("mapped colour, shape, stroke, facets and log scales render like ragg", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x * 1000 + 1, y, colour = c, shape = s)) +
    ggplot2::geom_point(alpha = 0.3, stroke = 1.5) +
    ggplot2::scale_x_log10() +
    ggplot2::facet_wrap(~s)
  expect_true(uses_rust(p))
  expect_render_close(p, width = 600, height = 400, res = 150, tier = "hybrid")
})

test_that("infinite positions are squished to the panel edge", {
  p <- ggplot2::ggplot(data.frame(x = c(-Inf, 0.5, Inf), y = c(0.5, Inf, -Inf)), ggplot2::aes(x, y)) +
    ggplot2::geom_point(size = 5) +
    ggplot2::lims(x = c(0, 1), y = c(0, 1))
  expect_true(uses_rust(p))
  # Half of each point is clipped at the panel edge, which falls between
  # pixels; the edge pixels there differ more than elsewhere.
  expect_render_close(p, max = 64, tier = "hybrid")
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
    "x or y is AsIs" = ggplot2::ggplot(d[1, ]) + ggplot2::geom_point(ggplot2::aes(x = I(0.5), y = I(0.5))),
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

test_that("expect_render_close() passes close renders and fails on tier or fallback", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  expect_success(expect_render_close(p, tier = "hybrid"))
  expect_failure(expect_render_close(p, tier = "full"), "hybrid tier, not full")
  local_mocked_bindings(rs_render_points = function(...) stop("boom"))
  expect_failure(expect_render_close(p, tier = "hybrid"), "fallback warning")
})

test_that("expect_render_close() fails on misplaced marks and writes images", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  shifted <- ggplot2::ggplot_build(ggplot2::ggplot(d, ggplot2::aes(y, x)) + ggplot2::geom_point())
  local_mocked_bindings(render_raster = function(built, size) {
    list(tier = "hybrid", raster = render_hybrid(shifted, size))
  })
  msg <- tryCatch(expect_render_close(p, tier = "hybrid"), expectation_failure = conditionMessage)
  expect_match(msg, "Render differs")
  dir <- sub(".*Images: ", "", msg)
  expect_setequal(list.files(dir), c("reference.png", "result.png", "diff.png"))
})

test_that("layout_boxes() puts the panel where ragg draws its background", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point(alpha = 0) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
  for (size in list(render_size, list(width = 300, height = 250, units = "px", res = 150))) {
    b <- ggplot2::ggplot_build(p)
    boxes <- layout_boxes(b, size)
    panel <- boxes[boxes$name == "panel", ]
    expect_equal(nrow(panel), 1)
    # The fully grey92 pixels of the background lie within a pixel of the
    # panel box.
    img <- render_reference(b, size)
    ch <- raster_channels(img)
    grey <- matrix(colSums(ch[1:3, ] == 0xEB) == 3, nrow = size$height, byrow = TRUE)
    rows <- range(which(rowSums(grey) > 20))
    cols <- range(which(colSums(grey) > 20))
    found <- c(cols[1] - 1, rows[1] - 1, cols[2], rows[2])
    expect_lte(max(abs(found - unlist(panel[c("x0", "y0", "x1", "y1")]))), 1)
  }
})

test_that("expect_layout_close() compares boxes by name", {
  a <- data.frame(name = c("panel", "axis-l"), x0 = c(10, 0), y0 = c(5, 5), x1 = c(100, 10), y1 = c(80, 80))
  b <- a
  b$x0[1] <- 10.4
  expect_success(expect_layout_close(b, a))
  b$x0[1] <- 10.6
  expect_failure(expect_layout_close(b, a), "panel")
  expect_failure(expect_layout_close(b[2, ], a), "Missing boxes: panel")
})
