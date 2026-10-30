# The hybrid tier: point layers rasterised in Rust (R/render.R). Output
# is compared with ggplot2 drawn by ragg pixel by pixel with
# expect_render_close() (helper-render.R): rendering only has to look the
# same, so edge pixels may differ slightly (anti-aliasing, subpixel
# positions).

# Header fields of a PNG: width, height, colour type (2 RGB, 6 RGBA), the
# pHYs chunk's pixels per unit (x, y) and unit (NULL if absent), the bKGD
# chunk's bytes, and the order of the chunks other than image data.
png_info <- function(file) {
  bytes <- readBin(file, "raw", file.size(file))
  stopifnot(identical(bytes[1:8], as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))))
  int <- function(at) readBin(bytes[at:(at + 3)], "integer", endian = "big")
  out <- list(phys = NULL, bkgd = NULL, chunks = character())
  at <- 9
  while (at < length(bytes)) {
    len <- int(at)
    type <- rawToChar(bytes[(at + 4):(at + 7)])
    data <- at + 8
    if (type == "IHDR") {
      out$width <- int(data)
      out$height <- int(data + 4)
      out$colour_type <- as.integer(bytes[data + 9])
    }
    if (type == "pHYs") out$phys <- c(int(data), int(data + 4), as.integer(bytes[data + 8]))
    if (type == "bKGD") out$bkgd <- as.integer(bytes[data:(data + len - 1)])
    if (!type %in% c("IDAT", "IEND")) out$chunks <- c(out$chunks, type)
    if (type == "IEND") break
    at <- data + len + 4
  }
  out
}

png_size <- function(file) {
  info <- png_info(file)
  c(info$width, info$height)
}

panel_children <- function(g) {
  g$grobs[[grep("^panel", g$layout$name)[1]]]$children
}

# Whether the hybrid gtable draws the plot's points in Rust; checks that
# alot_render_coverage() agrees.
uses_rust <- function(p) {
  b <- ggplot2::ggplot_build(p)
  rust <- any(vapply(panel_children(hybrid_gtable(b)), inherits, logical(1), "alot_hybrid_layer"))
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

test_that("every shape renders like ragg at several sizes, strokes, alphas and dpis", {
  combos <- list(
    list(size = 1.5, stroke = 0.5, alpha = 1, res = 96, fill = NA),
    list(size = 4, stroke = 1, alpha = 0.5, res = 150, fill = "orange"),
    list(size = 8, stroke = 2, alpha = 0.7, res = 72, fill = "#3366CC"),
    list(size = 3, stroke = 0, alpha = 1, res = 300, fill = "orange")
  )
  for (shape in 0:25) {
    for (k in combos) {
      p <- ggplot2::ggplot(d[1:60, ], ggplot2::aes(x, y)) +
        ggplot2::geom_point(
          shape = shape, size = k$size, stroke = k$stroke, alpha = k$alpha,
          colour = "steelblue4", fill = k$fill
        )
      expect_true(uses_rust(p))
      expect_render_close(p, res = k$res, tier = "hybrid", label = sprintf("shape %d, size %g, stroke %g, %g dpi", shape, k$size, k$stroke, k$res))
    }
  }
})

test_that("mapped size, shape names and fill render like ragg", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, size = c, fill = s)) +
    ggplot2::geom_point(shape = "circle filled", alpha = 0.6)
  expect_true(uses_rust(p))
  expect_render_close(p, tier = "hybrid")
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, shape = s)) +
    ggplot2::geom_point(colour = "grey20", fill = "red", size = 3, stroke = 0) +
    ggplot2::scale_shape_manual(values = 21:24)
  expect_true(uses_rust(p))
  expect_render_close(p, tier = "hybrid")
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
    "unsupported shape" = base + ggplot2::geom_point(shape = 30),
    "character pch" = base + ggplot2::geom_point(shape = "a"),
    "clip is not \"on\"" = base + ggplot2::geom_point() + ggplot2::coord_cartesian(clip = "off"),
    "coord is not an unreversed coord_cartesian()" = base + ggplot2::geom_point() + ggplot2::coord_flip(),
    "NA in stroke" = base + ggplot2::geom_point(stroke = NA),
    "position scale does not rescale linearly" =
      base + ggplot2::geom_point() + ggplot2::continuous_scale(
        "x", palette = identity, guide = "axis", position = "bottom", super = ggplot2::ScaleContinuousPosition,
        rescaler = function(x, to = c(0, 1), from = range(x)) scales::rescale(x, to, from)
      ),
    "no rows" = ggplot2::ggplot(d[0, ], ggplot2::aes(x, y)) + ggplot2::geom_point(),
    "x or y is AsIs" = ggplot2::ggplot(d[1, ]) + ggplot2::geom_point(ggplot2::aes(x = I(0.5), y = I(0.5))),
    "no Rust drawer for this geom" = base + ggplot2::geom_step()
  )
  for (reason in names(cases)) {
    p <- cases[[reason]]
    expect_false(uses_rust(p))
    expect_equal(alot_render_coverage(p)$layers$reason, reason)
  }
})

test_that("rows with missing values are removed as ggplot2 does", {
  na <- d
  na$y[1:3] <- NA
  p <- ggplot2::ggplot(na, ggplot2::aes(x, y)) + ggplot2::geom_point(size = 3)
  expect_true(suppressWarnings(uses_rust(p)))
  b <- ggplot2::ggplot_build(p)
  # alot warns as ggplot2 does; the reference drawing warns too.
  expect_warning(render_raster(b, render_size), "Removed 3 rows")
  suppressWarnings(expect_render_close(b, tier = "hybrid"))
})

test_that("alot_render_coverage() reports each layer", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_step() + ggplot2::geom_point()
  cov <- alot_render_coverage(p)
  expect_equal(cov$tier, "hybrid")
  expect_equal(cov$layers$geom, c("GeomStep", "GeomPoint"))
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
  expect_no_warning(out <- alot_png(p, file, width = 400, height = 300, units = "px", dpi = 96))
  expect_equal(attr(out, "tier"), "hybrid")
  bytes <- readBin(file, "raw", 8)
  expect_equal(bytes, as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)))
  expect_equal(grDevices::dev.cur(), before)
})

test_that("alot_png() draws unsupported plots with ggplot2", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_step()
  file <- withr::local_tempfile(fileext = ".png")
  before <- grDevices::dev.cur()
  rlang::local_options(rlib_message_verbosity = "verbose")
  expect_message(out <- alot_png(p, file, width = 400, height = 300, units = "px", dpi = 96), "drawing with ggplot2")
  expect_equal(attr(out, "tier"), "ggplot2")
  expect_equal(png_size(file), c(400, 300))
  expect_equal(grDevices::dev.cur(), before)
})

test_that("an internal error in the hybrid tier warns and draws with ggplot2", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  file <- withr::local_tempfile(fileext = ".png")
  before <- grDevices::dev.cur()
  local_mocked_bindings(rs_render_points = function(...) stop("boom"))
  expect_warning(out <- alot_png(p, file, width = 400, height = 300, units = "px", dpi = 96), "boom")
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

# alot_png() / alot_ggsave() (R0.4) against ggsave() with ragg.

ggsave_ragg <- function(file, plot, ...) {
  ggplot2::ggsave(file, plot, device = ragg::agg_png, ...)
}

test_that("alot_png() defaults to ggsave()'s 7 x 7 in at 300 dpi", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  file <- withr::local_tempfile(fileext = ".png")
  expect_no_warning(alot_png(p, file))
  info <- png_info(file)
  expect_equal(c(info$width, info$height), c(2100, 2100))
  expect_equal(info$phys, c(11811L, 11811L, 1L))
  expect_equal(info$colour_type, 2L)
})

test_that("alot_ggsave() matches ggsave() with ragg for PNGs", {
  points <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  lines <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_line()
  cases <- list(
    list(plot = points, width = 4, height = 3),
    list(plot = points, width = 10, height = 6, units = "cm", dpi = 150),
    list(plot = points, width = 80, height = 60, units = "mm", dpi = "screen", scale = 1.5),
    list(plot = points, width = 640, height = 480, units = "px", dpi = 72),
    list(plot = points, width = 3, height = 2, dpi = "retina", bg = "transparent"),
    list(plot = points, width = 3, height = 2, dpi = 100, bg = "#33669980"),
    list(plot = points + ggplot2::theme(plot.background = ggplot2::element_rect(fill = NA)), width = 3, height = 2, dpi = 100),
    list(plot = lines, width = 3, height = 2, dpi = 120)
  )
  for (args in cases) {
    ref <- withr::local_tempfile(fileext = ".png")
    out <- withr::local_tempfile(fileext = ".png")
    suppressMessages(do.call(ggsave_ragg, c(list(ref), args)))
    res <- suppressMessages(do.call(alot_ggsave, c(list(out), args)))
    expect_equal(res, out, ignore_attr = TRUE)
    expect_equal(png_info(out), png_info(ref))
  }
})

test_that("alot_ggsave() draws PNGs with alot and passes other files to ggsave()", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  dir <- withr::local_tempdir()
  out <- alot_ggsave("plot.PNG", p, path = dir, width = 3, height = 2, dpi = 72)
  expect_equal(attr(out, "tier"), "hybrid")
  expect_equal(png_size(file.path(dir, "plot.PNG")), c(216, 144))
  out <- alot_ggsave(file.path(dir, "plot.dat"), p, device = "png", width = 3, height = 2, dpi = 72)
  expect_equal(attr(out, "tier"), "hybrid")
  pdf <- file.path(dir, "plot.pdf")
  out <- alot_ggsave(pdf, p, width = 3, height = 2)
  expect_null(attr(out, "tier"))
  expect_equal(readBin(pdf, "raw", 4), charToRaw("%PDF"))
  out <- alot_ggsave(file.path(dir, "fn.png"), p, device = ragg::agg_png, width = 3, height = 2, dpi = 72)
  expect_null(attr(out, "tier"))
  expect_equal(png_size(file.path(dir, "fn.png")), c(216, 144))
})

test_that("alot_ggsave() reports the default size and checks limitsize like ggsave()", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  file <- withr::local_tempfile(fileext = ".png")
  expect_message(alot_ggsave(file, p, dpi = 30), "Saving 7 x 7 in image")
  expect_error(alot_ggsave(file, p, width = 60, height = 2), "exceed 50 inches")
})

test_that("alot_png() restores the current device", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_point()
  pdf_file <- withr::local_tempfile(fileext = ".pdf")
  grDevices::pdf(pdf_file)
  dev <- grDevices::dev.cur()
  grDevices::pdf(withr::local_tempfile(fileext = ".pdf"))
  grDevices::dev.set(dev)
  withr::defer(grDevices::graphics.off())
  alot_png(p, withr::local_tempfile(fileext = ".png"), width = 2, height = 2, dpi = 50)
  expect_equal(grDevices::dev.cur(), dev)
  suppressMessages(alot_png(ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_step(),
    withr::local_tempfile(fileext = ".png"), width = 2, height = 2, dpi = 50))
  expect_equal(grDevices::dev.cur(), dev)
})

test_that("render_threads() follows alot.threads, ALOT_THREADS and the check limit", {
  withr::local_options(alot.threads = NULL)
  withr::local_envvar(ALOT_THREADS = "", "_R_CHECK_LIMIT_CORES_" = "")
  expect_equal(render_threads(), 0L)
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "TRUE")
  expect_equal(render_threads(), 2L)
  withr::local_envvar(ALOT_THREADS = "3")
  expect_equal(render_threads(), 3L)
  withr::local_options(alot.threads = 5)
  expect_equal(render_threads(), 5L)
  withr::local_options(alot.threads = 0)
  expect_error(render_threads(), "positive integer")
})

test_that("the thread count doesn't change the hybrid's pixels", {
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = c)) + ggplot2::geom_point(size = 3, alpha = 0.4)
  b <- ggplot2::ggplot_build(p)
  draw <- function(threads) {
    withr::local_options(alot.threads = threads)
    render_raster(b, render_size)$raster
  }
  expect_identical(draw(1), draw(8))
  expect_render_close(b, tier = "hybrid")
})

# Rect layers (R1.3): GeomRect's draw_panel, inherited by GeomTile, GeomBar
# and GeomCol.

test_that("tiles, bars and rects render like ragg", {
  set.seed(2)
  tiles <- expand.grid(x = 1:25, y = 1:15)
  tiles$z <- runif(nrow(tiles))
  tiles$z[3] <- NA
  plots <- list(
    ggplot2::ggplot(tiles, ggplot2::aes(x, y, fill = z)) + ggplot2::geom_tile(),
    ggplot2::ggplot(tiles, ggplot2::aes(x, y, fill = z)) + ggplot2::geom_tile(alpha = 0.5, width = 0.7, height = 0.6),
    ggplot2::ggplot(tiles, ggplot2::aes(x, y, fill = z)) + ggplot2::geom_tile(colour = "white", linewidth = 0.8),
    ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), fill = factor(gear))) + ggplot2::geom_bar(),
    ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), fill = factor(gear))) +
      ggplot2::geom_bar(position = "dodge", colour = "black") + ggplot2::facet_wrap(~am),
    ggplot2::ggplot(mtcars, ggplot2::aes(mpg)) + ggplot2::geom_histogram(bins = 12, colour = "grey30", fill = NA),
    ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) + ggplot2::geom_col(linewidth = 2, colour = "blue", linejoin = "round"),
    ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl), mpg)) + ggplot2::geom_col(linewidth = 2, colour = "blue", linejoin = "bevel", alpha = 0.4),
    ggplot2::ggplot(d, ggplot2::aes(x, y)) +
      ggplot2::annotate("rect", xmin = -Inf, xmax = 0.4, ymin = 0.2, ymax = Inf, fill = "red", alpha = 0.3) +
      ggplot2::geom_rect(ggplot2::aes(xmin = x, xmax = x + 0.05, ymin = y, ymax = y + 0.03), data = d[1:20, ], linewidth = 0.3, colour = "black")
  )
  for (i in seq_along(plots)) {
    p <- plots[[i]]
    expect_true(all(alot_render_coverage(p)$layers$engine == "rust"))
    expect_render_close(p, tier = "hybrid", label = paste("plot", i))
    expect_render_close(p, width = 300, height = 250, res = 150, tier = "hybrid", label = paste("plot", i, "at 150 dpi"))
  }
})

test_that("a 1000 x 1000 geom_tile renders like ragg", {
  set.seed(42)
  tiles <- expand.grid(x = 1:1000, y = 1:1000)
  tiles$z <- runif(nrow(tiles))
  p <- ggplot2::ggplot(tiles, ggplot2::aes(x, y, fill = z)) + ggplot2::geom_tile() +
    ggplot2::theme_void() + ggplot2::theme(legend.position = "none")
  expect_render_close(p, width = 600, height = 400, res = 96, tier = "hybrid")
})

test_that("unsupported rect layers keep ggplot2's rectGrob, with a reason", {
  base <- ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl)))
  cases <- list(
    "linetype is not solid or blank" = base + ggplot2::geom_bar(colour = "black", linetype = "dashed"),
    "coord is not an unreversed coord_cartesian()" = base + ggplot2::geom_bar() + ggplot2::coord_flip(),
    "clip is not \"on\"" = base + ggplot2::geom_bar() + ggplot2::coord_cartesian(clip = "off"),
    "no Rust drawer for this geom" = ggplot2::ggplot(ggplot2::faithfuld, ggplot2::aes(waiting, eruptions, fill = density)) + ggplot2::geom_raster()
  )
  for (reason in names(cases)) {
    p <- cases[[reason]]
    expect_equal(alot_render_coverage(p)$layers$reason, reason)
    expect_false(any(vapply(panel_children(hybrid_gtable(ggplot2::ggplot_build(p))), inherits, logical(1), "alot_hybrid_layer")))
  }
})

test_that("blank line types draw no outline", {
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(factor(cyl))) + ggplot2::geom_bar(colour = "black", linetype = "blank")
  expect_equal(alot_render_coverage(p)$layers$engine, "rust")
  expect_render_close(p, tier = "hybrid")
})

# Path and polygon layers (R1.4): GeomPath's draw_panel (GeomLine) and
# GeomPolygon's.

test_that("lines, dashes and polygons render like ragg at several widths", {
  ec <- ggplot2::economics_long
  plots <- list()
  for (lw in c(0.25, 0.5, 1.5, 3)) {
    plots <- c(plots, list(
      ggplot2::ggplot(ec, ggplot2::aes(date, value01, colour = variable)) + ggplot2::geom_line(linewidth = lw),
      ggplot2::ggplot(ec, ggplot2::aes(date, value01, linetype = variable)) + ggplot2::geom_line(linewidth = lw),
      ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
        ggplot2::geom_path(linewidth = lw, lineend = "round", linejoin = "mitre", linetype = "1343", alpha = 0.6)
    ))
  }
  tri <- data.frame(x = c(1, 3, 2, 2.2, 4, 3), y = c(1, 1, 3, 1.5, 1.5, 3.5), g = rep(1:2, each = 3))
  plots <- c(plots, list(
    ggplot2::ggplot(tri, ggplot2::aes(x, y, group = g, fill = factor(g))) +
      ggplot2::geom_polygon(colour = "black", linewidth = 1, alpha = 0.6),
    ggplot2::ggplot(tri, ggplot2::aes(x, y, group = g)) +
      ggplot2::geom_polygon(fill = NA, colour = "red", linewidth = 2, linetype = "dashed", linejoin = "mitre")
  ))
  for (i in seq_along(plots)) {
    p <- plots[[i]]
    expect_true(all(alot_render_coverage(p)$layers$engine == "rust"))
    expect_render_close(p, tier = "hybrid", label = paste("plot", i))
    expect_render_close(p, width = 300, height = 250, res = 150, tier = "hybrid", label = paste("plot", i, "at 150 dpi"))
  }
})

test_that("missing values break lines as grid does", {
  d <- data.frame(x = 1:20, y = sin(1:20))
  d$y[c(5, 12, 13)] <- NA
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) + ggplot2::geom_path(linewidth = 1)
  expect_equal(alot_render_coverage(p)$layers$engine, "rust")
  expect_render_close(p, tier = "hybrid")
})

test_that("polygons with holes follow the fill rule", {
  holes <- data.frame(
    x = c(0, 4, 4, 0, 1, 3, 3, 1, 6, 9, 9, 6),
    y = c(0, 0, 4, 4, 1, 1, 3, 3, 0, 0, 3, 3),
    g = rep(c(1, 1, 2), each = 4), s = rep(1:3, each = 4)
  )
  for (rule in c("evenodd", "winding")) {
    p <- ggplot2::ggplot(holes, ggplot2::aes(x, y, group = g, subgroup = s)) +
      ggplot2::geom_polygon(rule = rule, fill = "steelblue", colour = "black")
    expect_equal(alot_render_coverage(p)$layers$engine, "rust")
    expect_render_close(p, tier = "hybrid")
  }
})

test_that("unsupported path layers keep ggplot2's grobs, with a reason", {
  base <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg))
  na <- data.frame(x = c(1, 2, NA, 1), y = c(1, 2, 1, 3))
  cases <- list(
    "arrows" = base + ggplot2::geom_path(arrow = grid::arrow()),
    "aesthetics vary along a line" = base + ggplot2::geom_path(ggplot2::aes(colour = hp)),
    "coord is not an unreversed coord_cartesian()" = base + ggplot2::geom_line() + ggplot2::coord_flip(),
    "NA in x or y" = ggplot2::ggplot(na, ggplot2::aes(x, y)) + ggplot2::geom_polygon(),
    "no Rust drawer for this geom" = base + ggplot2::geom_step()
  )
  for (reason in names(cases)) {
    p <- cases[[reason]]
    expect_equal(alot_render_coverage(p)$layers$reason, reason)
  }
})

test_that("lty_code() gives the graphics engine's line type codes", {
  expect_equal(lty_code(c("solid", "dashed", "dotdash", "1F", "blank", NA)), c(0, 0x44, 0x3431, 0xF1, -1, -1))
  expect_equal(lty_code(0:6), c(-1, 0, 0x44, 0x31, 0x3431, 0x37, 0x2622))
  expect_null(lty_code("0F"))
  expect_null(lty_code(7))
})
