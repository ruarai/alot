# Grouped-driver overhead (T0.4). Times Stat$compute_layer for a trivial
# identity-style stat (compute_group returns x, y and the group size) against
# the same stat run through the driver with its Rust twin. Both pay
# remove_missing(); the difference is dapply()/split()/vec_rbind() versus one
# Rust pass plus the R assembly.
#
#   NOT_CRAN=true Rscript -e 'pkgload::load_all(); source("inst/bench/grouped.R")'
#
# For release-build numbers, install first (R CMD INSTALL with NOT_CRAN set
# builds --release) and run with library(alot) instead of load_all().
ns <- asNamespace("alot")
library(ggplot2)

StatBenchGrouped <- ggproto("StatBenchGrouped", Stat,
  required_aes = c("x", "y"),
  compute_group = function(data, scales) {
    ns$gg_data_frame0(x = data$x, y = data$y, n = nrow(data))
  }
)

layer_frame <- function(n, panels, groups) {
  data.frame(
    x = runif(n), y = runif(n),
    PANEL = factor(sample.int(panels, n, TRUE), levels = seq_len(panels)),
    group = sample.int(groups, n, TRUE),
    colour = "black", size = 1.5
  )
}

time_ms <- function(expr, reps = 5) {
  expr <- substitute(expr)
  env <- parent.frame()
  t <- vapply(seq_len(reps), function(i) system.time(eval(expr, env))[["elapsed"]], double(1))
  1000 * stats::median(t)
}

layout <- ggplot_build(ggplot(mtcars, aes(wt, mpg)) + geom_point())@layout
layout$get_scales <- function(i) list(x = NULL, y = NULL)
params <- list(na.rm = FALSE)
run <- function(data, params) ns$rs_grouped_test_stat(data, c("x", "y"))

cases <- expand.grid(rows = c(1e4, 1e6), panels = c(1, 4, 400), groups = c(1, 10))
res <- do.call(rbind, lapply(seq_len(nrow(cases)), function(i) {
  cs <- cases[i, ]
  data <- layer_frame(cs$rows, cs$panels, cs$groups)
  stopifnot(isTRUE(all.equal(
    ns$stat_compute_grouped(StatBenchGrouped, data, params, run),
    StatBenchGrouped$compute_layer(data, params, layout)
  )))
  ggplot2_ms <- time_ms(StatBenchGrouped$compute_layer(data, params, layout))
  alot_ms <- time_ms(ns$stat_compute_grouped(StatBenchGrouped, data, params, run))
  data.frame(
    rows = format(cs$rows, scientific = TRUE), panels = cs$panels, groups = cs$groups,
    ggplot2_ms = ggplot2_ms, alot_ms = alot_ms, speedup = round(ggplot2_ms / alot_ms, 1)
  )
}))
print(res, row.names = FALSE)
