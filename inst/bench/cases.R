# Shared case definitions and helpers for the benchmark suites (T0.6):
# row-scaling.R, facet-scaling.R and step-profile.R source this file. The
# cases are the ones in PLAN.md "Where the time goes".
#
# Environment variables narrow a run:
#   ALOT_BENCH_CASES  comma-separated case names (default: all)
#   ALOT_BENCH_SIZES  comma-separated row counts or panel counts
#   ALOT_BENCH_CORES  parallel workers (default 8); a 1e7-row job peaks at
#                     about 2.3 GB, so mind memory before raising it
library(ggplot2)
if (!"alot" %in% loadedNamespaces()) library(alot)
alot_ns <- asNamespace("alot")

# pkgload::load_all() compiles with DEBUG set, which makes an unoptimised
# Rust build roughly 10x slower. Load a release build as the suite headers
# show, or install the package.
if (alot_ns$rs_build_profile() != "release") {
  stop("alot's Rust library is a debug build; benchmarks need a release build. ",
       "Run pkgbuild::compile_dll(force = TRUE, debug = FALSE) first.")
}

# Row-scaling cases: n rows, one panel unless faceted.
row_data <- function(n) {
  data.frame(
    x = stats::rnorm(n),
    y = stats::rnorm(n),
    z = stats::runif(n),
    g = factor(sample(letters[1:5], n, TRUE)),
    a = factor(sample(LETTERS[1:10], n, TRUE)),
    f = factor(sample(paste0("f", 1:9), n, TRUE))
  )
}

row_cases <- list(
  point_discrete = function(d) ggplot(d, aes(x, y, colour = g)) + geom_point(),
  point_continuous = function(d) ggplot(d, aes(x, y, colour = z)) + geom_point(),
  facet_wrap_point = function(d) ggplot(d, aes(x, y)) + geom_point() + facet_wrap(~f),
  histogram_fill = function(d) ggplot(d, aes(x, fill = g)) + geom_histogram(bins = 30),
  bar_dodge = function(d) ggplot(d, aes(a, fill = g)) + geom_bar(position = "dodge"),
  density_groups = function(d) ggplot(d, aes(x, colour = g)) + geom_density(),
  boxplot = function(d) ggplot(d, aes(a, y)) + geom_boxplot(),
  smooth_lm = function(d) ggplot(d, aes(x, y)) + geom_smooth(method = "lm", formula = y ~ x)
)

# Facet-scaling cases: k panels with 200 rows each. facet_grid uses a
# sqrt(k) x sqrt(k) grid, so k must be a square.
facet_data <- function(k, rows_per_panel = 200) {
  n <- k * rows_per_panel
  side <- round(sqrt(k))
  stopifnot(side^2 == k)
  panel <- rep(seq_len(k), each = rows_per_panel)
  data.frame(
    x = stats::rnorm(n) + panel,
    y = stats::rnorm(n) * panel,
    g = factor(sample(letters[1:5], n, TRUE)),
    p = factor(panel),
    r = factor((panel - 1) %/% side + 1),
    c = factor((panel - 1) %% side + 1)
  )
}

facet_cases <- list(
  wrap_fixed_point = function(d) ggplot(d, aes(x, y)) + geom_point() + facet_wrap(~p),
  wrap_free_point = function(d) ggplot(d, aes(x, y)) + geom_point() + facet_wrap(~p, scales = "free"),
  grid_free_point = function(d) ggplot(d, aes(x, y)) + geom_point() + facet_grid(r ~ c, scales = "free"),
  wrap_histogram = function(d) ggplot(d, aes(x, fill = g)) + geom_histogram(bins = 30) + facet_wrap(~p)
)

env_list <- function(var, default) {
  val <- Sys.getenv(var)
  if (!nzchar(val)) return(default)
  strsplit(val, ",", fixed = TRUE)[[1]]
}

select_cases <- function(cases) {
  keep <- env_list("ALOT_BENCH_CASES", names(cases))
  unknown <- setdiff(keep, names(cases))
  if (length(unknown)) stop("Unknown benchmark case(s): ", paste(unknown, collapse = ", "))
  cases[keep]
}

select_sizes <- function(default) as.numeric(env_list("ALOT_BENCH_SIZES", default))

# Fewer repetitions for big inputs; the median is reported.
reps_for <- function(rows) if (rows >= 5e6) 1L else if (rows >= 5e5) 3L else 5L

# Median elapsed milliseconds of `reps` evaluations of `f()`, after a gc().
time_ms <- function(f, reps) {
  t <- vapply(seq_len(reps), function(i) {
    gc(FALSE)
    system.time(f())[["elapsed"]]
  }, double(1))
  1000 * stats::median(t)
}

bench_cores <- function() as.integer(Sys.getenv("ALOT_BENCH_CORES", "8"))

# Run `fn` on each element of `jobs` in forked workers, one job per worker
# at a time, and return the results in job order. Each job times ggplot2 and
# alot in the same worker, so contention between workers affects both.
run_jobs <- function(jobs, fn) {
  out <- parallel::mclapply(jobs, fn, mc.cores = bench_cores(), mc.preschedule = FALSE)
  failed <- vapply(out, inherits, logical(1), "try-error")
  if (any(failed)) stop("Benchmark job failed: ", out[failed][[1]])
  out
}

# Progress on stderr, so a long run shows where it is without touching the
# table on stdout.
progress <- function(...) message(format(Sys.time(), "%H:%M:%S "), ...)

quiet <- function(expr) suppressWarnings(suppressMessages(expr))

# Check that alot and ggplot2 agree on `p`, so a benchmark never times a
# build that has drifted.
check_equal <- function(p) {
  set.seed(1)
  a <- quiet(alot_build(p))
  set.seed(1)
  b <- quiet(ggplot_build(p))
  ok <- isTRUE(all.equal(a@data, b@data, tolerance = 1e-8))
  if (!ok) stop("alot and ggplot2 builds differ")
  invisible(TRUE)
}

fmt_rows <- function(n) {
  p <- log10(n)
  if (p == round(p)) sprintf("1e%d", as.integer(p)) else format(n, big.mark = ",")
}
fmt_ms <- function(x) formatC(x, format = "f", digits = if (all(x >= 100)) 0 else 1, big.mark = ",")

# Print a data frame as a Markdown table.
md_table <- function(df) {
  cells <- lapply(df, function(col) if (is.numeric(col)) fmt_ms(col) else as.character(col))
  num <- vapply(df, is.numeric, logical(1))
  line <- function(x) paste0("| ", paste(x, collapse = " | "), " |")
  cat(line(names(df)), "\n", sep = "")
  cat(line(ifelse(num, "---:", "---")), "\n", sep = "")
  for (i in seq_len(nrow(df))) cat(line(vapply(cells, `[`, "", i)), "\n", sep = "")
  cat("\n")
}

bench_header <- function(title) {
  cat("## ", title, "\n\n", sep = "")
  cat(sprintf("%s; %s; ggplot2 %s; alot %s; %d parallel workers.\n\n",
              R.version.string, utils::sessionInfo()$running,
              utils::packageVersion("ggplot2"), utils::packageVersion("alot"), bench_cores()))
}
