# Discrete position training (T1.1): the scale_train dispatch alone, kernels
# off vs on, for one discrete column of 1e6 values trained into 1 or 25
# panel scales. Runs sequentially with ggplot2 and alot reps interleaved;
# this is the kernel's 2x check. The step-profile suite's train_position
# step also includes continuous training and match(PANEL), which this
# leaves out.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/scale-train.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
inputs <- list(
  factor_10 = factor(sample(LETTERS[1:10], n, TRUE)),
  character_10 = sample(LETTERS[1:10], n, TRUE),
  character_1e4 = sample(sprintf("s%05d", 1:1e4), n, TRUE),
  logical = sample(c(TRUE, FALSE, NA), n, TRUE),
  mapped_discrete = ggplot2:::mapped_discrete(sample(1:10, n, TRUE) + 0.4 * stats::runif(n))
)

# Seconds for one scales_train() call on fresh scales.
time_train <- function(x, panels, kernels) {
  scales <- lapply(seq_len(panels), function(i) scale_x_discrete()$clone())
  scale_id <- sort(rep(seq_len(panels), length.out = n))
  df <- data.frame(row = seq_len(n))
  df$x <- x
  old <- options(alot.kernels = kernels)
  on.exit(options(old))
  gc(FALSE)
  system.time(alot_ns$scales_train(df, "x", scale_id, scales))[["elapsed"]]
}

reps <- 7L
rows <- list()
for (name in names(inputs)) {
  for (panels in c(1, 25)) {
    progress(sprintf("%s, %d panels", name, panels))
    off <- on <- double(reps)
    for (r in seq_len(reps)) {
      off[r] <- time_train(inputs[[name]], panels, FALSE)
      on[r] <- time_train(inputs[[name]], panels, TRUE)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      input = name, panels = as.character(panels),
      ggplot2_ms = 1000 * stats::median(off), alot_ms = 1000 * stats::median(on),
      speedup = sprintf("%.1fx", stats::median(off) / stats::median(on))
    )
  }
}

cat("## Discrete position training at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
