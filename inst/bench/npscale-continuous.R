# Continuous colour scales (T2.3): npscales_train_df() and npscales_map_df()
# for one colour column of 1e6 values through one scale, kernels off vs on.
# Runs sequentially with ggplot2 and alot reps interleaved; this is the
# kernels' 1.25x check. Doubles are rnorm() with 1% NA; integers are
# 1-1000 with NA, so the palette sees few unique values.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/npscale-continuous.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
dbl <- stats::rnorm(n)
dbl[sample(n, n / 100)] <- NA
ints <- sample(c(1:1000, NA), n, TRUE)
inputs <- list(
  gradient = list(x = dbl, scale = scale_colour_continuous),
  gradient_integer = list(x = ints, scale = scale_colour_continuous),
  gradient2 = list(x = dbl, scale = function() scale_colour_gradient2(midpoint = 0.5)),
  gradientn_values = list(x = dbl, scale = function() {
    scale_colour_gradientn(colours = grDevices::terrain.colors(7), values = c(0, 0.1, 0.2, 0.5, 0.6, 0.9, 1))
  }),
  distiller = list(x = dbl, scale = scale_colour_distiller),
  viridis = list(x = dbl, scale = scale_colour_viridis_c),
  viridis_alpha = list(x = dbl, scale = function() scale_colour_viridis_c(alpha = 0.5))
)

scales_of <- function(scale) {
  scales <- ggplot2:::scales_list()
  scales$add(scale)
  scales
}

# Seconds for `f()`, after a full gc so neither path pays for the other's
# garbage. Sys.time() rather than system.time(), whose 1 ms resolution is
# too coarse for these steps.
time_step <- function(f, kernels) {
  old <- options(alot.kernels = kernels)
  on.exit(options(old))
  gc(FALSE)
  start <- Sys.time()
  f()
  as.double(Sys.time() - start, units = "secs")
}

reps <- 15L
rows <- list()
for (name in names(inputs)) {
  progress(name)
  df <- data.frame(colour = inputs[[name]]$x)
  trained <- scales_of(inputs[[name]]$scale())
  alot_ns$npscales_train_df(trained, df)
  mapped <- function(kernels) {
    options(alot.kernels = kernels)
    alot_ns$npscales_map_df(scales_of(trained$scales[[1]]$clone()), df)
  }
  stopifnot(identical(mapped(FALSE), mapped(TRUE)))

  steps <- list(
    train = function() alot_ns$npscales_train_df(scales_of(inputs[[name]]$scale()), df),
    map = function() alot_ns$npscales_map_df(trained, df)
  )
  for (step in names(steps)) {
    off <- on <- double(reps)
    for (r in seq_len(reps)) {
      off[r] <- time_step(steps[[step]], FALSE)
      on[r] <- time_step(steps[[step]], TRUE)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      input = name, step = step,
      ggplot2_ms = round(1000 * stats::median(off), 1), alot_ms = round(1000 * stats::median(on), 1),
      speedup = sprintf("%.1fx", stats::median(off) / stats::median(on))
    )
  }
}

cat("## Continuous colour scales at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
