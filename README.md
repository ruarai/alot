# alot

A Rust backend for building and rendering ggplot2 plots.

```r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
b <- alot::alot_build(p)  # identical to ggplot2::ggplot_build(p)
alot::alot_coverage(p)    # which components ran in Rust vs ggplot2
alot::alot_print(p)       # like print(p), but builds with alot
```

`alot_build()` mirrors `ggplot2:::build_ggplot()` step by step. Pipeline
components (stats, positions, ...) with a registered Rust kernel run in
Rust; everything else falls back to ggplot2's own methods, so results are
always identical to ggplot2. Targets ggplot2 4.0.x.

## Example benchmark

A faceted scatter plot of 1e6 rows with a log-scaled x axis, a continuous
colour scale and a discrete shape scale:

```r
library(ggplot2)
set.seed(42)
n <- 1e6
d <- data.frame(
  income = exp(rnorm(n, 10, 1)),
  spend = runif(n, 0, 100),
  age = sample(18:90, n, TRUE),
  region = factor(sample(c("North", "South", "East", "West", "Central", "Islands"), n, TRUE)),
  segment = factor(sample(c("A", "B", "C", "D"), n, TRUE))
)
p <- ggplot(d, aes(income, spend, colour = age, shape = segment)) +
  geom_point(alpha = 0.3) +
  scale_x_log10() +
  scale_colour_viridis_c() +
  facet_wrap(~region)

system.time(ggplot_build(p))     # 0.49 s
system.time(alot::alot_build(p)) # 0.25 s, same result
```

That is about 2× faster. The position transform, training and mapping
steps and the colour and shape scales all run in Rust; the stat, position
and facet steps fall back to ggplot2. Times are medians of 5 interleaved
runs on a release build (AMD EPYC 9474F, R 4.6.1, ggplot2 4.0.3). See
[inst/bench/RESULTS.md](inst/bench/RESULTS.md) for per-step numbers.

## Tests

Tests compare every build against `ggplot2::ggplot_build()`:

```sh
NOT_CRAN=true Rscript -e 'pkgload::load_all(); testthat::test_dir("tests/testthat", load_package = "none")'
```
