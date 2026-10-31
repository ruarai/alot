# Complete themes in the full tier (R6.2): every built-in complete theme
# (ggplot2 R/theme-defaults.R), its arguments, and the theme elements and
# options they set, on blank and point plots with titles, legends and
# facet_wrap(), drawn by alot-core's page drawers against ggplot2 on ragg.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_theme <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-themes.R", label, b)
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key)))
  expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
}

mt <- transform(mtcars, gear = factor(gear))
plots <- list(
  blank = ggplot(mt, aes(wt, mpg)) + geom_blank(),
  points = ggplot(mt, aes(wt, mpg)) + geom_point() + labs(title = "Title", subtitle = "Subtitle", caption = "Caption", tag = "A"),
  legend = ggplot(mt, aes(wt, mpg, colour = gear)) + geom_point(),
  colourbar = ggplot(mt, aes(wt, mpg, colour = qsec)) + geom_point() + theme(legend.position = "bottom"),
  wrap = ggplot(mt, aes(wt, mpg)) + geom_point() + facet_wrap(~gear)
)
themes <- c("grey", "gray", "bw", "linedraw", "light", "dark", "minimal", "classic", "void", "test")

test_that("blank and point plots draw as ggplot2 draws them in every complete theme", {
  for (theme in themes) {
    for (plot in names(plots)) {
      check_theme(plots[[plot]] + get(paste0("theme_", theme))(), paste(theme, plot))
    }
  }
})

test_that("complete themes' arguments", {
  args <- list(
    `grey base_size 18` = theme_grey(base_size = 18),
    `bw base_size 7` = theme_bw(base_size = 7),
    `classic serif` = theme_classic(base_family = "serif"),
    `light mono` = theme_light(base_family = "mono"),
    `grey header_family` = theme_grey(header_family = "serif"),
    `grey ink and paper` = theme_grey(ink = "white", paper = "black"),
    `bw ink, paper and accent` = theme_bw(ink = "navy", paper = "lightyellow", accent = "red"),
    `minimal dark mode` = theme_minimal(ink = "grey90", paper = "grey10"),
    `dark ink and paper` = theme_dark(ink = "#202020", paper = "#F0F0F0"),
    `classic translucent paper` = theme_classic(ink = "darkred", paper = "#FFFFFF80"),
    `void paper` = theme_void(paper = "grey80"),
    `linedraw line and rect sizes` = theme_linedraw(base_line_size = 1, base_rect_size = 2),
    `test base_size 20` = theme_test(base_size = 20)
  )
  for (label in names(args)) {
    for (plot in c("points", "legend", "wrap")) {
      check_theme(plots[[plot]] + args[[label]], paste(label, plot))
    }
  }
})

test_that("theme elements and options", {
  pts <- plots$points
  leg <- plots$legend
  wrap <- plots$wrap
  # Dashed and dotted outlines of element rects (ragg's drawRect() path, dashed).
  check_theme(pts + theme(panel.border = element_rect(fill = NA, linetype = "dashed")), "dashed border")
  check_theme(pts + theme(panel.border = element_rect(fill = NA, colour = "red", linetype = "dotdash", linewidth = 2, linejoin = "mitre")), "dotdash border")
  check_theme(plots$blank + theme(plot.background = element_rect(colour = "red", linetype = 2, linewidth = 2)), "dashed plot background")
  check_theme(leg + theme(legend.background = element_rect(colour = "black", linetype = "dotted"), legend.key = element_rect(colour = "grey50", linetype = "44")), "dashed legend rects")
  check_theme(wrap + theme(strip.background = element_rect(linetype = "dashed", colour = "black")), "dashed strips")
  check_theme(pts + theme(panel.background = element_rect(colour = "blue", linetype = "longdash", linewidth = 1)), "dashed panel background")
  check_theme(pts + theme(line = element_line(linetype = "dashed")), "dashed lines")
  # Font-relative units in the plot and panel tables and on ticks.
  check_theme(pts + theme(plot.margin = unit(c(1, 2, 1, 0.5), "lines")), "margin in lines")
  check_theme(wrap + theme(panel.spacing = unit(2, "lines")), "spacing in lines")
  check_theme(pts + theme(axis.ticks.length = unit(0.5, "lines")), "ticks in lines")
  check_theme(pts + theme(plot.margin = unit(c(1, 1, 1, 1), "char")), "margin in char")
  # Panel on top of the layers (Coord$draw_panel()).
  check_theme(pts + theme(panel.ontop = TRUE, panel.background = element_rect(fill = NA, colour = "blue")), "panel on top")
  check_theme(wrap + theme_bw() + theme(panel.ontop = TRUE, panel.background = element_rect(fill = alpha("white", 0.3))), "translucent panel on top")
  # Text elements.
  check_theme(pts + theme(axis.title = element_text(face = "bold", colour = "#FF000080"), plot.title = element_text(family = "mono", face = "italic")), "text faces")
  check_theme(pts + theme(text = element_text(colour = "darkblue", size = 14), axis.text = element_text(size = rel(1.2))), "root text")
  check_theme(wrap + theme(strip.text = element_text(face = "bold", hjust = 0), strip.background = element_rect(fill = "navy", colour = "red", linewidth = 2)), "strips")
  check_theme(leg + theme_minimal() + theme(legend.position = "top", legend.title = element_text(face = "bold")), "minimal legend on top")
  check_theme(pts + theme(rect = element_rect(fill = "lightyellow", colour = "red", linewidth = 2)), "root rect")
})

test_that("a higher resolution", {
  size <- list(width = 600, height = 450, res = 150)
  for (theme in c("bw", "classic", "dark", "void")) {
    check_theme(plots$legend + get(paste0("theme_", theme))(), paste(theme, "at 150 dpi"), size = size)
  }
  check_theme(plots$points + theme(panel.border = element_rect(fill = NA, linetype = "dashed")), "dashed border at 150 dpi", size = size)
})

test_that("theme options the full tier doesn't draw decline to another tier, with a reason", {
  reason <- function(p) {
    set.seed(1)
    b <- suppressWarnings(suppressMessages(ggplot_build(p)))
    out <- suppressMessages(render_raster(b, render_size))
    expect_false(identical(out$tier, "full"))
    paste(alot_render_coverage(b)$full$reason, collapse = "; ")
  }
  pts <- plots$points
  expect_match(reason(pts + theme(axis.title = element_text(debug = TRUE))), "debug text")
  expect_match(reason(pts + theme(axis.line = element_line(arrow = arrow()))), "arrows")
  expect_match(reason(pts + theme(plot.title = element_text(margin = margin(b = 1, unit = "lines")))), "unit lines")
  expect_match(reason(plots$legend + theme(legend.spacing.y = unit(1, "null"))), "stretched")
})
