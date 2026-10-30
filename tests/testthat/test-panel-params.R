library(ggplot2)

# Layout$setup_panel_params for CoordCartesian, CoordFlip and CoordFixed
# (T5.3): view scales built once per distinct x and y scale, extended breaks
# batched in Rust. expect_build_equal() compares panel_params field by
# field, including the ViewScale objects and the frames their `super`
# closures capture.

panel_path <- function(p) {
  cov <- suppressWarnings(alot_coverage(p))
  cov$path[cov$step == "setup_panel_params"]
}
expect_panel_params <- function(p, path = "rust") {
  expect_identical(panel_path(p), path)
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

test_that("coords match ggplot2", {
  for (p in list(
    point,
    point + coord_flip(),
    point + coord_fixed(),
    point + coord_equal(ratio = 2),
    point + coord_cartesian(xlim = c(5, 15), ylim = c(-10, 0)),
    point + coord_cartesian(expand = FALSE),
    point + coord_cartesian(expand = c(top = FALSE, left = FALSE)),
    point + coord_flip(xlim = c(0, 20), expand = c(bottom = FALSE)),
    point + coord_cartesian(reverse = "x"),
    point + coord_cartesian(reverse = "xy")
  )) {
    expect_panel_params(p)
  }
})

test_that("continuous scale variants match ggplot2", {
  for (p in list(
    point + scale_x_log10() + scale_y_sqrt(),
    point + scale_x_reverse(),
    point + scale_x_continuous(n.breaks = 9) + scale_y_continuous(n.breaks = 3L),
    point + scale_x_continuous(breaks = c(0, 7, 21)),
    point + scale_x_continuous(breaks = NULL, minor_breaks = NULL),
    point + scale_x_continuous(breaks = function(l) seq(l[1], l[2], length.out = 4)),
    point + scale_x_continuous(breaks = scales::breaks_extended(n = 8)),
    point + scale_x_continuous(breaks = scales::breaks_extended(Q = c(1, 5))),
    point + scale_x_continuous(minor_breaks = function(l) seq(l[1], l[2], by = 1)),
    point + scale_x_continuous(minor_breaks = c(3, 4)),
    point + scale_x_continuous(limits = c(0, NA)),
    point + scale_x_continuous(limits = c(NA, 1e3), oob = scales::oob_keep),
    point + scale_x_continuous(expand = expansion(mult = c(0, 0.2))),
    point + scale_x_continuous(position = "top") + scale_y_continuous(position = "right") + coord_flip(),
    ggplot(df, aes(i, y)) + geom_point(),
    ggplot(df, aes(d, y)) + geom_point(),
    ggplot(df, aes(as.POSIXct(d), y)) + geom_point(),
    point + scale_x_binned(),
    # Zero-width data, a single row, and no x data at all.
    ggplot(data.frame(x = 1, y = 2), aes(x, y)) + geom_point(),
    ggplot(data.frame(x = c(1e-300, 2e-300), y = 1:2), aes(x, y)) + geom_point(),
    ggplot(data.frame(x = c(1e300, -1e300), y = 1:2), aes(x, y)) + geom_point(),
    ggplot(df, aes(y = y)) + geom_boxplot(),
    ggplot() + geom_blank()
  )) {
    expect_panel_params(p)
  }
})

test_that("discrete scales match ggplot2", {
  box <- ggplot(df, aes(f, y)) + geom_boxplot()
  for (p in list(
    box, box + coord_flip(), box + scale_x_discrete(limits = c("c", "a")),
    box + scale_x_discrete(expand = expansion(add = 2)),
    ggplot(df, aes(f, g)) + geom_count(),
    ggplot(df, aes(f, g)) + geom_count() + facet_wrap(~f, scales = "free")
  )) {
    expect_panel_params(p)
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
    point + facet_grid(g ~ f, scales = "free") + coord_flip(),
    point + facet_wrap(~f, scales = "free") + scale_x_log10()
  )) {
    expect_panel_params(p)
  }
})

test_that("panels share view scales exactly as ggplot2's do, and no more", {
  # x is free by column, y shared: panels 1 and 2 (row 1) have the same y
  # scale but different COORDs.
  p <- point + facet_grid(g ~ f, scales = "free_x")
  a <- alot_build(p)@layout$panel_params
  b <- ggplot_build(p)@layout$panel_params
  share <- function(pp, aes) outer(seq_along(pp), seq_along(pp), Vectorize(function(i, j) identical(pp[[i]][[aes]], pp[[j]][[aes]])))
  for (aes in c("x", "x.sec", "y", "y.sec")) {
    expect_identical(share(a, aes), share(b, aes))
  }
  # Changing one panel's y view scales leaves the other's alone.
  expect_false(identical(a[[1]]$y, a[[2]]$y))
  title <- a[[2]]$y.sec$guide$params$title
  a[[1]]$y$breaks <- 0
  a[[1]]$y.sec$guide$params$title <- "changed"
  expect_false(identical(a[[2]]$y$breaks, 0))
  expect_identical(a[[2]]$y.sec$guide$params$title, title)
})

test_that("unsupported cases fall back to ggplot2", {
  # A secondary axis.
  expect_panel_params(point + scale_x_continuous(sec.axis = sec_axis(~ . * 2)), "ggplot2")
  expect_panel_params(point + scale_y_continuous(sec.axis = dup_axis()) + coord_flip(), "ggplot2")
  # Other coords have no kernel.
  expect_panel_params(point + coord_trans(x = "sqrt"), "ggplot2")
  expect_panel_params(point + coord_polar(), "ggplot2")
  # A coord whose setup_panel_params is overridden.
  coord <- coord_cartesian()
  p <- point
  p@coordinates <- ggproto(NULL, coord, setup_panel_params = function(self, scale_x, scale_y, params = list()) {
    ggproto_parent(CoordCartesian, self)$setup_panel_params(scale_x, scale_y, params)
  })
  expect_panel_params(p, "ggplot2")
  # A coord subclass.
  MyCoord <- ggproto("MyCoord", CoordCartesian)
  p@coordinates <- ggproto(NULL, MyCoord)
  expect_panel_params(p, "ggplot2")
  # A layout with an overridden setup_panel_params.
  p <- point
  p@layout <- ggproto(NULL, Layout, setup_panel_params = function(self) {
    ggproto_parent(Layout, self)$setup_panel_params()
  })
  expect_panel_params(p, "ggplot2")
})

test_that("the breaks plan recognises only plain breaks_extended()", {
  expect_true(is_extended_breaks(scales::breaks_extended()))
  expect_true(is_extended_breaks(scales::extended_breaks(n = 3)))
  expect_true(is_extended_breaks(scales::transform_identity()$breaks))
  expect_false(is_extended_breaks(scales::breaks_extended(Q = c(1, 5))))
  expect_false(is_extended_breaks(scales::breaks_log()))
  expect_false(is_extended_breaks(c(1, 2)))
  expect_false(is_extended_breaks(NULL))
})
