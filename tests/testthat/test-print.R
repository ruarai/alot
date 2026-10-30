library(ggplot2)

test_that("alot_print draws the plot and returns it invisibly", {
  p <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point() + facet_wrap(~am)
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  expect_invisible(out <- alot_print(p))
  expect_identical(out, p)
  expect_identical(last_plot(), p)
  # The drawn plot is ggplot2's gtable of the alot build.
  expect_true(length(grid::grid.ls(print = FALSE)$name) > 0)
  expect_true(any(grepl("^layout$", grid::grid.ls(print = FALSE)$name)))
})

test_that("alot_print draws into a viewport", {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 2)))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  alot_print(p, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  expect_equal(sum(grid::grid.ls(print = FALSE)$name == "layout"), 2)
})

test_that("alot_print rejects non-ggplot input", {
  expect_error(alot_print(1), "ggplot object")
})
