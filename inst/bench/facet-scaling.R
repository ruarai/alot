# Facet-scaling suite (T0.6): total build time for the four many-facet plots
# in PLAN.md at 25, 100, 400 and 1,600 panels with 200 rows per panel,
# ggplot2::ggplot_build() vs alot_build(). Prints the Markdown table
# recorded in RESULTS.md; ms_per_panel shows whether cost per panel stays
# flat.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/facet-scaling.R")'
#
# ALOT_BENCH_CASES and ALOT_BENCH_SIZES (panel counts) narrow the run.
source("inst/bench/cases.R")

cases <- select_cases(facet_cases)
sizes <- select_sizes(c(25, 100, 400, 1600))

# One job per (panels, case), largest first.
jobs <- expand.grid(case = names(cases), panels = sort(sizes, decreasing = TRUE), stringsAsFactors = FALSE)
res <- run_jobs(split(jobs, seq_len(nrow(jobs))), function(job) {
  k <- job$panels
  progress(job$case, " at ", k, " panels")
  set.seed(42)
  p <- cases[[job$case]](facet_data(k))
  if (k == min(sizes)) check_equal(p)
  reps <- if (k >= 1600) 1L else 3L
  ggplot2_ms <- time_ms(function() quiet(ggplot_build(p)), reps)
  alot_ms <- time_ms(function() quiet(alot_build(p)), reps)
  data.frame(
    case = job$case, panels = k, ggplot2_ms = ggplot2_ms, alot_ms = alot_ms,
    speedup = paste0(formatC(ggplot2_ms / alot_ms, format = "f", digits = 2), "x"),
    alot_ms_per_panel = alot_ms / k
  )
})
res <- do.call(rbind, res)
res <- res[order(match(res$case, names(cases)), res$panels), ]
res$panels <- as.character(res$panels)

bench_header("Facet scaling (200 rows per panel)")
md_table(res)
