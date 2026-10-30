# Batched labeling::extended() (T5.2): breaks for 400 axis ranges, as for a
# 400-panel free-scale facet, via scales::extended_breaks() per range vs one
# rs_extended_breaks() call. Runs sequentially with reps interleaved.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/extended-breaks.R")'
set.seed(42)
n <- 400
ranges <- t(replicate(n, range(stats::rnorm(50, runif(1, -100, 100), 10^runif(1, -2, 3)))))
m <- rep(5, n)
r_breaks <- function() lapply(seq_len(n), function(i) scales::extended_breaks()(ranges[i, ]))
rust_breaks <- function() rs_extended_breaks(ranges[, 1], ranges[, 2], m)
stopifnot(identical(r_breaks(), rust_breaks()))

reps <- 21
times <- matrix(NA_real_, reps, 2, dimnames = list(NULL, c("labeling", "alot")))
for (i in seq_len(reps)) {
  gc()
  times[i, 1] <- system.time(r_breaks())[["elapsed"]]
  gc()
  times[i, 2] <- system.time(for (k in 1:10) rust_breaks())[["elapsed"]] / 10
}
med <- apply(times, 2, stats::median) * 1000
cat(sprintf("%d ranges: labeling %.2f ms, alot %.3f ms, %.0fx\n", n, med[1], med[2], med[1] / med[2]))
