# Panel guides (T5.4): the setup_panel_guides step for the many-facet cases
# at 100 panels, kernels off vs on. Runs sequentially with ggplot2 and alot
# reps interleaved; this is the kernel's 1.25x check.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/panel-guides.R")'
#
# ALOT_BENCH_CASES narrows the cases, ALOT_BENCH_SIZES sets the panel count.
source("inst/bench/cases.R")

cases <- select_cases(facet_cases[c("wrap_free_point", "grid_free_point", "wrap_fixed_point")])
k <- select_sizes(100)[[1]]
step_ms <- function(p, kernels) {
  gc(FALSE)
  st <- quiet(step_times(p, kernels = kernels))
  1000 * st$seconds[st$step == "setup_panel_guides"]
}
res <- do.call(rbind, lapply(names(cases), function(case) {
  progress(case, " at ", k, " panels")
  set.seed(42)
  p <- cases[[case]](facet_data(k))
  check_equal(p)
  t <- replicate(5, c(step_ms(p, FALSE), step_ms(p, TRUE)))
  m <- apply(t, 1, stats::median)
  data.frame(
    case = case, panels = k, ggplot2_ms = m[1], alot_ms = m[2],
    speedup = paste0(formatC(m[1] / m[2], format = "f", digits = 2), "x")
  )
}))

bench_header("setup_panel_guides step")
md_table(res)
