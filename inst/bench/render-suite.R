# Render suite (R0.3): time per stage from a ggplot to a PNG file, for the
# cases in PHASE2.md "Performance targets" and "Verification". Prints the
# Markdown tables recorded in RESULTS.md.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/render-suite.R")'
#
# Paths, each run on its own build of the plot:
#   ggplot2  ggplot_build(); then on ragg::agg_png(): ggplot_gtable(), grid
#            drawing, and dev.off(), which writes the PNG (encode).
#   hybrid   alot_build(); then on ragg::agg_capture(): the hybrid gtable,
#            grid drawing, and readback plus Rust PNG encoding (what
#            alot_png() does in the hybrid tier).
# The device is opened before the gtable is built, as print.ggplot() does,
# since ggplot_gtable() measures text on the current device. "render" is
# gtable + draw + encode, the part PHASE2.md's targets cover.
#
# Runs are sequential (the hybrid's raster is multi-threaded) and the paths
# are interleaved within each rep; medians are reported. Each case starts
# with an untimed warm-up rep (first calls, point sprite builds).
#   ALOT_BENCH_CASES  comma-separated case names (default: all)
#   ALOT_BENCH_REPS   reps per case (default: 3; 7 for readme_10)
#   ALOT_BENCH_OUT    directory for the PNGs (default: tempdir())
source("inst/bench/render-cases.R")

secs <- function(expr) {
  t <- proc.time()[["elapsed"]]
  force(expr)
  proc.time()[["elapsed"]] - t
}

# Stage times (seconds) for one path on plot `p`.
run_ggplot2 <- function(p, size, file) {
  t_build <- secs(b <- quiet(ggplot_build(p)))
  do.call(ragg::agg_png, c(list(file), size))
  t_gtable <- secs(g <- quiet(ggplot_gtable(b)))
  t_draw <- secs({
    grid::grid.newpage()
    grid::grid.draw(g)
  })
  t_encode <- secs(grDevices::dev.off())
  c(build = t_build, gtable = t_gtable, draw = t_draw, encode = t_encode)
}

run_hybrid <- function(p, size, file) {
  t_build <- secs(b <- quiet(alot_build(p)))
  cap <- do.call(ragg::agg_capture, size)
  t_gtable <- secs(g <- quiet(alot_ns$hybrid_gtable(b)))
  t_draw <- secs({
    grid::grid.newpage()
    grid::grid.draw(g)
  })
  t_encode <- secs(alot_ns$write_png(cap(native = TRUE), file, dpi = size$res))
  grDevices::dev.off()
  c(build = t_build, gtable = t_gtable, draw = t_draw, encode = t_encode)
}

paths <- list(ggplot2 = run_ggplot2, hybrid = run_hybrid)
cases <- select_cases(render_cases)
out_dir <- Sys.getenv("ALOT_BENCH_OUT", tempdir())

cat("## Render suite\n\n")
cat(sprintf(
  "%s; %s; ggplot2 %s; ragg %s; alot %s; %d threads available. Medians of interleaved runs, ms.\n\n",
  R.version.string, utils::sessionInfo()$running, utils::packageVersion("ggplot2"),
  utils::packageVersion("ragg"), utils::packageVersion("alot"), parallel::detectCores()
))

summary <- list()
for (name in names(cases)) {
  case <- cases[[name]]
  reps <- as.integer(Sys.getenv("ALOT_BENCH_REPS", case$reps %||% 3L))
  set.seed(42)
  p <- case$plot()
  times <- list()
  for (i in 0:reps) {
    for (path in names(paths)) {
      progress(name, " rep ", i, ": ", path)
      file <- file.path(out_dir, paste0("render-", name, "-", path, ".png"))
      gc(FALSE)
      t <- paths[[path]](p, case$size, file)
      if (i > 0) times[[path]] <- rbind(times[[path]], t)
    }
  }
  med <- lapply(times, function(t) {
    t <- cbind(t, render = t[, "gtable"] + t[, "draw"] + t[, "encode"])
    t <- cbind(t, total = t[, "build"] + t[, "render"])
    1000 * apply(t, 2, stats::median)
  })
  s <- case$size
  cat(sprintf("### %s (%s x %s %s, %s dpi; %d reps)\n\n", name, s$width, s$height, s$units, s$res, reps))
  md_table(data.frame(
    step = names(med$ggplot2), ggplot2 = unname(med$ggplot2), hybrid = unname(med$hybrid),
    speedup = paste0(formatC(med$ggplot2 / med$hybrid, format = "f", digits = 1), "x")
  ))
  summary[[name]] <- data.frame(
    case = name, ggplot2 = med$ggplot2[["render"]], hybrid = med$hybrid[["render"]],
    speedup = paste0(formatC(med$ggplot2[["render"]] / med$hybrid[["render"]], format = "f", digits = 1), "x")
  )
}

cat("### Render (gtable + draw + encode)\n\n")
md_table(do.call(rbind, summary))
