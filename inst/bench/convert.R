# Interchange-layer overhead (T0.3). Reading columns as views and passing
# them back must not copy: pass-through time stays flat as rows grow, while
# rebuilding every column from its view (copy = TRUE) scales with n.
#
#   NOT_CRAN=true Rscript -e 'pkgload::load_all(); source("inst/bench/convert.R")'
frame <- function(n) {
  data.frame(
    x = runif(n), y = sample.int(100L, n, TRUE), z = runif(n) > 0.5,
    PANEL = factor(sample.int(4L, n, TRUE)), group = sample.int(10L, n, TRUE)
  )
}

time_ms <- function(expr, reps = 20) {
  expr <- substitute(expr)
  env <- parent.frame()
  t <- vapply(seq_len(reps), function(i) system.time(eval(expr, env))[["elapsed"]], double(1))
  1000 * stats::median(t)
}

res <- do.call(rbind, lapply(c(1e4, 1e6, 1e7), function(n) {
  df <- frame(n)
  data.frame(
    rows = format(n, scientific = TRUE),
    view_ms = time_ms(rs_convert_roundtrip(df, FALSE)),
    copy_ms = time_ms(rs_convert_roundtrip(df, TRUE), reps = 5),
    rebuild_frame_ms = time_ms(rebuild_frame(rs_convert_roundtrip(df, FALSE), df))
  )
}))
print(res, row.names = FALSE)
