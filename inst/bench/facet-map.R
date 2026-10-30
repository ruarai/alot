# Facet layout and panel assignment (T5.1): the layout_setup step
# (Layout$setup, whose compute_layout and map_data the kernels replace)
# for one layer of 1e6 rows, kernels off
# vs on. Runs sequentially with ggplot2 and alot reps interleaved; this is
# the kernels' 1.25x check. Facet columns hold 9 values (3 x 3 for the grid)
# plus 1% NA, in random order.
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE); source("inst/bench/facet-map.R")'
#
# ALOT_BENCH_SIZES sets the row count (default 1e6).
source("inst/bench/cases.R")

n <- select_sizes(1e6)[[1]]
set.seed(42)
with_na <- function(x) {
  x[sample(n, n / 100)] <- NA
  x
}
df <- data.frame(
  x = stats::rnorm(n), y = stats::rnorm(n),
  fct = with_na(factor(sample(paste0("f", 1:9), n, TRUE))),
  chr = with_na(sample(paste0("f", 1:9), n, TRUE)),
  int = with_na(sample(1:9, n, TRUE)),
  r = with_na(factor(sample(1:3, n, TRUE))),
  c = with_na(factor(sample(1:3, n, TRUE)))
)
point <- ggplot(df, aes(x, y)) + geom_point()
inputs <- list(
  wrap_factor = point + facet_wrap(~fct),
  wrap_character = point + facet_wrap(~chr),
  wrap_integer = point + facet_wrap(~int),
  grid_factor = point + facet_grid(r ~ c)
)

# Seconds for `f()`, after a full gc so neither path pays for the other's
# garbage.
time_step <- function(f, kernels) {
  old <- options(alot.kernels = kernels)
  on.exit(options(old))
  gc(FALSE)
  start <- Sys.time()
  f()
  as.double(Sys.time() - start, units = "secs")
}

reps <- 15L
rows <- list()
for (name in names(inputs)) {
  progress(name)
  p <- inputs[[name]]
  data <- lapply(p@layers, function(l) l$setup_layer(l$layer_data(p@data), p))
  setup <- function() {
    layout <- ggplot2:::create_layout(p@facet, p@coordinates, p@layout)
    alot_ns$layout_setup(layout, data, p@data, p@plot_env)
  }
  set_up <- function(kernels) {
    options(alot.kernels = kernels)
    setup()
  }
  stopifnot(identical(set_up(FALSE), set_up(TRUE)))

  off <- on <- double(reps)
  for (r in seq_len(reps)) {
    off[r] <- time_step(setup, FALSE)
    on[r] <- time_step(setup, TRUE)
  }
  rows[[length(rows) + 1L]] <- data.frame(
    input = name,
    ggplot2_ms = round(1000 * stats::median(off), 1), alot_ms = round(1000 * stats::median(on), 1),
    speedup = sprintf("%.1fx", stats::median(off) / stats::median(on))
  )
}

cat("## Facet panel assignment at ", fmt_rows(n), " rows (sequential, interleaved)\n\n", sep = "")
cat(sprintf("%s; %s; ggplot2 %s; alot %s.\n\n", R.version.string, utils::sessionInfo()$running,
            utils::packageVersion("ggplot2"), utils::packageVersion("alot")))
md_table(do.call(rbind, rows))
