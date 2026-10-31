# Segments, reference lines and rugs in the full tier (R6.5c):
# geom_segment(), geom_abline(), geom_hline(), geom_vline() and
# geom_rug(), with their keys, drawn by alot-core's page drawers against
# ggplot2 on ragg. They have no hybrid drawer: in the hybrid tier ggplot2
# draws them. geom_curve() and arrows decline.

skip_on_cran()
library(ggplot2)
withr::local_options(alot.full_tier = TRUE)

check_seg <- function(p, label, ..., max = 32, size = list()) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot_build(p)))
  key <- render_case_key("test-render-segments.R", label, b)
  expect_no_warning(
    do.call(expect_render_close, c(list(b), size, list(..., max = max, tier = "full", label = label, cache_key = key))),
    class = "alot_render_fallback"
  )
  expect_layout_sampled(b, utils::modifyList(render_size, size), label = label, cache_key = key)
}

segs <- data.frame(x = c(1, 2.5, 3), y = c(1, 4, 2), xend = c(2, 3.5, 1.5), yend = c(3, 4, 0.5), g = c("a", "b", "a"))
sp <- ggplot(segs, aes(x, y, xend = xend, yend = yend))
pts <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

test_that("segments draw as ggplot2 draws them", {
  check_seg(sp + geom_segment(), "segment")
  check_seg(sp + geom_segment(aes(colour = g), linewidth = 2, lineend = "round"), "segment colour legend, round ends")
  check_seg(sp + geom_segment(aes(linetype = g), alpha = 0.5), "segment linetype legend, alpha")
  check_seg(sp + geom_segment(linewidth = 3, lineend = "square") + facet_wrap(vars(g), scales = "free"), "segment facets")
  check_seg(ggplot(segs, aes(x, y, xend = xend)) + geom_segment(), "segment without yend")
  check_seg(ggplot(mpg, aes(class, hwy, xend = class, yend = 0)) + geom_segment(stat = "summary", fun = mean), "discrete x")
})

test_that("reference lines draw as ggplot2 draws them", {
  check_seg(pts + geom_hline(yintercept = c(15, 25)), "hline")
  check_seg(pts + geom_vline(xintercept = 3, colour = "red", linewidth = 1.5, linetype = "dashed"), "vline styled")
  check_seg(pts + geom_abline(intercept = 37, slope = -5), "abline")
  check_seg(pts + geom_abline(aes(intercept = a, slope = b, colour = f), data.frame(a = c(30, 10, 20), b = c(-4, 3, 0), f = c("p", "q", "r"))),
    "abline legend, flat slope")
  check_seg(pts + geom_vline(aes(xintercept = wt, colour = factor(gear)), data.frame(wt = c(2, 3, 4), gear = 3:5)),
    "vline legend")
  check_seg(pts + geom_hline(aes(yintercept = y, linetype = f), data.frame(y = c(15, 30), f = c("u", "v"))), "hline legend")
  check_seg(pts + geom_hline(yintercept = 20) + geom_vline(xintercept = 3) + facet_wrap(vars(cyl), scales = "free"),
    "reference lines, free facets")
  check_seg(pts + geom_hline(yintercept = c(20, 20, 20), alpha = 0.3), "duplicated lines")
  check_seg(pts + geom_hline(yintercept = 100), "line outside the panel")
  check_seg(pts + geom_abline(slope = 0, intercept = 25), "abline slope 0")
})

test_that("rugs draw as ggplot2 draws them", {
  check_seg(pts + geom_rug(), "rug")
  check_seg(pts + geom_rug(aes(colour = factor(cyl)), sides = "trbl", length = unit(0.05, "npc")), "rug all sides, legend")
  check_seg(ggplot(mtcars, aes(wt)) + geom_density() + geom_rug(alpha = 0.5, linewidth = 1), "rug x only")
  check_seg(pts + geom_rug(sides = "r") + facet_wrap(vars(am), scales = "free_y"), "rug facets")
  check_seg(pts + geom_rug(outside = TRUE), "rug outside, clipped")
  na <- mtcars
  na$wt[1:3] <- NA
  na$mpg[4] <- NA
  # ggplot2 warns of the rows GeomRug$handle_na() removes.
  suppressWarnings(check_seg(ggplot(na, aes(wt, mpg)) + geom_rug(), "rug with NA"))
})

test_that("missing, infinite, empty and single-row segment data", {
  inf <- segs
  inf$xend[1] <- Inf
  inf$y[2] <- -Inf
  check_seg(ggplot(inf, aes(x, y, xend = xend, yend = yend)) + geom_segment(), "Inf")
  check_seg(sp %+% segs[0, ] + geom_segment(), "no rows")
  check_seg(sp %+% segs[1, ] + geom_segment(), "single row")
  check_seg(ggplot(data.frame(x = 1:3, y = 1:3), aes(x, y, xend = x + 1L, yend = y)) + geom_segment(), "integers")
  check_seg(pts + geom_hline(yintercept = 20L), "integer intercept")
})

test_that("segments the full tier doesn't draw decline to another tier", {
  reason <- function(p) {
    set.seed(1)
    attr(render_full(suppressWarnings(suppressMessages(ggplot_build(p))), render_size), "reason")
  }
  expect_match(reason(sp + geom_curve()), "layers other than")
  expect_match(reason(sp + geom_segment(arrow = arrow())), "arrows")
  expect_match(reason(sp + geom_segment() + coord_flip()), "coord")
  expect_match(reason(pts + geom_hline(yintercept = 20) + coord_cartesian(clip = "off")), "clip")
  expect_match(reason(pts + geom_rug(length = unit(2, "mm"))), "npc")
  expect_match(reason(pts + geom_vline(xintercept = 3, lineend = "foo")), "lineend")
  gap <- segs
  gap$yend[2] <- NA
  expect_match(reason(ggplot(gap, aes(x, y, xend = xend, yend = yend)) + geom_segment()), "NA in positions")
  cov <- alot_render_coverage(pts + geom_hline(yintercept = 20))
  expect_identical(cov$tier, "full")
})
