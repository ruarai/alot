# Legends and colourbars in the full tier (R5.3, R6.4): guide_legend() with
# the keys of the geoms the full tier draws, guide_colourbar(),
# guide_coloursteps() and guide_bins(), at every position including inside,
# drawn by alot-core's legend module against ggplot2 on ragg, and their
# boxes against grid's.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_legend <- function(p, label, ..., max = 12, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label)))
  # The layout is alot's own: grid's legend sizes are not passed.
  full <- utils::modifyList(render_size, size)
  mine <- layout_boxes_rust(b, full$width, full$height, full$res)
  expect_gt(length(mine), 0)
  expect_layout_close(mine, grid_layout(b, full)$boxes, 0.5)
}

base <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
disc <- base + aes(colour = factor(cyl))

test_that("a discrete legend draws as ggplot2 draws it", {
  check_legend(disc, "colour legend")
  check_legend(base + aes(shape = factor(cyl)), "shape legend")
  check_legend(base + aes(colour = factor(cyl), size = hp), "colour and size legends")
  check_legend(base + aes(colour = factor(cyl), shape = factor(cyl)), "merged legend")
  check_legend(disc + labs(colour = "Cylinders\nin the engine"), "multi-line title")
  check_legend(disc + labs(colour = NULL), "no title")
  check_legend(disc + geom_point(size = 5, alpha = 0.5), "big points with alpha")
  check_legend(base + geom_point(aes(colour = interaction(cyl, gear))), "many keys")
  check_legend(disc + scale_colour_manual(values = c("red", "#00FF0080", "blue"), labels = c("four", "six", "eight")), "labels")
  check_legend(base + aes(fill = factor(cyl)) + geom_point(shape = 21, size = 4, stroke = 1.5), "filled points")
  check_legend(ggplot(mtcars, aes(wt, mpg)) + geom_blank(aes(colour = factor(cyl)), show.legend = TRUE), "blank layer's keys")
})

test_that("legend positions, directions and boxes", {
  for (position in c("left", "top", "bottom")) {
    check_legend(disc + theme(legend.position = position), paste("position", position))
  }
  check_legend(disc + theme(legend.position = "none"), "no legend")
  check_legend(disc + theme(legend.direction = "horizontal"), "horizontal on the right")
  check_legend(disc + theme(legend.position = "bottom", legend.direction = "vertical"), "vertical at the bottom")
  check_legend(disc + aes(size = hp) + theme(legend.position = "bottom"), "two legends at the bottom")
  check_legend(disc + aes(size = hp) + theme(legend.box = "horizontal"), "horizontal box")
  check_legend(disc + aes(size = hp) + theme(legend.box.just = "right", legend.spacing.y = unit(1, "cm")), "box just and spacing")
  check_legend(disc + theme(legend.justification = "top"), "justified to the top")
  check_legend(disc + theme(legend.justification = c(1, 0), legend.position = "bottom"), "justified to the right")
  check_legend(disc + theme(legend.box.spacing = unit(1, "cm")), "box spacing")
  check_legend(disc + theme(legend.location = "plot", legend.position = "bottom") + labs(title = "T", caption = "C"), "location plot")
})

test_that("legend text, keys and spacing follow the theme", {
  check_legend(disc + theme(legend.text.position = "left"), "text left")
  check_legend(disc + theme(legend.text.position = "top"), "text top")
  check_legend(disc + theme(legend.text.position = "bottom"), "text bottom")
  check_legend(disc + theme(legend.title.position = "left"), "title left")
  check_legend(disc + theme(legend.title.position = "bottom"), "title bottom")
  check_legend(disc + theme(legend.title.position = "right"), "title right")
  check_legend(disc + theme(legend.title = element_text(hjust = 1, face = "bold", size = 16)), "wide title right-justified")
  check_legend(disc + theme(legend.title = element_text(size = 20), legend.position = "bottom"), "wide title at the bottom")
  check_legend(disc + theme(legend.key.size = unit(1, "cm")), "big keys")
  check_legend(disc + theme(legend.key.width = unit(2, "cm"), legend.key.height = unit(0.5, "cm")), "key width and height")
  check_legend(disc + theme(legend.key.spacing.y = unit(5, "pt")), "key spacing")
  check_legend(disc + theme(legend.key.spacing = unit(10, "pt"), legend.position = "bottom"), "key spacing at the bottom")
  check_legend(disc + theme(legend.margin = margin(10, 20, 5, 15), legend.background = element_rect(fill = "grey80", colour = "black")), "margin and background")
  check_legend(disc + theme(legend.key = element_rect(fill = "yellow", colour = "red")), "key rect")
  check_legend(disc + theme(legend.text = element_text(colour = "red", size = 14, face = "italic")), "text style")
  check_legend(disc + theme(legend.byrow = TRUE) + guides(colour = guide_legend(ncol = 2)), "two columns by row")
  check_legend(disc + guides(colour = guide_legend(nrow = 2)), "two rows")
  check_legend(base + geom_point(aes(colour = interaction(cyl, gear))) + guides(colour = guide_legend(ncol = 2, byrow = TRUE)), "many keys, columns")
  check_legend(disc + guides(colour = guide_legend(reverse = TRUE)), "reversed")
  check_legend(disc + guides(colour = guide_legend(override.aes = list(size = 6, shape = 17))), "override.aes")
  check_legend(disc + guides(colour = guide_legend(position = "bottom")), "guide position")
  check_legend(disc + guides(colour = guide_legend(theme = theme(legend.key.size = unit(1, "cm"), legend.text = element_text(size = 15)))), "guide theme")
  for (theme in list(theme_bw(), theme_classic(), theme_minimal(), theme_dark(), theme_light(), theme_linedraw(), theme_void())) {
    check_legend(disc + theme + labs(title = "Themes"), "complete theme")
  }
})

test_that("a colourbar draws as ggplot2 draws it", {
  bar <- base + aes(colour = qsec)
  check_legend(bar, "colourbar")
  check_legend(bar + scale_colour_viridis_c(), "viridis")
  check_legend(bar + scale_colour_gradient2(midpoint = 18), "diverging")
  check_legend(bar + scale_colour_gradient(low = "white", high = "black"), "grey")
  check_legend(bar + scale_colour_gradient(breaks = c(16, 20), labels = c("low", "high")), "labels")
  check_legend(bar + scale_colour_gradient(limits = c(10, 30)), "limits wider than the data")
  check_legend(bar + scale_colour_gradient(trans = "log10"), "log scale")
  check_legend(bar + scale_colour_gradient(guide = guide_colourbar(reverse = TRUE)), "reversed")
  check_legend(bar + scale_colour_gradient(guide = guide_colourbar(nbin = 20)), "few bins")
  check_legend(bar + scale_colour_gradient(guide = guide_colourbar(draw.ulim = FALSE, draw.llim = FALSE)), "no limit ticks")
  check_legend(bar + scale_colour_gradient(guide = guide_colourbar(alpha = 0.5)), "alpha")
  check_legend(bar + labs(colour = "A long title\nin two lines"), "title")
  check_legend(bar + theme(legend.position = "bottom"), "bottom")
  check_legend(bar + theme(legend.position = "top"), "top")
  check_legend(bar + theme(legend.position = "left"), "left")
  check_legend(bar + theme(legend.key.height = unit(3, "cm"), legend.key.width = unit(1, "cm")), "key size")
  check_legend(bar + theme(legend.position = "bottom", legend.key.width = unit(5, "cm")), "long horizontal bar")
  check_legend(bar + theme(legend.title.position = "left", legend.position = "bottom"), "title left")
  check_legend(bar + theme(legend.text.position = "left"), "text left")
  check_legend(bar + theme(legend.ticks = element_line(colour = "red", linewidth = 1), legend.ticks.length = unit(0.4, "npc")), "ticks")
  check_legend(bar + theme(legend.frame = element_rect(colour = "black", linewidth = 1)), "frame")
  check_legend(bar + theme(legend.ticks = element_blank()), "no ticks")
  check_legend(bar + guides(colour = guide_colourbar(theme = theme(legend.text = element_blank()))), "no labels")
  check_legend(bar + theme(legend.background = element_rect(fill = "grey90"), legend.margin = margin(5, 5, 5, 5)), "background")
  check_legend(bar + aes(shape = factor(cyl)), "colourbar and legend")
  check_legend(bar + aes(shape = factor(cyl)) + theme(legend.position = "bottom"), "colourbar and legend at the bottom")
  check_legend(bar + aes(fill = hp) + geom_point(shape = 21), "two colourbars")
  check_legend(bar, "150 dpi", size = list(width = 600, height = 450, res = 150))
  check_legend(bar, "300 dpi", size = list(width = 900, height = 700, res = 300))
})

test_that("missing, empty and single-row data", {
  check_legend(ggplot(mtcars[1, ], aes(wt, mpg, colour = factor(cyl))) + geom_point(), "one row")
  check_legend(ggplot(mtcars[1, ], aes(wt, mpg, colour = qsec)) + geom_point(), "one row colourbar")
  d <- data.frame(x = c(1, 2, NA, 4), y = c(1, 3, 2, NA), g = c("a", NA, "b", "a"))
  check_legend(ggplot(mtcars[0, ], aes(wt, mpg, colour = factor(cyl))) + geom_point(), "no rows")
  na <- data.frame(x = 1:3, y = 1:3, g = c("a", NA, "b"))
  check_legend(ggplot(na, aes(x, y, colour = g)) + geom_point(), "an NA key")
  check_legend(ggplot(na, aes(x, y, fill = g)) + geom_tile() + scale_fill_grey(), "an NA tile key")
  check_legend(disc + scale_colour_discrete(drop = FALSE, limits = c("4", "6", "8", "10")), "unused level")
  check_legend(base + aes(colour = qsec) + facet_null(), "null facet")
})

test_that("keys of the other geoms draw as ggplot2 draws them (R6.4)", {
  bars <- ggplot(mpg, aes(class, fill = drv)) + geom_bar()
  check_legend(bars, "bar keys")
  check_legend(ggplot(mpg, aes(class, fill = drv)) + geom_bar(colour = "black", linewidth = 1), "outlined bar keys")
  check_legend(
    ggplot(mpg, aes(class, fill = drv)) + geom_bar(colour = "black", linewidth = 1) +
      guides(fill = guide_legend(override.aes = list(linetype = "dashed"))),
    "dashed bar keys"
  )
  check_legend(ggplot(mpg, aes(class, colour = drv)) + geom_bar(fill = NA, linewidth = 0.8), "outline-only bar keys")
  check_legend(ggplot(mpg, aes(class, fill = drv)) + geom_bar(alpha = 0.4, linejoin = "round", colour = "red"), "bar keys with alpha and joins")
  check_legend(ggplot(faithfuld, aes(waiting, eruptions, fill = density)) + geom_tile(), "tiles with a colourbar")
  check_legend(ggplot(data.frame(x = 1:3, y = 1:3, g = c("a", "b", "c")), aes(x, y, fill = g)) + geom_tile(), "tile keys")
  check_legend(ggplot(data.frame(x = 1:3, g = c("a", "b", "c")), aes(xmin = x, xmax = x + 1, ymin = 0, ymax = x, fill = g)) + geom_rect(), "rect keys")
  check_legend(ggplot(economics_long, aes(date, value01, colour = variable)) + geom_line(), "line keys")
  check_legend(ggplot(economics_long, aes(date, value01, linetype = variable)) + geom_line(), "line type keys")
  check_legend(ggplot(economics_long, aes(date, value01, linewidth = variable)) + geom_line(), "line width keys")
  check_legend(ggplot(economics_long, aes(date, value01, colour = variable)) + geom_line(lineend = "round", linewidth = 2, alpha = 0.5), "round line keys")
  check_legend(ggplot(economics_long, aes(date, value01, colour = variable)) + geom_step(), "step keys")
  check_legend(ggplot(economics_long, aes(date, value01, colour = variable)) + geom_path(), "path keys")
  check_legend(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point() + geom_line(), "point and line keys")
  check_legend(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_line(key_glyph = "rect"), "rect key glyph")
  check_legend(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point(key_glyph = draw_key_path), "path key glyph on points")
  check_legend(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point(key_glyph = "blank"), "blank key glyph")
  check_legend(bars + theme(legend.key.size = unit(1, "cm"), legend.key = element_rect(fill = "grey90", colour = "black")), "big bar keys")
  check_legend(bars + theme(legend.position = "bottom"), "bar keys at the bottom")
  check_legend(ggplot(economics_long, aes(date, value01, colour = variable)) + geom_line(key_glyph = "timeseries"), "timeseries keys")
  check_legend(
    ggplot(economics_long, aes(date, value01, colour = variable)) + geom_line(key_glyph = "timeseries", linewidth = 1.5, linejoin = "mitre"),
    "thick timeseries keys"
  )
  txt <- ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars)))
  check_legend(txt + geom_text(aes(colour = factor(cyl))), "text keys")
  check_legend(txt + geom_text(aes(colour = factor(cyl)), size = 6, fontface = "bold", alpha = 0.5), "big bold text keys")
  check_legend(txt + geom_text(aes(colour = factor(cyl)), family = "serif") + theme(legend.key.size = unit(0.3, "cm")), "serif text keys")
  check_legend(txt + geom_text(aes(colour = factor(cyl))) + geom_point(aes(colour = factor(cyl))), "text and point keys")
})

test_that("key justification, box margin and box background (R6.4)", {
  big <- disc + aes(size = hp)
  check_legend(big + theme(legend.key.justification = "top"), "keys justified to the top")
  check_legend(big + theme(legend.key.justification = c(1, 0), legend.key = element_rect(fill = "grey80")), "keys justified bottom right")
  check_legend(disc + theme(legend.box.margin = margin(5, 10, 15, 20)), "box margin")
  check_legend(disc + theme(legend.box.margin = margin(5, 10, 15, 20), legend.justification = c(0, 1)), "box margin justified")
  check_legend(disc + theme(legend.box.margin = margin(5, 10, 15, 20), legend.position = "bottom"), "box margin at the bottom")
  check_legend(big + theme(legend.box.background = element_rect(colour = "black")), "box background")
  check_legend(big + theme(legend.box.background = element_rect(), legend.box.margin = margin_auto(6)), "default box background")
  check_legend(big + theme(legend.box.background = element_rect(fill = "grey90", colour = "red", linewidth = 2), legend.box.margin = margin(2, 4, 6, 8), legend.position = "top"), "box background on top")
  check_legend(big + theme(legend.box.background = element_rect(colour = "blue", fill = NA), legend.box = "horizontal", legend.box.margin = margin(t = 5, b = 10, unit = "mm")), "horizontal box background")
})

test_that("inside legends draw as ggplot2 draws them (R6.4)", {
  check_legend(disc + theme(legend.position = "inside"), "inside")
  check_legend(disc + theme(legend.position = c(0.9, 0.8)), "inside at a point")
  check_legend(disc + theme(legend.position = "inside", legend.position.inside = c(1, 1), legend.justification.inside = c(1, 1)), "inside top right")
  check_legend(disc + theme(legend.position = "inside", legend.justification.inside = c(0, 0)), "inside bottom left")
  check_legend(disc + aes(size = hp) + theme(legend.position = "inside", legend.box.background = element_rect(), legend.box.margin = margin_auto(3)), "two inside")
  check_legend(
    disc + aes(size = hp) + guides(size = guide_legend(position = "inside", theme = theme(legend.position.inside = c(0.2, 0.2)))),
    "one inside, one right"
  )
  check_legend(
    disc + aes(size = hp) + theme(legend.position = "inside") +
      guides(size = guide_legend(theme = theme(legend.justification.inside = c(0, 1), legend.position.inside = c(0, 1)))),
    "two inside boxes"
  )
  check_legend(disc + facet_wrap(~am) + theme(legend.position = "inside", legend.position.inside = c(0.5, 0.9)), "inside over facets")
  check_legend(base + aes(colour = qsec) + theme(legend.position = "inside", legend.direction = "horizontal"), "inside colourbar")
})

test_that("colour steps and rectangle colourbars draw as ggplot2 draws them (R6.4)", {
  bar <- base + aes(colour = qsec)
  check_legend(bar + guides(colour = guide_coloursteps()), "coloursteps")
  check_legend(bar + guides(colour = guide_coloursteps(show.limits = TRUE)), "coloursteps with limits")
  check_legend(bar + guides(colour = guide_coloursteps(even.steps = FALSE)), "uneven steps")
  check_legend(bar + scale_colour_binned(), "binned scale")
  check_legend(bar + scale_colour_viridis_b() + theme(legend.position = "bottom"), "binned at the bottom")
  check_legend(bar + guides(colour = guide_coloursteps(reverse = TRUE)) + theme(legend.frame = element_rect(colour = "black")), "reversed steps with frame")
  check_legend(bar + guides(colour = guide_colourbar(display = "rectangles")), "rectangles")
  check_legend(bar + guides(colour = guide_colourbar(display = "rectangles", nbin = 7)) + theme(legend.position = "bottom"), "few rectangles")
})

test_that("guide_bins() draws as ggplot2 draws it (R6.4)", {
  bins <- base + aes(size = hp) + guides(size = guide_bins())
  check_legend(bins, "bins")
  check_legend(base + aes(size = hp) + scale_size_binned(), "binned size scale")
  check_legend(bins + theme(legend.position = "bottom"), "bins at the bottom")
  check_legend(bins + theme(legend.position = "left"), "bins on the left")
  check_legend(base + aes(size = hp) + guides(size = guide_bins(show.limits = TRUE)), "bins with limits")
  check_legend(base + aes(size = hp) + guides(size = guide_bins(reverse = TRUE)), "reversed bins")
  check_legend(bins + theme(legend.text.position = "left"), "bins with text on the left")
  check_legend(bins + theme(legend.position = "bottom", legend.text.position = "top"), "bins with text on top")
  check_legend(bins + theme(legend.axis.line = element_line(colour = "red", linewidth = 1), legend.ticks = element_line(colour = "blue")), "bins axis and ticks")
  check_legend(bins + theme(legend.ticks.length = unit(4, "pt"), legend.key = element_rect(fill = "grey90")), "bins tick length")
  check_legend(bins + theme(legend.text = element_blank()), "bins without labels")
  check_legend(base + aes(colour = qsec) + guides(colour = guide_bins()), "colour bins")
  check_legend(ggplot(mpg, aes(displ, hwy, colour = cty)) + geom_point() + scale_colour_binned(guide = "bins") + theme(legend.key.justification = "top"), "bins with key justification")
})

test_that("guides alot doesn't draw fall back", {
  tier <- function(p) {
    set.seed(1)
    b <- suppressWarnings(ggplot_build(p))
    render_raster(b, render_size)$tier
  }
  declined <- function(p) {
    b <- suppressWarnings(ggplot_build(p))
    attr(layout_boxes_rust(b, 400, 300, 96), "reason")
  }
  expect_match(declined(disc + scale_colour_discrete(labels = expression(alpha, beta, gamma))), "plain text")
  expect_match(declined(base + aes(colour = qsec) + guides(colour = guide_colourbar(display = "gradient"))), "gradient")
  expect_match(declined(base + aes(colour = qsec) + guides(colour = guide_colourbar(angle = 45))), "angle")
  expect_match(declined(disc + theme(legend.key.width = unit(1, "null"))), "stretched")
  expect_match(declined(disc + theme(legend.box.margin = margin(1, 1, 1, 1, "null"))), "stretched")
  expect_match(declined(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_text(aes(label = cyl), angle = 30)), "rotated")
  expect_match(declined(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_text(aes(label = cyl), hjust = 0)), "justified")
  expect_match(declined(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_line(arrow = arrow())), "arrow")
  expect_match(declined(ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point(key_glyph = "dotplot")), "legend key")
  expect_equal(tier(base + aes(colour = qsec) + guides(colour = guide_colourbar(display = "gradient"))), "hybrid")
  expect_equal(tier(disc + theme(legend.position = "inside")), "full")
  expect_equal(tier(disc), "full")
})
