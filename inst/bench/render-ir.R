# Render IR extraction (R3.1): median time of render_ir() on a built plot,
# for PHASE2.md's budgets (README plot under 10 ms, 400 panels under 50 ms).
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/render-ir.R")'
#
# pkgload::load_all() doesn't byte-compile R functions, an installed package
# does; the functions are byte-compiled here so the timings match an
# installed alot.
source("inst/bench/cases.R")
for (f in ls(alot_ns)) {
  g <- get(f, alot_ns)
  if (is.function(g) && !inherits(g, "compiled")) {
    unlockBinding(f, alot_ns)
    assign(f, compiler::cmpfun(g), alot_ns)
  }
}

set.seed(1)
n <- 1e6
readme <- ggplot(
  data.frame(
    income = exp(stats::rnorm(n, 10, 1)), spend = stats::runif(n, 0, 100),
    age = sample(18:90, n, TRUE),
    region = factor(sample(c("North", "South", "East", "West", "Central", "Islands"), n, TRUE)),
    segment = factor(sample(c("A", "B", "C", "D"), n, TRUE))
  ),
  aes(income, spend, colour = age, shape = segment)
) +
  geom_point(alpha = 0.3) + scale_x_log10() + scale_colour_viridis_c() + facet_wrap(~region)
d <- data.frame(x = stats::rnorm(2e4), y = stats::rnorm(2e4), p = factor(rep(1:400, each = 50)))
facets_400 <- ggplot(d, aes(x, y)) + geom_point(size = 0.5) + facet_wrap(~p)

median_ms <- function(f, reps = 60) {
  f()
  stats::median(vapply(seq_len(reps), function(i) {
    t <- proc.time()[["elapsed"]]
    f()
    (proc.time()[["elapsed"]] - t) * 1000
  }, numeric(1)))
}

cat("| Case | render_ir() (ms) | theme only (ms) |\n|---|---:|---:|\n")
for (case in c("readme", "facets_400")) {
  b <- alot_build(get(case))
  cat(sprintf(
    "| %s | %.1f | %.1f |\n", case,
    median_ms(function() alot_ns$render_ir(b)),
    median_ms(function() alot_ns$resolve_theme(b@plot@theme))
  ))
}
