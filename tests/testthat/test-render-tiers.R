# Tier selection (R7.1, R/render.R): alot_render_coverage() reports the tier
# render_raster() draws with and why a plot isn't drawn in full; internal
# errors warn and drop a tier; a plot below the full tier gets a message
# (once per session). The hybrid tier's "marks" drawer draws the geoms the
# full tier draws that have no hybrid drawer of their own, and coord_flip()
# and coord_transform(), a panel at a time (draw_marks_layer()).

library(ggplot2)

marks_df <- data.frame(x = c(1, 2, 3, 4), y = c(2, 4, 3, 5), g = c("a", "a", "b", "b"))

test_that("layers without rows don't keep a plot out of the full tier", {
  withr::local_options(alot.full_tier = TRUE)
  df <- data.frame(x = 1:3, y = 3:1, z = c("a", "b", "c"))
  for (p in list(
    ggplot() + geom_point(aes(x, y), df) + geom_line() + facet_grid(. ~ z),
    ggplot(df, aes(x, y)) + geom_point() + geom_blank()
  )) {
    cov <- alot_render_coverage(p)
    expect_identical(cov$tier, "full")
    expect_identical(nrow(cov$full), 0L)
    expect_identical(attr(alot_png(p, withr::local_tempfile(fileext = ".png"), width = 2, height = 2, dpi = 72), "tier"), "full")
  }
})

test_that("alot_render_coverage() explains every plot not drawn in full", {
  withr::local_options(alot.full_tier = TRUE)
  p <- ggplot(marks_df, aes(x, y)) + geom_point() + labs(title = quote(alpha))
  cov <- alot_render_coverage(p)
  expect_identical(cov$tier, "hybrid")
  expect_gt(nrow(cov$full), 0)
  withr::local_options(alot.full_tier = FALSE)
  cov <- alot_render_coverage(ggplot(marks_df, aes(x, y)) + geom_point())
  expect_identical(cov$tier, "hybrid")
  expect_identical(cov$full$name, "alot.full_tier")
})

test_that("a plot below the full tier gets a message", {
  withr::local_options(alot.full_tier = TRUE, rlib_message_verbosity = "verbose")
  b <- ggplot_build(ggplot(marks_df, aes(x, y)) + geom_point() + labs(title = quote(alpha)))
  expect_message(out <- render_raster(b, render_size), class = "alot_render_below_full")
  expect_identical(out$tier, "hybrid")
  b <- ggplot_build(ggplot(marks_df, aes(x, y)) + geom_point())
  expect_no_message(out <- render_raster(b, render_size))
  expect_identical(out$tier, "full")
})

test_that("internal errors warn and drop a tier", {
  withr::local_options(alot.full_tier = TRUE, rlib_message_verbosity = "quiet")
  b <- ggplot_build(ggplot(marks_df, aes(x, y)) + geom_point())
  local({
    local_mocked_bindings(render_full = function(...) stop("boom"))
    expect_warning(out <- render_raster(b, render_size), "boom", class = "alot_render_fallback")
    expect_identical(out$tier, "hybrid")
    expect_false(is.null(out$raster))
  })
  local({
    local_mocked_bindings(render_full = function(...) stop("boom"), render_hybrid = function(...) stop("bang"))
    expect_warning(expect_warning(out <- render_raster(b, render_size), "boom"), "bang", class = "alot_render_fallback")
    expect_identical(out$tier, "ggplot2")
    expect_null(out$raster)
  })
})

test_that("the hybrid tier draws the full tier's geoms with the marks drawer", {
  set.seed(1)
  cases <- list(
    ribbon = ggplot(marks_df, aes(x, ymin = y - 1, ymax = y + 1, group = g)) + geom_ribbon(fill = "grey70", colour = "red"),
    area = ggplot(marks_df, aes(x, y, fill = g)) + geom_area(alpha = 0.5),
    density = ggplot(mpg, aes(hwy, fill = drv)) + geom_density(alpha = 0.4) + facet_wrap(~year),
    smooth = ggplot(mpg, aes(displ, hwy)) + geom_point() + geom_smooth(method = "loess", formula = y ~ x),
    boxplot = ggplot(mpg, aes(class, hwy)) + geom_boxplot(),
    violin = ggplot(mpg, aes(hwy, class)) + geom_violin(),
    ranges = ggplot(marks_df, aes(x, y, ymin = y - 1, ymax = y + 1)) + geom_crossbar() + geom_errorbar(colour = "blue") +
      geom_linerange(colour = "red") + geom_pointrange(),
    segments = ggplot(mtcars, aes(wt, mpg)) + geom_segment(aes(xend = wt + 0.5, yend = mpg)) + geom_hline(yintercept = 20) +
      geom_vline(xintercept = 3) + geom_abline(slope = 2, intercept = 10) + geom_rug(),
    flip = ggplot(mtcars, aes(wt, mpg)) + geom_point() + geom_line() + geom_col(alpha = 0.2) + coord_flip(),
    transform = ggplot(mtcars, aes(wt, mpg)) + geom_point() + coord_transform(x = "log10"),
    free = ggplot(mpg, aes(displ, hwy)) + geom_smooth(method = "lm", formula = y ~ x) + facet_wrap(~drv, scales = "free")
  )
  for (n in names(cases)) {
    b <- ggplot_build(cases[[n]])
    cov <- alot_render_coverage(b)
    expect_identical(cov$layers$engine, rep("rust", nrow(cov$layers)), label = n)
    expect_render_close(b, tier = "hybrid", label = n)
  }
})

test_that("the marks drawer declines what the full tier declines", {
  # Text and labels stay with ggplot2 in the hybrid tier.
  cov <- alot_render_coverage(ggplot(marks_df, aes(x, y, label = g)) + geom_label() + geom_text())
  expect_identical(cov$layers$engine, c("ggplot2", "ggplot2"))
  expect_match(cov$layers$reason, "text is drawn by ggplot2")
  # A ribbon whose fill varies along it (ggplot2 aborts or draws a gradient).
  cov <- alot_render_coverage(ggplot(marks_df, aes(x, ymin = y - 1, ymax = y + 1, fill = x)) + geom_ribbon())
  expect_identical(cov$layers$engine, "ggplot2")
  # coord_polar() and rugs with coord_flip().
  cov <- alot_render_coverage(ggplot(mpg, aes(class, hwy)) + geom_boxplot() + coord_polar())
  expect_identical(cov$layers$engine, "ggplot2")
  cov <- alot_render_coverage(ggplot(mtcars, aes(wt, mpg)) + geom_rug() + coord_flip())
  expect_identical(cov$layers$reason, "a rug with coord_flip()")
  # On a device the Rust drawers don't draw on, ggplot2's grob.
  b <- ggplot_build(ggplot(mpg, aes(class, hwy)) + geom_boxplot())
  file <- withr::local_tempfile(fileext = ".pdf")
  grDevices::pdf(file)
  expect_no_error(grid::grid.draw(hybrid_gtable(b)))
  grDevices::dev.off()
})
