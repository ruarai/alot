# The render IR (R/render-ir.R): theme resolution, extraction and the full
# tier's support decisions.

ir_plot <- function() {
  ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy, colour = cty, shape = drv)) +
    ggplot2::geom_point() +
    ggplot2::facet_wrap(~year) +
    ggplot2::labs(title = "Title", caption = "Caption")
}

ir_reasons <- function(p) render_ir(alot_build(p))$support$reason

test_that("theme elements resolve as calc_element() does", {
  tree <- names(ggplot2::get_element_tree())
  themes <- list(
    ggplot2::theme_grey(), ggplot2::theme_bw(), ggplot2::theme_classic(),
    ggplot2::theme_void(), ggplot2::theme_minimal(), ggplot2::theme_dark(),
    ggplot2::theme_light(), ggplot2::theme_linedraw(),
    ggplot2::theme_grey(base_size = 16, base_family = "serif") + ggplot2::theme(
      axis.text = ggplot2::element_text(colour = "red", size = ggplot2::rel(2)),
      axis.line = ggplot2::element_line(linewidth = ggplot2::rel(3)),
      panel.grid.minor = ggplot2::element_blank(),
      axis.title.x = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(margin = ggplot2::margin(1, NA, 2, NA)),
      legend.key.size = grid::unit(2, "cm"),
      axis.ticks.length = grid::unit(1, "npc") - grid::unit(2, "pt")
    ),
    ggplot2::theme_bw() + ggplot2::theme(
      text = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(inherit.blank = TRUE),
      axis.text = ggplot2::element_blank()
    )
  )
  for (t in themes) {
    theme <- alot_build(ir_plot() + t)@plot@theme
    want <- stats::setNames(lapply(tree, function(n) as_element(ggplot2::calc_element(n, theme))), tree)
    expect_identical(resolve_theme(theme), want)
  }
})

test_that("the IR holds what the layout and drawers need", {
  b <- alot_build(ir_plot())
  ir <- render_ir(b)
  expect_identical(nrow(ir$support), 0L)
  expect_identical(ir$theme$axis.text.x$.class, "ggplot2::element_text")
  expect_identical(ir$theme$axis.text.x$size, 8.8)
  expect_identical(ir$labels$title, "Title")
  expect_identical(ir$labels$x, "displ")
  expect_null(ir$labels$subtitle)
  # Two fixed-scale panels share one set of panel params.
  expect_identical(ir$layout$scales, c(1L, 1L))
  expect_length(ir$scales, 1)
  expect_identical(ir$scales[[1]]$x.range, b@layout$panel_params[[1]]$x.range)
  expect_identical(ir$scales[[1]]$x$major, b@layout$panel_params[[1]]$x$break_positions())
  expect_setequal(vapply(ir$scales[[1]]$axes, `[[`, "", "position"), c("bottom", "left"))
  expect_identical(ir$strips$facets$year, c("1999", "2008"))
  expect_identical(vapply(ir$legends, `[[`, "", "class"), c("GuideColourbar", "GuideLegend"))
  expect_identical(ir$layers[[1]]$kind, "points")
  expect_identical(ir$fonts$face, 1L)
  expect_identical(ir$fonts$path, systemfonts::match_fonts("")$path)
  expect_identical(ir$facet$class, "FacetWrap")
  expect_identical(ir$coord$class, "CoordCartesian")
})

test_that("free scales give each panel its own params", {
  b <- alot_build(ir_plot() + ggplot2::facet_wrap(~year, scales = "free"))
  ir <- render_ir(b)
  expect_identical(ir$layout$scales, c(1L, 2L))
  expect_identical(ir$scales[[2]]$y.range, b@layout$panel_params[[2]]$y.range)
})

test_that("unsupported parts give reasons", {
  base <- ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy)) + ggplot2::geom_point()
  expect_match(ir_reasons(base + ggplot2::coord_polar()), "coord not in Phase 2 scope", all = FALSE)
  expect_match(ir_reasons(base + ggplot2::labs(title = quote(alpha^2))), "plotmath", all = FALSE)
  expect_match(ir_reasons(base + ggplot2::labs(title = "排気量")), "glyph missing", all = FALSE)
  expect_match(ir_reasons(base + ggplot2::geom_area()), "no Rust drawer", all = FALSE)
  expect_match(
    ir_reasons(base + ggplot2::guides(x = ggplot2::guide_axis_logticks())),
    "axis guide not in Phase 2 scope", all = FALSE
  )
  expect_match(
    ir_reasons(base + ggplot2::facet_wrap(~drv, labeller = ggplot2::label_bquote(alpha == .(drv)))),
    "plotmath", all = FALSE
  )
  custom <- ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy, colour = drv)) +
    ggplot2::geom_point(key_glyph = function(data, params, size) grid::nullGrob())
  expect_match(ir_reasons(custom), "legend key", all = FALSE)
  expect_match(ir_reasons(base + ggplot2::theme(axis.ticks.length = grid::unit(1, "npc") - grid::unit(2, "pt"))), "compound unit")
})

test_that("alot_render_coverage() reports the full tier's reasons", {
  cov <- alot_render_coverage(ir_plot())
  expect_identical(nrow(cov$full), 0L)
  cov <- alot_render_coverage(ir_plot() + ggplot2::coord_polar())
  expect_true("coord" %in% cov$full$component)
})

test_that("text fonts resolve once per style", {
  f <- text_fonts(c("sans", "serif", "sans", NA), c(1, 2, 1, 1))
  expect_identical(f$path[1], f$path[3])
  expect_true(is.na(f$path[4]))
})

test_that("alot_render_coverage() reports the tier alot_png() would use", {
  base <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  withr::local_options(alot.full_tier = TRUE)
  cov <- alot_render_coverage(base + ggplot2::aes(colour = qsec) + ggplot2::facet_wrap(~cyl))
  expect_identical(cov$tier, "full")
  expect_identical(nrow(cov$full), 0L)
  # Reasons from the page layout are reported too.
  cov <- alot_render_coverage(base + ggplot2::facet_wrap(~cyl, scales = "free"))
  expect_identical(cov$tier, "hybrid")
  expect_identical(cov$full$reason, "free scales")
  cov <- alot_render_coverage(base + ggplot2::theme(legend.position = "inside") + ggplot2::aes(colour = qsec))
  expect_identical(cov$tier, "hybrid")
  cov <- alot_render_coverage(ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_area())
  expect_identical(cov$tier, "ggplot2")
  # What alot_png() uses.
  b <- ggplot2::ggplot_build(base)
  expect_identical(alot_render_coverage(b)$tier, render_raster(b, render_size)$tier)
  withr::local_options(alot.full_tier = FALSE)
  expect_identical(alot_render_coverage(b)$tier, "hybrid")
})
