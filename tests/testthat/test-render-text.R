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

# Glyph drawing (R2.2): with options(alot.hybrid_text = TRUE) the hybrid tier draws the gtable's text grobs in
# Rust, mirroring ragg's hinted glyph cache, so text matches ragg pixel
# for pixel at the default tolerance.
test_that("axis labels, rotated and multi-line titles render like ragg", {
  withr::local_options(alot.hybrid_text = TRUE)
  base <- ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy, colour = class)) + ggplot2::geom_point()
  plots <- list(
    titles = base + ggplot2::facet_wrap(~drv) + ggplot2::labs(
      title = "Fuel economy\nby engine size", subtitle = "Two lines\nof subtitle",
      caption = "Source: EPA", y = "Highway\nmpg", tag = "A"
    ),
    angled = ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(class, hwy)) + ggplot2::geom_point() +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 30, vjust = 0.5),
        axis.text.y = ggplot2::element_text(angle = 45, hjust = 1),
        axis.title.y = ggplot2::element_text(angle = 0)
      ),
    strips = base + ggplot2::facet_grid(drv ~ cyl) +
      ggplot2::theme_bw(base_family = "serif", base_size = 14) +
      ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"), legend.position = "bottom") +
      ggplot2::labs(title = "Bold serif"),
    mono = base + ggplot2::theme_classic(base_family = "mono") + ggplot2::labs(x = "x\ny\nz")
  )
  for (nm in names(plots)) {
    for (res in c(96, 300)) {
      expect_render_close(
        plots[[nm]], width = 1000 * res / 150, height = 700 * res / 150, res = res,
        tier = "hybrid", label = paste(nm, res)
      )
    }
  }
})

test_that("text alot doesn't mirror falls back to grid", {
  withr::local_options(alot.hybrid_text = TRUE)
  p <- ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy)) + ggplot2::geom_point() +
    ggplot2::labs(title = quote(alpha^2), x = "排気量")
  expect_render_close(p, tier = "hybrid")
  g <- hybrid_text(grid::gTree(children = grid::gList(grid::textGrob("a"), grid::rectGrob())))
  expect_s3_class(g$children[[1]], "alot_text")
  expect_false(inherits(g$children[[2]], "alot_text"))
})
