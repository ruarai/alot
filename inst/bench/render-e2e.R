# End-to-end render benchmark: from a ggplot to a PNG file, ggsave() on
# ragg::agg_png() vs alot_png() in the tier it picks (full where supported,
# else hybrid or ggplot2), for the cases in render-cases.R. Prints a Markdown
# table; the CSV of medians goes to ALOT_BENCH_CSV when set.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE, helpers = FALSE); source("inst/bench/render-e2e.R")'
#
# helpers = FALSE matters: the test helpers set options(alot.full_tier =
# FALSE), which would time the hybrid tier instead of the full one.
#
# Runs are sequential with the two paths interleaved; medians are reported,
# after an untimed warm-up rep.
#   ALOT_BENCH_CASES  comma-separated case names (default: all)
#   ALOT_BENCH_REPS   reps per case (default: 3; 7 for readme_10)
#   ALOT_BENCH_OUT    directory for the PNGs (default: tempdir())
#   ALOT_BENCH_CSV    file for the medians as CSV (default: none)
source("inst/bench/render-cases.R")
if (isFALSE(getOption("alot.full_tier"))) stop("options(alot.full_tier = FALSE) is set; load with pkgload::load_all(helpers = FALSE).")

cases <- select_cases(render_cases)
out_dir <- Sys.getenv("ALOT_BENCH_OUT", tempdir())

elapsed <- function(expr) {
  t <- proc.time()[["elapsed"]]
  force(expr)
  proc.time()[["elapsed"]] - t
}

run_ggplot2 <- function(p, s, file) {
  elapsed(quiet(ggsave(file, p, device = ragg::agg_png, width = s$width, height = s$height, units = s$units, dpi = s$res)))
}

run_alot <- function(p, s, file) {
  elapsed(quiet(alot_png(p, file, width = s$width, height = s$height, units = s$units, dpi = s$res)))
}

paths <- list(ggplot2 = run_ggplot2, alot = run_alot)

cat("## Render end to end\n\n")
cat(sprintf(
  "%s; %s; ggplot2 %s; ragg %s; alot %s; %d threads available. Medians of interleaved runs, ms.\n\n",
  R.version.string, utils::sessionInfo()$running, utils::packageVersion("ggplot2"),
  utils::packageVersion("ragg"), utils::packageVersion("alot"), parallel::detectCores()
))

rows <- list()
for (name in names(cases)) {
  case <- cases[[name]]
  reps <- as.integer(Sys.getenv("ALOT_BENCH_REPS", case$reps %||% 3L))
  set.seed(42)
  p <- case$plot()
  tier <- quiet(alot_render_coverage(p))$tier
  times <- list()
  for (i in 0:reps) {
    for (path in names(paths)) {
      progress(name, " rep ", i, ": ", path)
      file <- file.path(out_dir, paste0("e2e-", name, "-", path, ".png"))
      gc(FALSE)
      t <- paths[[path]](p, case$size, file)
      if (i > 0) times[[path]] <- c(times[[path]], t)
    }
  }
  med <- vapply(times, function(t) 1000 * stats::median(t), numeric(1))
  rows[[name]] <- data.frame(
    case = name, tier = tier, ggplot2 = med[["ggplot2"]], alot = med[["alot"]],
    speedup = paste0(formatC(med[["ggplot2"]] / med[["alot"]], format = "f", digits = 1), "x")
  )
}

res <- do.call(rbind, rows)
md_table(res)
csv <- Sys.getenv("ALOT_BENCH_CSV")
if (nzchar(csv)) utils::write.csv(res, csv, row.names = FALSE)
