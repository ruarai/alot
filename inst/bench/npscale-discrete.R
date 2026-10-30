# Discrete non-position scales (T2.4): npscales_train_df() and
# npscales_map_df() for one aesthetic column of 1e6 values through one
# scale, kernels off vs on. Runs sequentially with ggplot2 and alot reps
# interleaved; this is the kernels' 1.25x check. Columns hold 5-10 distinct
# values plus 1% NA, in random order.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/npscale-discrete.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
with_na <- function(x) {
  x[sample(n, n / 100)] <- NA
  x
}
chr <- with_na(sample(letters[1:10], n, TRUE))
fct <- with_na(factor(sample(letters[1:5], n, TRUE)))
lgl <- with_na(sample(c(TRUE, FALSE), n, TRUE))
inputs <- list(
  hue_character = list(x = chr, aes = "colour", scale = scale_colour_hue),
  hue_factor = list(x = fct, aes = "colour", scale = scale_colour_hue),
  brewer_factor = list(x = fct, aes = "fill", scale = scale_fill_brewer),
  manual_named = list(x = chr, aes = "colour", scale = function() {
    scale_colour_manual(values = stats::setNames(grDevices::rainbow(10), rev(letters[1:10])))
  }),
  shape_factor = list(x = fct, aes = "shape", scale = scale_shape),
  linetype_character = list(x = chr, aes = "linetype", scale = function() {
    scale_linetype_manual(values = rep(c("solid", "dashed"), 5))
  }),
  hue_logical = list(x = lgl, aes = "colour", scale = scale_colour_hue)
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
  df <- stats::setNames(data.frame(inputs[[name]]$x), inputs[[name]]$aes)
  trained <- scales_of(inputs[[name]]$scale())
  alot_ns$npscales_train_df(trained, df)
  # A clone() would have untrained limits; map() only fills the palette
  # cache, the same on both paths.
  mapped <- function(kernels) {
    options(alot.kernels = kernels)
    alot_ns$npscales_map_df(trained, df)
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

cat("## Discrete non-position scales at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
