# Panel decorations and axes in the full tier (R4.2): plots of blank layers
# drawn by alot-core's page drawers (R/render-full.R) against ggplot2 on
# ragg, and their layout against grid's. Layers aren't drawn in the full
# tier until R5, so the plots have none (geom_blank(); points are in test-render-points.R).

skip_on_cran()
library(ggplot2)

local_full_tier <- function(env = parent.frame()) {
  withr::local_options(alot.full_tier = TRUE, .local_envir = env)
}

base <- ggplot(mtcars, aes(wt, mpg)) + geom_blank()
disc <- ggplot(
  data.frame(x = c("alpha long label", "beta", "gamma", "delta", "epsilon zeta", "eta", "theta"), y = 1:7),
  aes(x, y)
) + geom_blank()

# The image and the layout check at one resolution. Plots alternate between
# resolutions in a session only in "a higher resolution" below: ragg's own
# text occasionally comes out differently on a fresh device after a change
# of resolution (see expect_render_close()).
check_page <- function(p, label, ..., max = 32, size = list()) {
  local_full_tier()
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-panel.R", label, b)
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key)))
  expect_null(expect_layout_matches(b, utils::modifyList(render_size, size), label = label, cache_key = key))
}

test_that("theme_grey() draws the background, grid lines, axes and titles as ggplot2 does", {
  check_page(base, "theme_grey")
  check_page(base + labs(title = "A title", subtitle = "A subtitle\non two lines", caption = "A caption", tag = "A"), "titles")
  check_page(base + labs(x = NULL, y = NULL), "no axis titles")
  check_page(base + labs(x = "Weight\n(1000 lbs)", y = "Miles per gallon, gross"), "multi-line axis titles")
})

test_that("every complete theme draws as ggplot2 does", {
  for (theme in c("bw", "classic", "minimal", "void", "dark", "light", "linedraw", "grey")) {
    check_page(base + get(paste0("theme_", theme))(), paste("theme", theme))
  }
  check_page(base + theme_grey(base_size = 20, base_family = "serif") + labs(title = "Serif"), "serif")
})

test_that("axes at every position, with sizes, angles, dodging and lines", {
  check_page(base + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"), "top and right")
  check_page(
    base + scale_x_continuous(sec.axis = dup_axis(name = "Second")) + scale_y_continuous(sec.axis = dup_axis()),
    "secondary axes"
  )
  check_page(base + guides(x = guide_axis(angle = 45), y = guide_axis(angle = 90)), "angle")
  check_page(base + guides(x = guide_axis(n.dodge = 2), y = guide_axis(n.dodge = 2)), "n.dodge")
  check_page(
    base + guides(x = guide_axis(minor.ticks = TRUE), y = guide_axis(minor.ticks = TRUE)) +
      theme(axis.minor.ticks.length = rel(0.5)),
    "minor ticks"
  )
  check_page(base + theme(axis.line = element_line(colour = "red", linewidth = 1)), "axis line")
  check_page(
    base + scale_x_continuous(position = "top") + scale_y_continuous(position = "right") +
      theme(axis.line = element_line(colour = "red", linewidth = 1)),
    "axis line, top and right"
  )
  check_page(base + theme(axis.ticks.length = unit(-0.3, "cm")), "negative tick length")
  check_page(base + theme(axis.ticks.length = unit(0.5, "cm"), axis.ticks = element_line(colour = "blue")), "long ticks")
  check_page(base + theme(axis.text = element_text(size = 20, margin = margin(10, 10, 10, 10))), "large labels")
  check_page(base + theme(axis.text.x = element_blank(), axis.ticks = element_blank()), "blank labels and ticks")
  check_page(base + theme(axis.title.y = element_text(angle = 0)), "horizontal y title")
  check_page(base + scale_x_reverse() + scale_y_log10(), "reversed and log scales")
})

test_that("check.overlap keeps the labels grid keeps", {
  crowded <- disc + theme(axis.text.x = element_text(size = 20))
  check_page(crowded + guides(x = guide_axis(check.overlap = TRUE)), "check.overlap")
  check_page(crowded + guides(x = guide_axis(check.overlap = TRUE, n.dodge = 2)), "check.overlap with n.dodge")
  check_page(
    base + guides(y = guide_axis(check.overlap = TRUE)) + theme(axis.text.y = element_text(size = 40)),
    "check.overlap on y"
  )
})

test_that("rotated discrete labels", {
  check_page(disc + theme(axis.text.x = element_text(angle = 30, hjust = 1)), "angle 30")
  check_page(disc + theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)), "angle 90")
  check_page(disc + guides(x = guide_axis(angle = 60)), "guide angle 60")
})

test_that("panel elements: border, clip, line types and widths, aspect ratio", {
  check_page(base + theme(panel.border = element_rect(colour = "red", fill = "blue", linewidth = 2)), "border")
  check_page(base + coord_cartesian(clip = "off") + theme(panel.border = element_rect(colour = "red", linewidth = 4)), "clip off")
  check_page(
    base + theme(
      panel.grid.major = element_line(linetype = "dashed", colour = "black"),
      panel.grid.minor = element_line(linetype = "dotted", colour = "black")
    ),
    "dashed grid"
  )
  check_page(base + theme(panel.grid = element_line(linewidth = 3, colour = "grey30")), "thick grid")
  check_page(base + theme(panel.grid.minor = element_blank(), panel.background = element_blank()), "blank panel elements")
  check_page(base + theme(panel.ontop = TRUE, panel.background = element_rect(fill = NA)), "panel on top")
  check_page(base + coord_fixed(), "coord_fixed")
  check_page(base + coord_fixed(ratio = 0.2) + labs(title = "Fixed"), "coord_fixed 0.2")
  check_page(base + theme(aspect.ratio = 2), "aspect ratio")
})

test_that("margins, backgrounds, titles and tags", {
  check_page(base + theme(plot.margin = margin(1, 2, 3, 4, "cm")), "plot margin")
  check_page(base + theme(plot.background = element_blank()), "no plot background")
  check_page(base + theme(plot.background = element_rect(fill = "grey90", colour = "red", linewidth = 3)), "plot background")
  check_page(base + labs(tag = "T") + theme(plot.tag.position = "bottomright"), "tag")
  check_page(
    base + labs(title = "T", caption = "C") + theme(plot.title.position = "plot", plot.caption.position = "plot"),
    "title and caption on the plot"
  )
})

test_that("a transparent or coloured device background is cleared first", {
  local_full_tier()
  b <- ggplot_build(base + theme(plot.background = element_blank()))
  out <- render_raster(b, c(render_size, list(bg = "transparent")))
  expect_identical(out$tier, "full")
  expect_identical(bitwShiftR(out$raster[1], 24L), 0L)
})

test_that("plots the full tier doesn't draw decline to another tier", {
  local_full_tier()
  tier <- function(p, ...) {
    set.seed(1)
    b <- suppressWarnings(suppressMessages(ggplot_build(p)))
    suppressMessages(render_raster(b, utils::modifyList(render_size, list(...)))$tier)
  }
  expect_identical(tier(base), "full")
  # Other layers aren't drawn yet.
  expect_identical(tier(ggplot(mtcars, aes(wt, mpg)) + geom_rug()), "ggplot2")
  expect_identical(tier(base + geom_blank() + geom_rug()), "ggplot2")
  # Blank strips, coords, axis caps and scaling aren't drawn yet.
  expect_identical(tier(base + facet_wrap(vars(cyl)) + theme(strip.text = element_blank())), "ggplot2")
  expect_identical(tier(base + coord_flip()), "ggplot2")
  expect_identical(tier(base + coord_trans(x = "sqrt")), "ggplot2")
  # A blank layer's legend has point keys (GeomBlank$draw_key), which the full tier draws.
  expect_identical(tier(ggplot(mtcars, aes(wt, mpg)) + geom_blank(aes(colour = factor(cyl)), show.legend = TRUE)), "full")
  expect_identical(tier(base + guides(x = guide_axis(cap = "both"))), "ggplot2")
  expect_identical(tier(base, scaling = 2), "ggplot2")
  # Plotmath labels and glyphs the font lacks.
  expect_identical(tier(base + labs(x = expression(alpha^2))), "ggplot2")
  expect_identical(tier(base + labs(title = "漢字")), "ggplot2")
  # The option turns the tier off.
  withr::local_options(alot.full_tier = FALSE)
  expect_identical(tier(base), "ggplot2")
})

test_that("the full tier names why it declines", {
  set.seed(1)
  b <- ggplot_build(base + guides(x = guide_axis(cap = "both")))
  expect_match(attr(render_full(b, render_size), "reason"), "axis cap")
  b <- ggplot_build(ggplot(mtcars, aes(wt, mpg)) + geom_rug())
  expect_match(attr(render_full(b, render_size), "reason"), "layers other than")
})

test_that("a higher resolution and a larger page", {
  size <- list(width = 600, height = 450, res = 150)
  check_page(base, "theme_grey at 150 dpi", size = size)
  check_page(base + labs(title = "A title", tag = "A") + theme_bw(), "theme_bw at 150 dpi", size = size)
  check_page(
    base + guides(x = guide_axis(n.dodge = 2, minor.ticks = TRUE), y = guide_axis(angle = 45)) +
      scale_x_continuous(position = "top") + theme(axis.line = element_line()),
    "axes at 150 dpi", size = size
  )
  check_page(base + theme(panel.border = element_rect(fill = NA, colour = "red", linewidth = 2)), "border at 150 dpi", size = size)
})
