# Position mapping (T1.2): the scale_map dispatch alone, kernels off vs on,
# for one column of 1e6 values mapped through 1 or 25 trained panel scales.
# Runs sequentially with ggplot2 and alot reps interleaved; this is the
# kernels' 1.25x check. The step-profile suite's map_position steps also
# include match(PANEL) and the data frame assignment, which this leaves out.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/scale-map.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
double_x <- stats::rnorm(n)
double_x[sample(n, n / 100)] <- NA
inputs <- list(
  double_censor = list(x = double_x, scale = function() scale_x_continuous(limits = c(-2, 2))),
  double_squish = list(x = double_x, scale = function() scale_x_continuous(limits = c(-2, 2), oob = scales::squish)),
  integer = list(x = sample(c(1:100, NA), n, TRUE), scale = scale_x_continuous),
  factor_10 = list(x = factor(sample(LETTERS[1:10], n, TRUE)), scale = scale_x_discrete),
  character_10 = list(x = sample(LETTERS[1:10], n, TRUE), scale = scale_x_discrete),
  character_1e4 = list(x = sample(sprintf("s%05d", 1:1e4), n, TRUE), scale = scale_x_discrete),
  logical = list(x = sample(c(TRUE, FALSE, NA), n, TRUE), scale = scale_x_discrete),
  mapped_discrete = list(
    x = ggplot2:::mapped_discrete(sample(1:10, n, TRUE) + 0.4 * stats::runif(n)),
    scale = scale_x_discrete
  )
)

# Panel scales trained on their slices, as map_position sees them.
trained_scales <- function(input, panels, scale_id) {
  scales <- lapply(seq_len(panels), function(i) input$scale()$clone())
  for (i in seq_len(panels)) scales[[i]]$train(input$x[scale_id == i])
  scales
}

# Seconds for one scales_map() call.
time_map <- function(df, scale_id, scales, kernels) {
  old <- options(alot.kernels = kernels)
  on.exit(options(old))
  gc(FALSE)
  system.time(alot_ns$scales_map(df, c(x = "x"), scale_id, scales))[["elapsed"]]
}

reps <- 7L
rows <- list()
for (name in names(inputs)) {
  for (panels in c(1, 25)) {
    progress(sprintf("%s, %d panels", name, panels))
    scale_id <- sort(rep(seq_len(panels), length.out = n))
    scales <- trained_scales(inputs[[name]], panels, scale_id)
    df <- data.frame(row = seq_len(n))
    df$x <- inputs[[name]]$x
    stopifnot(identical(
      { options(alot.kernels = FALSE); alot_ns$scales_map(df, c(x = "x"), scale_id, scales) },
      { options(alot.kernels = TRUE); alot_ns$scales_map(df, c(x = "x"), scale_id, scales) }
    ))
    off <- on <- double(reps)
    for (r in seq_len(reps)) {
      off[r] <- time_map(df, scale_id, scales, FALSE)
      on[r] <- time_map(df, scale_id, scales, TRUE)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      input = name, panels = as.character(panels),
      ggplot2_ms = 1000 * stats::median(off), alot_ms = 1000 * stats::median(on),
      speedup = sprintf("%.1fx", stats::median(off) / stats::median(on))
    )
  }
}

cat("## Position mapping at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
