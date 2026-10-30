# Row-scaling suite (T0.6): total build time for the eight large-data plots
# in PLAN.md at 1e4, 1e6 and 1e7 rows, ggplot2::ggplot_build() vs
# alot_build(). Prints the Markdown table recorded in RESULTS.md.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/row-scaling.R")'
#
# ALOT_BENCH_CASES and ALOT_BENCH_SIZES narrow the run (see cases.R).
source("inst/bench/cases.R")

cases <- select_cases(row_cases)
sizes <- select_sizes(c(1e4, 1e6, 1e7))

# One job per (size, case), largest first so the 1e7 jobs start early.
jobs <- expand.grid(case = names(cases), rows = sort(sizes, decreasing = TRUE), stringsAsFactors = FALSE)
res <- run_jobs(split(jobs, seq_len(nrow(jobs))), function(job) {
  progress(job$case, " at ", fmt_rows(job$rows), " rows")
  set.seed(42)
  p <- cases[[job$case]](row_data(job$rows))
  if (job$rows == min(sizes)) check_equal(p)
  reps <- reps_for(job$rows)
  ggplot2_ms <- time_ms(function() quiet(ggplot_build(p)), reps)
  alot_ms <- time_ms(function() quiet(alot_build(p)), reps)
  data.frame(
    case = job$case, rows = job$rows, ggplot2_ms = ggplot2_ms, alot_ms = alot_ms,
    speedup = paste0(formatC(ggplot2_ms / alot_ms, format = "f", digits = 2), "x")
  )
})
res <- do.call(rbind, res)
res <- res[order(match(res$case, names(cases)), res$rows), ]
res$rows <- vapply(res$rows, fmt_rows, "")

bench_header("Row scaling")
md_table(res)
