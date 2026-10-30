# Scale transforms (T1.3): the scales_transform_df() step for one column of
# 1e6 values through one transformed scale, kernels off vs on. Runs
# sequentially with ggplot2 and alot reps interleaved; this is the kernels'
# 1.25x check. The `zeros` inputs hold 1% zeros and negatives, so both of
# R's warnings fire (and are muffled here).
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/scale-transform.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
pos <- stats::rexp(n)
pos[sample(n, n / 100)] <- NA
zeros <- pos
zeros[sample(n, n / 100)] <- c(0, -1)
ints <- sample(c(1:1000, NA), n, TRUE)
inputs <- list(
  log10_double = list(x = pos, scale = scale_x_log10),
  log10_zeros = list(x = zeros, scale = scale_x_log10),
  log10_integer = list(x = ints, scale = scale_x_log10),
  sqrt_double = list(x = pos, scale = scale_x_sqrt),
  sqrt_zeros = list(x = zeros, scale = scale_x_sqrt),
  sqrt_integer = list(x = ints, scale = scale_x_sqrt),
  reverse_double = list(x = pos, scale = scale_x_reverse),
  reverse_integer = list(x = ints, scale = scale_x_reverse)
)

# Seconds for one scales_transform_df() call, after a full gc so neither
# path pays for the other's garbage. Sys.time() rather than system.time(),
# whose 1 ms resolution is too coarse for these steps.
time_transform <- function(scales, df, kernels) {
  old <- options(alot.kernels = kernels)
  on.exit(options(old))
  gc(FALSE)
  start <- Sys.time()
  suppressWarnings(alot_ns$scales_transform_df(scales, df))
  as.double(Sys.time() - start, units = "secs")
}

reps <- 15L
rows <- list()
for (name in names(inputs)) {
  progress(name)
  scales <- ggplot2:::scales_list()
  scales$add(inputs[[name]]$scale())
  df <- data.frame(x = inputs[[name]]$x, y = 1)
  stopifnot(identical(
    { options(alot.kernels = FALSE); suppressWarnings(alot_ns$scales_transform_df(scales, df)) },
    { options(alot.kernels = TRUE); suppressWarnings(alot_ns$scales_transform_df(scales, df)) }
  ))
  off <- on <- double(reps)
  for (r in seq_len(reps)) {
    off[r] <- time_transform(scales, df, FALSE)
    on[r] <- time_transform(scales, df, TRUE)
  }
  rows[[length(rows) + 1L]] <- data.frame(
    input = name,
    ggplot2_ms = round(1000 * stats::median(off), 1), alot_ms = round(1000 * stats::median(on), 1),
    speedup = sprintf("%.1fx", stats::median(off) / stats::median(on))
  )
}

cat("## Scale transforms at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
