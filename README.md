# alot

A Rust backend for building and rendering ggplot2 plots.

```r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
b <- alot::alot_build(p)  # identical to ggplot2::ggplot_build(p)
alot::alot_coverage(p)    # which components ran in Rust vs ggplot2
```

`alot_build()` mirrors `ggplot2:::build_ggplot()` step by step. Pipeline
components (stats, positions, ...) with a registered Rust kernel run in
Rust; everything else falls back to ggplot2's own methods, so results are
always identical to ggplot2. Targets ggplot2 4.0.x.

Tests compare every build against `ggplot2::ggplot_build()`:

```sh
NOT_CRAN=true Rscript -e 'pkgload::load_all(); testthat::test_dir("tests/testthat", load_package = "none")'
```
