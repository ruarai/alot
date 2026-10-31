library(ggplot2)

# Layout$setup_panel_guides for CoordCartesian and CoordFixed (T5.4): axis
# guides trained once per distinct x and y scale. expect_build_equal()
# compares panel_params field by field, including the Guides objects.

guides_path <- function(p) {
  cov <- suppressWarnings(alot_coverage(p))
  cov$path[cov$step == "setup_panel_guides"]
}
expect_panel_guides <- function(p, path = "rust") {
  expect_identical(guides_path(p), path)
  suppressWarnings(expect_build_equal(p))
}

set.seed(1)
df <- data.frame(
  x = c(stats::rnorm(60, 10, 3), NA, Inf), y = c(stats::runif(60, -5, 5), 1, 2),
  i = c(sample(1:50, 60, TRUE), 1L, 2L),
  f = factor(sample(c("a", "b", "c"), 62, TRUE)), g = sample(c("u", "v"), 62, TRUE),
  d = as.Date("2020-01-01") + sample(0:400, 62, TRUE)
)
point <- ggplot(df, aes(x, y)) + geom_point()

test_that("coords and scales match ggplot2", {
  for (p in list(
    point,
    point + coord_fixed(),
    point + coord_equal(ratio = 2),
    point + coord_cartesian(xlim = c(5, 15), ylim = c(-10, 0)),
    point + coord_cartesian(xlim = c(15, 5)),
    point + coord_cartesian(expand = FALSE),
    point + scale_x_log10() + scale_y_sqrt(),
    point + scale_x_reverse(),
    point + scale_x_continuous(n.breaks = 9),
    point + scale_x_continuous(breaks = c(0, 7, 21)),
    point + scale_x_continuous(labels = function(x) paste0(x, "!")),
    point + scale_x_continuous(breaks = c(0, 7, 21), labels = c("a", "b", "c")),
    point + scale_x_continuous(limits = c(0, NA)),
    point + scale_x_continuous(position = "top") + scale_y_continuous(position = "right"),
    point + theme(axis.text.x = element_text(angle = 45)),
    ggplot(df, aes(i, y)) + geom_point(),
    ggplot(df, aes(d, y)) + geom_point(),
    ggplot(df, aes(as.POSIXct(d), y)) + geom_point(),
    ggplot(df, aes(f, y)) + geom_boxplot(),
    ggplot(df, aes(f, g)) + geom_count(),
    ggplot(df, aes(f, y)) + geom_boxplot() + scale_x_discrete(limits = c("c", "a")),
    point + scale_x_binned(),
    ggplot(data.frame(x = 1, y = 2), aes(x, y)) + geom_point(),
    ggplot(df, aes(y = y)) + geom_boxplot()
  )) {
    expect_panel_guides(p)
  }
})

test_that("facets with free and shared scales match ggplot2", {
  for (p in list(
    point + facet_wrap(~f),
    point + facet_wrap(~f, scales = "free"),
    point + facet_wrap(~f, scales = "free_x"),
    point + facet_grid(g ~ f, scales = "free"),
    point + facet_grid(g ~ f, scales = "free_y"),
    point + facet_grid(g ~ f, scales = "free", space = "free"),
    point + facet_grid(g ~ f, scales = "free") + coord_fixed(),
    point + facet_wrap(~f, scales = "free") + scale_x_log10(),
    point + facet_wrap(~f, scales = "free", axes = "all"),
    ggplot(df, aes(f, g)) + geom_count() + facet_wrap(~f, scales = "free")
  )) {
    expect_panel_guides(p)
  }
})

test_that("panels share guides exactly as ggplot2's do, and no more", {
  p <- point + facet_grid(g ~ f, scales = "free_x")
  a <- alot_build(p)@layout$panel_params
  b <- ggplot_build(p)@layout$panel_params
  same <- function(pp) outer(seq_along(pp), seq_along(pp), Vectorize(function(i, j) identical(pp[[i]]$guides, pp[[j]]$guides)))
  expect_identical(same(a), same(b))
  # Changing one panel's guide parameters leaves the others alone.
  key <- a[[2]]$guides$params[[1]]$key
  a[[1]]$guides$params[[1]]$key$x <- 0
  a[[1]]$guides$guides[[1]]$params$title <- "changed"
  expect_identical(a[[2]]$guides$params[[1]]$key, key)
  expect_false(identical(a[[2]]$guides$guides[[1]]$params$title, "changed"))
})

test_that("unsupported cases fall back to ggplot2", {
  # User guides, on the plot or the scale.
  expect_panel_guides(point + guides(x = guide_axis(angle = 90)), "ggplot2")
  expect_panel_guides(point + guides(y = "none"), "ggplot2")
  expect_panel_guides(point + scale_x_continuous(guide = guide_axis(minor.ticks = TRUE)), "ggplot2")
  expect_panel_guides(point + scale_y_continuous(guide = guide_axis(cap = "both")), "ggplot2")
  expect_panel_guides(point + scale_x_continuous(guide = guide_axis_logticks()), "ggplot2")
  # A secondary axis.
  expect_panel_guides(point + scale_x_continuous(sec.axis = sec_axis(~ . * 2)), "ggplot2")
  # No breaks, so no key.
  expect_panel_guides(point + scale_x_continuous(breaks = NULL), "ggplot2")
  expect_panel_guides(point + scale_x_continuous(breaks = 1e6), "ggplot2")
  expect_panel_guides(ggplot() + geom_blank(), "ggplot2")
  # A range that is not finite or has zero width.
  expect_panel_guides(point + coord_cartesian(xlim = c(5, 5), expand = FALSE), "ggplot2")
  expect_panel_guides(ggplot(data.frame(x = 1, y = 2), aes(x, y)) + geom_point() + coord_cartesian(expand = FALSE), "ggplot2")
  # Reversed coords, and coords other than CoordCartesian and CoordFixed.
  expect_panel_guides(point + coord_cartesian(reverse = "x"), "ggplot2")
  expect_panel_guides(point + coord_flip(), "ggplot2")
  expect_panel_guides(point + coord_trans(x = "sqrt"), "ggplot2")
  expect_panel_guides(point + coord_polar(), "ggplot2")
  # A coord whose train_panel_guides is overridden, and a subclass.
  p <- point
  p@coordinates <- ggproto(NULL, coord_cartesian(), train_panel_guides = function(self, panel_params, layers, params = list()) {
    ggproto_parent(CoordCartesian, self)$train_panel_guides(panel_params, layers, params)
  })
  expect_panel_guides(p, "ggplot2")
  p@coordinates <- ggproto(NULL, ggproto("MyCoord", CoordCartesian))
  expect_panel_guides(p, "ggplot2")
  # A facet that alters panel params.
  MyFacet <- ggproto("MyFacet", FacetNull, setup_panel_params = function(self, panel_params, coord, ...) panel_params)
  p <- point
  p@facet <- ggproto(NULL, MyFacet)
  expect_panel_guides(p, "ggplot2")
  # A layout with an overridden setup_panel_guides.
  p <- point
  p@layout <- ggproto(NULL, Layout, setup_panel_guides = function(self, guides, layers) {
    ggproto_parent(Layout, self)$setup_panel_guides(guides, layers)
  })
  expect_panel_guides(p, "ggplot2")
})

test_that("a guide perpendicular to its axis still warns", {
  p <- point + guides(x = guide_axis(position = "left"))
  expect_panel_guides(p, "ggplot2")
})
