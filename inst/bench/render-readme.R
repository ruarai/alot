# Hybrid tier: end-to-end time for the README example plot (1e6
# points, facet_wrap, log x, continuous colour, discrete shape) drawn to a
# 1600 x 1000 PNG at 150 dpi with ragg. ggplot2: ggplot_build() +
# ggplot_gtable() + grid drawing; alot: alot_build() + the hybrid gtable (points
# rasterised in Rust) + grid drawing on agg_capture, encoded to PNG in Rust
# (what alot_png() does). Medians of interleaved runs. Also
# compares the two images pixel by pixel.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/render-readme.R")'
library(ggplot2)

set.seed(42)
n <- as.numeric(Sys.getenv("ALOT_BENCH_SIZES", "1e6"))
d <- data.frame(
  income = exp(rnorm(n, 10, 1)),
  spend = runif(n, 0, 100),
  age = sample(18:90, n, TRUE),
  region = factor(sample(c("North", "South", "East", "West", "Central", "Islands"), n, TRUE)),
  segment = factor(sample(c("A", "B", "C", "D"), n, TRUE))
)
p <- ggplot(d, aes(income, spend, colour = age, shape = segment)) +
  geom_point(alpha = 0.3) +
  scale_x_log10() +
  scale_colour_viridis_c() +
  facet_wrap(~region)

out_dir <- Sys.getenv("ALOT_BENCH_OUT", tempdir())
size <- list(width = 1600, height = 1000, units = "px", res = 150)

draw <- function(g, file) {
  do.call(ragg::agg_png, c(list(file), size))
  grid::grid.newpage()
  grid::grid.draw(g)
  grDevices::dev.off()
}

# alot_png()'s drawing step.
draw_alot <- function(g, file) {
  cap <- do.call(ragg::agg_capture, size)
  grid::grid.newpage()
  grid::grid.draw(g)
  alot_ns$rs_write_png(cap(native = TRUE), file)
  grDevices::dev.off()
}

secs <- function(expr) {
  t <- proc.time()[["elapsed"]]
  force(expr)
  proc.time()[["elapsed"]] - t
}

alot_ns <- asNamespace("alot")
paths <- list(
  ggplot2 = list(build = ggplot_build, gtable = ggplot_gtable, draw = draw),
  alot = list(build = alot_build, gtable = alot_ns$hybrid_gtable, draw = draw_alot)
)
reps <- as.integer(Sys.getenv("ALOT_BENCH_REPS", "5"))
runs <- list()
for (i in seq_len(reps)) {
  for (name in names(paths)) {
    f <- paths[[name]]
    file <- file.path(out_dir, paste0("readme-", name, ".png"))
    gc(FALSE)
    t_build <- secs(b <- f$build(p))
    t_gtable <- secs(g <- f$gtable(b))
    t_draw <- secs(f$draw(g, file))
    runs[[length(runs) + 1]] <- data.frame(
      path = name, step = c("build", "gtable", "draw", "total"),
      seconds = c(t_build, t_gtable, t_draw, t_build + t_gtable + t_draw)
    )
  }
}
runs <- do.call(rbind, runs)
med <- aggregate(seconds ~ path + step, runs, stats::median)
tab <- reshape(med, idvar = "step", timevar = "path", direction = "wide")
tab <- tab[match(c("build", "gtable", "draw", "total"), tab$step), ]
cat(sprintf("%-7s %9s %9s %8s\n", "step", "ggplot2", "alot", "speedup"))
cat(sprintf("%-7s %8.0fms %8.0fms %7.1fx\n", tab$step, 1000 * tab$seconds.ggplot2,
  1000 * tab$seconds.alot, tab$seconds.ggplot2 / tab$seconds.alot), sep = "")

# Pixel comparison on the same built plot.
capture <- function(g) {
  cap <- ragg::agg_capture(width = size$width, height = size$height, units = "px", res = size$res)
  grid::grid.newpage()
  grid::grid.draw(g)
  m <- cap(native = FALSE)
  grDevices::dev.off()
  grDevices::col2rgb(m)
}
b <- ggplot_build(p)
diff <- abs(capture(ggplot_gtable(b)) - capture(alot_ns$hybrid_gtable(b)))
px <- apply(diff, 2, max)
cat(sprintf(
  "\npixels: mean |diff| %.3f, max %d; %.3f%% differ by > 8, %.3f%% by > 32 (of 255)\n",
  mean(diff), max(diff), 100 * mean(px > 8), 100 * mean(px > 32)
))
cat("images:", out_dir, "\n")
