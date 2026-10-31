# The page layout (R4.1): alot's table for single-panel plots against the
# boxes grid gives ggplot_gtable()'s cells (helper-render.R), within 0.5 px.
# Legends are sized by grid for now; their layout is mirrored in R5.

skip_on_cran()
library(ggplot2)

layout_plot <- function(p, ..., tol = 0.5) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  expect_null(expect_layout_matches(b, utils::modifyList(render_size, list(...)), tol = tol))
}

base <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

test_that("a plain plot lays out as grid does", {
  layout_plot(base)
  layout_plot(base, width = 700, height = 500, units = "px", res = 150)
  layout_plot(base, width = 300, height = 300, units = "px", res = 72)
})

test_that("title, subtitle, caption and tag are placed as grid places them", {
  p <- base + labs(title = "A title", subtitle = "A subtitle\non two lines", caption = "A caption", tag = "A")
  layout_plot(p)
  layout_plot(p + theme(plot.title.position = "plot", plot.caption.position = "plot"))
  for (position in c("topleft", "top", "topright", "left", "right", "bottomleft", "bottom", "bottomright")) {
    layout_plot(p + theme(plot.tag.position = position))
    # ggplot2 fails on left and right tags outside the margin (an unset vjust).
    if (!position %in% c("left", "right")) {
      layout_plot(p + theme(plot.tag.position = position, plot.tag.location = "plot"))
      layout_plot(p + theme(plot.tag.position = position, plot.tag.location = "panel"))
    }
  }
  layout_plot(p + theme(plot.tag.position = c(0.2, 0.9)))
  layout_plot(p + theme(plot.title = element_text(size = 30, face = "bold", margin = margin(20, 0, 30, 0))))
  layout_plot(p + theme(plot.title = element_blank(), plot.caption = element_blank(), plot.tag = element_blank()))
})

test_that("axis titles, labels and ticks size the table", {
  layout_plot(base + labs(x = NULL, y = NULL))
  layout_plot(base + labs(x = "Weight\n(1000 lbs)", y = "Miles per gallon, gross"))
  layout_plot(base + theme(axis.title.y = element_text(angle = 0), axis.ticks.length = unit(0.5, "cm")))
  layout_plot(base + theme(axis.ticks.length = unit(-0.3, "cm")))
  layout_plot(base + theme(axis.text = element_text(size = 20, margin = margin(10, 10, 10, 10))))
  layout_plot(base + theme(axis.text.x = element_blank(), axis.ticks = element_blank()))
  layout_plot(base + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"))
  layout_plot(base + scale_x_continuous(sec.axis = dup_axis(name = "Second")) + scale_y_continuous(sec.axis = dup_axis()))
  layout_plot(base + guides(x = guide_axis(angle = 45), y = guide_axis(angle = 90)))
  layout_plot(base + guides(x = guide_axis(n.dodge = 2), y = guide_axis(n.dodge = 2, minor.ticks = TRUE)))
  layout_plot(base + guides(x = guide_axis(minor.ticks = TRUE)) + theme(axis.minor.ticks.length = rel(2)))
  layout_plot(ggplot(data.frame(x = c("a long label", "b", "c"), y = 1:3), aes(x, y)) + geom_point() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1)))
})

test_that("a fixed aspect ratio centres the panel", {
  layout_plot(base + coord_fixed())
  layout_plot(base + coord_fixed(ratio = 0.2) + labs(title = "Fixed"))
  layout_plot(base + theme(aspect.ratio = 2))
  layout_plot(base + coord_flip())
  layout_plot(base + coord_trans(x = "sqrt"))
})

test_that("margins, backgrounds and complete themes", {
  layout_plot(base + theme(plot.margin = margin(1, 2, 3, 4, "cm")))
  layout_plot(base + theme(plot.margin = unit(c(1, 2, 3, 4), "mm"), plot.background = element_blank()))
  for (theme in list(theme_bw(), theme_classic(), theme_minimal(), theme_void(), theme_dark(), theme_light(), theme_linedraw())) {
    layout_plot(base + theme + labs(title = "T", tag = "a"))
  }
  layout_plot(base + theme_grey(base_size = 20, base_family = "serif") + labs(title = "Serif"))
})

test_that("legends are placed around the panel", {
  p <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point() + labs(title = "Legend")
  layout_plot(p)
  for (position in c("left", "top", "bottom", "inside", "none")) {
    layout_plot(p + theme(legend.position = position))
  }
  layout_plot(p + theme(legend.location = "plot", legend.position = "bottom") + labs(subtitle = "S"))
  layout_plot(p + theme(legend.box.spacing = unit(1, "cm")))
  layout_plot(ggplot(mtcars, aes(wt, mpg, colour = disp, size = hp)) + geom_point())
})

test_that("plots alot doesn't lay out decline with a reason", {
  reason <- function(p) {
    b <- suppressWarnings(ggplot_build(p))
    attr(layout_boxes_rust(b, 400, 300, 96), "reason")
  }
  expect_match(reason(base + facet_wrap(~cyl) + theme(strip.text = element_blank())), "blank strips")
  expect_match(reason(base + facet_grid(am ~ cyl, labeller = label_bquote(rows = alpha^.(am)))), "not plain text")
  expect_match(reason(base + coord_polar()), "coord not laid out")
  expect_match(reason(base + theme(panel.widths = unit(5, "cm"))), "fixed panel sizes")
  expect_match(reason(base + theme(plot.margin = unit(c(1, 1, 1, 1), "npc"))), "unit npc")
  # A text margin in lines: titleGrob() sizes and places it in different gpars.
  expect_match(reason(base + theme(axis.title.x = element_text(margin = margin(t = 1, unit = "lines")))), "unit lines")
  expect_match(reason(base + labs(title = quote(alpha^2))), "plain text")
  expect_match(reason(base + aes(colour = qsec) + guides(colour = guide_colourbar(display = "gradient"))), "gradient")
})
