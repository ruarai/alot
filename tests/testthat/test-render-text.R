# String metrics (R/render-text.R, alot-core/src/render/text.rs), compared
# with grid's stringWidth(), stringHeight() and string ascent/descent units
# on a ragg device.

# grid's metrics of `text` in device pixels on a ragg device at `res` and
# `scaling`, with gpar() settings `gp`: a data frame like text_metrics().
grid_metrics <- function(text, gp, res, scaling = 1) {
  ragg::agg_capture(width = 400, height = 400, res = res, scaling = scaling)
  on.exit(grDevices::dev.off())
  grid::pushViewport(grid::viewport(gp = gp))
  px <- res * scaling
  m <- function(unit, conv) {
    vapply(text, function(s) conv(grid::unit(1, unit, s), "in", TRUE) * px, 0, USE.NAMES = FALSE)
  }
  data.frame(
    width = m("strwidth", grid::convertWidth),
    ascent = m("strascent", grid::convertHeight),
    descent = m("strdescent", grid::convertHeight),
    height = m("strheight", grid::convertHeight)
  )
}

text_strings <- c(
  "Hello", "hwy", "Fuel economy (mpg)", "AVAVA To WA", "gjpqyQ", "0.25",
  "-12.5%", "Ünïcödé façade", " ", "a b", "", "Two\nlines", "\nlead",
  "trail\n", "x\ny\nz"
)

test_that("metrics match grid on ragg across fonts, faces, sizes and dpis", {
  skip_if_not(nzchar(systemfonts::match_fonts("sans")$path))
  for (res in c(72, 150, 300)) {
    for (family in c("", "sans", "serif", "mono")) {
      for (face in 1:4) {
        for (fontsize in c(5.5, 8.8, 11, 13.2, 22)) {
          lh <- if (face %% 2) 0.9 else 1.2
          gp <- grid::gpar(fontfamily = family, fontface = face, fontsize = fontsize, lineheight = lh)
          ref <- grid_metrics(text_strings, gp, res)
          got <- text_metrics(text_strings, family, face, fontsize, lineheight = lh, res = res)
          label <- sprintf("%s/%d/%g pt/%g dpi", family, face, fontsize, res)
          expect_lte(max(abs(got$width - ref$width)), 0.25, label = label)
          expect_equal(got[c("ascent", "descent", "height")], ref[c("ascent", "descent", "height")], label = label)
        }
      }
    }
  }
})

test_that("metrics follow cex and the device's scaling", {
  gp <- grid::gpar(fontsize = 9.6, cex = 1.5, lineheight = 1.1)
  ref <- grid_metrics(text_strings, gp, res = 96, scaling = 2)
  got <- text_metrics(text_strings, fontsize = 9.6, cex = 1.5, lineheight = 1.1, res = 96, scaling = 2)
  expect_lte(max(abs(got$width - ref$width)), 0.25)
  expect_equal(got[c("ascent", "descent", "height")], ref[c("ascent", "descent", "height")])
})

test_that("widths are textshaping's exactly", {
  gp <- grid::gpar(fontsize = 13.2)
  ref <- grid_metrics(text_strings, gp, res = 72)
  got <- text_metrics(text_strings, fontsize = 13.2, res = 72)
  expect_equal(got$width, ref$width)
})

test_that("missing glyphs, the symbol face and NA need ragg", {
  m <- text_metrics(c("漢字", "label 🦀", "ok", NA), face = c(1, 1, 5, 1))
  expect_true(all(is.na(m$width)))
  expect_identical(text_tier(c("Displacement", "hwy")), "full")
  expect_identical(text_tier(c("Displacement", "排気量")), "hybrid")
  expect_identical(text_tier(c("Displacement", "🦀")), "hybrid")
  expect_identical(text_tier(c("a", NA)), "full")
  expect_identical(text_tier("a", face = 5L), "hybrid")
})

test_that("fonts resolve once per style as ragg does", {
  f <- text_fonts(c("sans", "serif", "sans", "mono"), c(1, 2, 1, 5))
  expect_identical(f$path[1], f$path[3])
  expect_identical(f$path[2], systemfonts::match_fonts("serif", weight = "bold")$path)
  expect_true(is.na(f$path[4]))
})
