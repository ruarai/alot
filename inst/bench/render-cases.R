# Cases for the render benchmarks: render-suite.R (time per stage, ggplot2
# vs the hybrid tier) and render-e2e.R (alot_png() end to end, in the tier it
# picks, vs ggsave() on ragg) source this file.
source("inst/bench/cases.R")

readme_data <- function(n) {
  data.frame(
    income = exp(stats::rnorm(n, 10, 1)),
    spend = stats::runif(n, 0, 100),
    age = sample(18:90, n, TRUE),
    region = factor(sample(c("North", "South", "East", "West", "Central", "Islands"), n, TRUE)),
    segment = factor(sample(c("A", "B", "C", "D"), n, TRUE))
  )
}

# The README example plot.
readme_plot <- function(n) {
  ggplot(readme_data(n), aes(income, spend, colour = age, shape = segment)) +
    geom_point(alpha = 0.3) +
    scale_x_log10() +
    scale_colour_viridis_c() +
    facet_wrap(~region)
}

readme_size <- list(width = 1600, height = 1000, units = "px", res = 150)
page_size <- list(width = 7, height = 7, units = "in", res = 300)

render_cases <- list(
  readme = list(plot = function() readme_plot(1e6), size = readme_size),
  readme_page = list(plot = function() readme_plot(1e6), size = page_size),
  readme_10 = list(plot = function() readme_plot(10), size = readme_size, reps = 7L),
  point_1e6 = list(
    plot = function() {
      ggplot(data.frame(x = stats::rnorm(1e6), y = stats::rnorm(1e6)), aes(x, y)) +
        geom_point() + theme_void()
    },
    size = readme_size
  ),
  size_1e4 = list(
    plot = function() {
      d <- data.frame(x = stats::runif(1e4), y = stats::runif(1e4), s = stats::runif(1e4))
      ggplot(d, aes(x, y, size = s)) + geom_point(alpha = 0.5)
    },
    size = readme_size
  ),
  tile_1000 = list(
    plot = function() {
      d <- expand.grid(x = 1:1000, y = 1:1000)
      d$z <- stats::runif(nrow(d))
      ggplot(d, aes(x, y, fill = z)) + geom_tile() + theme_void() +
        theme(legend.position = "none")
    },
    size = readme_size
  ),
  line_1e6 = list(
    plot = function() {
      ggplot(data.frame(x = seq_len(1e6), y = cumsum(stats::rnorm(1e6))), aes(x, y)) + geom_line()
    },
    size = readme_size
  ),
  facets_400 = list(
    plot = function() {
      d <- data.frame(x = stats::rnorm(2e4), y = stats::rnorm(2e4), p = factor(rep(1:400, each = 50)))
      ggplot(d, aes(x, y)) + geom_point(size = 0.5) + facet_wrap(~p)
    },
    size = readme_size
  ),
  # R6.3: facet_grid() with free scales and free space.
  grid_free_1e6 = list(
    plot = function() {
      d <- data.frame(x = stats::rnorm(1e6), y = stats::rexp(1e6), a = sample(letters[1:3], 1e6, TRUE), b = sample(LETTERS[1:4], 1e6, TRUE))
      d$x <- d$x * match(d$b, LETTERS)
      ggplot(d, aes(x, y)) + geom_point(size = 0.3) + facet_grid(a ~ b, scales = "free", space = "free_x")
    },
    size = readme_size
  ),
  # R6.4: colour steps and size bins (binned scales, so few distinct
  # point sizes), in a box inside the panel.
  legends_inside_1e6 = list(
    plot = function() {
      d <- data.frame(x = stats::rnorm(1e6), y = stats::rnorm(1e6), z = stats::runif(1e6), w = stats::rexp(1e6))
      ggplot(d, aes(x, y, colour = z, size = w)) + geom_point(alpha = 0.3) + scale_colour_binned() +
        scale_size_binned(range = c(0.2, 2)) +
        theme(legend.position = "inside", legend.position.inside = c(0.95, 0.95), legend.justification.inside = c(1, 1),
              legend.box.background = element_rect(), legend.box.margin = margin_auto(4))
    },
    size = readme_size
  ),
  # R6.5a: stacked areas of 1e6 rows (stat_align, outline.type "upper")
  # and a smooth's ribbon and line by group.
  area_1e6 = list(
    plot = function() {
      d <- data.frame(x = rep(seq_len(2.5e5), 4), g = rep(letters[1:4], each = 2.5e5), y = stats::runif(1e6))
      ggplot(d, aes(x, y, fill = g)) + geom_area(colour = "black")
    },
    size = readme_size
  ),
  # R6.5b: 1e5 error bars (three polylines each) coloured by group, and
  # boxplots of 1e6 rows with their outliers.
  errorbar_1e5 = list(
    plot = function() {
      d <- data.frame(x = seq_len(1e5), g = rep(letters[1:4], 2.5e4), y = stats::runif(1e5))
      ggplot(d, aes(x, ymin = y - 0.1, ymax = y + 0.1, colour = g)) + geom_errorbar()
    },
    size = readme_size
  ),
  boxplot_1e6 = list(
    plot = function() {
      d <- data.frame(g = rep(letters[1:10], 1e5), y = stats::rnorm(1e6))
      ggplot(d, aes(g, y, fill = g)) + geom_boxplot(notch = TRUE)
    },
    size = readme_size
  ),
  # R6.5c: 1e5 segments coloured by group.
  segment_1e5 = list(
    plot = function() {
      d <- data.frame(x = stats::runif(1e5), y = stats::runif(1e5), g = rep(letters[1:4], 2.5e4))
      ggplot(d, aes(x, y, xend = x + 0.02, yend = y + 0.01, colour = g)) + geom_segment()
    },
    size = readme_size
  ),
  # R6.5d: 2000 overlapping labels filled by group; 1e4 triangles.
  label_2e3 = list(
    plot = function() {
      d <- data.frame(x = stats::runif(2000), y = stats::runif(2000), g = rep(letters[1:4], 500))
      ggplot(d, aes(x, y, label = g, fill = g)) + geom_label()
    },
    size = readme_size
  ),
  polygon_1e4 = list(
    plot = function() {
      n <- 1e4
      cx <- rep(stats::runif(n), each = 3)
      cy <- rep(stats::runif(n), each = 3)
      d <- data.frame(x = cx + c(0, 0.01, 0.005), y = cy + c(0, 0, 0.01), g = rep(seq_len(n), each = 3), f = rep(letters[1:4], each = 3, length.out = 3 * n))
      ggplot(d, aes(x, y, group = g, fill = f)) + geom_polygon(colour = "black", linewidth = 0.2)
    },
    size = readme_size
  ),
  # R6.6: 1e5 points under coord_flip() and under coord_transform().
  flip_1e5 = list(
    plot = function() {
      d <- data.frame(x = stats::rnorm(1e5), y = stats::rnorm(1e5), g = rep(letters[1:4], 2.5e4))
      ggplot(d, aes(x, y, colour = g)) + geom_point() + coord_flip()
    },
    size = readme_size
  ),
  transform_1e5 = list(
    plot = function() {
      d <- data.frame(x = stats::rlnorm(1e5), y = stats::rlnorm(1e5), g = rep(letters[1:4], 2.5e4))
      ggplot(d, aes(x, y, colour = g)) + geom_point() + coord_transform(x = "log10", y = "log10")
    },
    size = readme_size
  )
)
