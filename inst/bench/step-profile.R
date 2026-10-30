# Per-step timing (T0.6): for each row-scaling case at 1e6 rows, the time
# alot_build() spends in each step of ggplot2:::build_ggplot, with kernels
# off (options(alot.kernels = FALSE), i.e. ggplot2's own methods) and on.
# This is the measurement behind each kernel's 2x rule: compare the step the
# kernel replaces. Steps under 2% of the ggplot2-path total are folded into
# "other".
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/step-profile.R")'
#
# ALOT_BENCH_CASES narrows the cases; ALOT_BENCH_SIZES sets the row count.
# Set ALOT_BENCH_FACETS=true to profile the facet cases instead, with
# ALOT_BENCH_SIZES as the panel count (default 400).
source("inst/bench/cases.R")

facets <- identical(Sys.getenv("ALOT_BENCH_FACETS"), "true")
cases <- select_cases(if (facets) facet_cases else row_cases)
size <- select_sizes(if (facets) 400 else 1e6)[[1]]

# Median seconds per step over `reps` builds.
median_steps <- function(p, kernels, reps) {
  runs <- lapply(seq_len(reps), function(i) {
    gc(FALSE)
    quiet(alot_ns$step_times(p, kernels = kernels))
  })
  steps <- runs[[1]]$step
  data.frame(
    step = steps,
    seconds = vapply(steps, function(s) {
      stats::median(vapply(runs, function(r) sum(r$seconds[r$step == s]), double(1)))
    }, double(1))
  )
}

reps <- if (facets) 3L else reps_for(size)

# One job per case; each returns its Markdown table as text.
tables <- run_jobs(names(cases), function(name) {
  progress(name)
  set.seed(42)
  p <- cases[[name]](if (facets) facet_data(size) else row_data(size))
  check_equal(p)
  off <- median_steps(p, FALSE, reps)
  on <- median_steps(p, TRUE, reps)
  tab <- merge(off, on, by = "step", all = TRUE, sort = FALSE, suffixes = c("_off", "_on"))
  tab[is.na(tab)] <- 0
  tab <- tab[match(off$step, tab$step), ]
  total_off <- sum(tab$seconds_off)
  major <- tab$seconds_off >= 0.02 * total_off
  rows <- rbind(
    tab[major, ],
    data.frame(step = "other", seconds_off = sum(tab$seconds_off[!major]), seconds_on = sum(tab$seconds_on[!major])),
    data.frame(step = "**total**", seconds_off = total_off, seconds_on = sum(tab$seconds_on))
  )
  utils::capture.output({
    cat("### ", name, "\n\n", sep = "")
    md_table(data.frame(
      step = rows$step,
      ggplot2_ms = 1000 * rows$seconds_off,
      share = sprintf("%.0f%%", 100 * rows$seconds_off / total_off),
      alot_ms = 1000 * rows$seconds_on,
      speedup = paste0(formatC(rows$seconds_off / pmax(rows$seconds_on, 1e-6), format = "f", digits = 2), "x")
    ))
  })
})

bench_header(sprintf("Per-step time at %s %s", fmt_rows(size), if (facets) "panels" else "rows"))
cat(unlist(tables), sep = "\n")
