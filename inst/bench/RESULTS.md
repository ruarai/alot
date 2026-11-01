# Benchmark results

Baselines for the suites in `inst/bench/` (T0.6). Each suite prints its
table as Markdown, so rerunning the command below for a suite reproduces
that section. Run from the repo root, on a release build:

```sh
export PATH="$PATH:$HOME/.cargo/bin"
NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE)'
NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE); source("inst/bench/row-scaling.R")'
NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE); source("inst/bench/facet-scaling.R")'
NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE); source("inst/bench/step-profile.R")'
ALOT_BENCH_FACETS=true NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE); source("inst/bench/step-profile.R")'
```

`ALOT_BENCH_CASES`, `ALOT_BENCH_SIZES` and `ALOT_BENCH_CORES` narrow a run
(see `inst/bench/cases.R`). Progress goes to stderr.

## How to read these numbers

- **Release builds only.** `pkgload::load_all()` compiles with `DEBUG` set,
  which gives an unoptimised Rust build about 10× slower (the continuous
  train kernel: 41 ms vs 3.8 ms on 1e6 values). `cases.R` stops if the loaded
  library is a debug build (`rs_build_profile()`).
- **Parallel runs are a quick overview.** The suites run jobs in 8 forked
  workers by default. Workers compete for memory bandwidth and cache, so
  absolute times are inflated and noisy. Each job also times all ggplot2
  reps before all alot reps, so contention can differ between the two and
  favour alot. In the tables below, steps with no kernel swing from 0.3× to
  3× (e.g. `map_position_2`); read speedups under about 1.5× as noise.
  The 1e7-row cells use a single rep and are the noisiest: `bar_dodge`
  shows 1.59× there although no kernel touches its main steps.
- **1.25× checks for new kernels run sequentially with interleaved reps.**
  A kernel's 1.25× decision uses `ALOT_BENCH_CORES=1` and alternates ggplot2
  and alot reps (ggplot2, alot, ggplot2, …), taking the median of each. The
  suites do not interleave yet; add that before the first kernel's check
  relies on these scripts.
- **Step profile.** "ggplot2" is alot's build mirror with
  `options(alot.kernels = FALSE)`, so every component runs ggplot2's own
  method; "alot" has kernels on. Steps are those of `ggplot2:::build_ggplot`
  (`R/timing.R`); the ones under 2% of the total are folded into "other".

## Baseline (2026-10-30)

AMD EPYC 9474F, 16 vCPUs (KVM), 31 GB RAM; R 4.6.1; Ubuntu 22.04.5 LTS;
ggplot2 4.0.3; alot 0.0.0.9000 at T0.6 (one kernel: continuous position
training); 8 parallel workers.

Pending a sequential, interleaved check: the continuous train kernel's step
(`train_position_1`) shows 1.2–2.4× here, so whether it meets the 2× rule
is not settled by these numbers.

### Row scaling

| case | rows | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| point_discrete | 1e4 | 30.0 | 31.0 | 0.97x |
| point_discrete | 1e6 | 707.0 | 494.0 | 1.43x |
| point_discrete | 1e7 | 9,234.0 | 6,940.0 | 1.33x |
| point_continuous | 1e4 | 27.0 | 26.0 | 1.04x |
| point_continuous | 1e6 | 516.0 | 407.0 | 1.27x |
| point_continuous | 1e7 | 11,572.0 | 8,806.0 | 1.31x |
| facet_wrap_point | 1e4 | 22.0 | 22.0 | 1.00x |
| facet_wrap_point | 1e6 | 469.0 | 338.0 | 1.39x |
| facet_wrap_point | 1e7 | 8,546.0 | 5,666.0 | 1.51x |
| histogram_fill | 1e4 | 43.0 | 44.0 | 0.98x |
| histogram_fill | 1e6 | 238.0 | 254.0 | 0.94x |
| histogram_fill | 1e7 | 5,433.0 | 3,161.0 | 1.72x |
| bar_dodge | 1e4 | 59.0 | 60.0 | 0.98x |
| bar_dodge | 1e6 | 488.0 | 399.0 | 1.22x |
| bar_dodge | 1e7 | 9,223.0 | 5,802.0 | 1.59x |
| density_groups | 1e4 | 34.0 | 34.0 | 1.00x |
| density_groups | 1e6 | 247.0 | 244.0 | 1.01x |
| density_groups | 1e7 | 6,140.0 | 3,232.0 | 1.90x |
| boxplot | 1e4 | 32.0 | 32.0 | 1.00x |
| boxplot | 1e6 | 516.0 | 389.0 | 1.33x |
| boxplot | 1e7 | 8,844.0 | 5,309.0 | 1.67x |
| smooth_lm | 1e4 | 24.0 | 24.0 | 1.00x |
| smooth_lm | 1e6 | 440.0 | 430.0 | 1.02x |
| smooth_lm | 1e7 | 11,646.0 | 8,471.0 | 1.37x |


### Facet scaling (200 rows per panel)

| case | panels | ggplot2_ms | alot_ms | speedup | alot_ms_per_panel |
| --- | --- | ---: | ---: | --- | ---: |
| wrap_fixed_point | 25 | 23.0 | 23.0 | 1.00x | 0.9 |
| wrap_fixed_point | 100 | 30.0 | 24.0 | 1.25x | 0.2 |
| wrap_fixed_point | 400 | 71.0 | 59.0 | 1.20x | 0.1 |
| wrap_fixed_point | 1600 | 159.0 | 114.0 | 1.39x | 0.1 |
| wrap_free_point | 25 | 229.0 | 228.0 | 1.00x | 9.1 |
| wrap_free_point | 100 | 768.0 | 742.0 | 1.04x | 7.4 |
| wrap_free_point | 400 | 3,130.0 | 3,014.0 | 1.04x | 7.5 |
| wrap_free_point | 1600 | 13,619.0 | 12,719.0 | 1.07x | 7.9 |
| grid_free_point | 25 | 159.0 | 159.0 | 1.00x | 6.4 |
| grid_free_point | 100 | 694.0 | 698.0 | 0.99x | 7.0 |
| grid_free_point | 400 | 2,367.0 | 2,314.0 | 1.02x | 5.8 |
| grid_free_point | 1600 | 10,344.0 | 9,759.0 | 1.06x | 6.1 |
| wrap_histogram | 25 | 269.0 | 234.0 | 1.15x | 9.4 |
| wrap_histogram | 100 | 855.0 | 859.0 | 1.00x | 8.6 |
| wrap_histogram | 400 | 3,709.0 | 3,640.0 | 1.02x | 9.1 |
| wrap_histogram | 1600 | 21,810.0 | 20,985.0 | 1.04x | 13.1 |


### Per-step time at 1e6 rows

#### point_discrete

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_aesthetics | 32.1 | 6% | 33.4 | 0.96x |
| train_position_1 | 85.7 | 16% | 46.8 | 1.83x |
| map_position_1 | 83.8 | 16% | 99.1 | 0.85x |
| train_position_2 | 30.5 | 6% | 23.7 | 1.28x |
| map_position_2 | 199.0 | 37% | 66.6 | 2.99x |
| npscales_train | 24.8 | 5% | 23.8 | 1.04x |
| guides_build | 17.7 | 3% | 16.6 | 1.07x |
| npscales_map | 32.3 | 6% | 23.0 | 1.40x |
| compute_geom_2 | 12.2 | 2% | 6.9 | 1.77x |
| other | 17.9 | 3% | 17.4 | 1.03x |
| **total** | 536.0 | 100% | 357.3 | 1.50x |

#### point_continuous

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| train_position_1 | 52.2 | 12% | 21.9 | 2.38x |
| map_position_1 | 76.9 | 18% | 55.1 | 1.40x |
| train_position_2 | 28.1 | 7% | 21.0 | 1.34x |
| map_position_2 | 58.8 | 14% | 211.1 | 0.28x |
| npscales_map | 179.0 | 41% | 173.0 | 1.03x |
| other | 36.5 | 8% | 36.4 | 1.00x |
| **total** | 431.6 | 100% | 518.5 | 0.83x |

#### facet_wrap_point

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| layout_setup | 61.7 | 18% | 61.1 | 1.01x |
| compute_aesthetics | 10.8 | 3% | 11.0 | 0.98x |
| train_position_1 | 78.5 | 22% | 41.7 | 1.88x |
| map_position_1 | 73.7 | 21% | 71.5 | 1.03x |
| train_position_2 | 39.5 | 11% | 29.1 | 1.36x |
| map_position_2 | 64.8 | 18% | 73.3 | 0.88x |
| compute_geom_2 | 8.6 | 2% | 12.5 | 0.69x |
| other | 12.9 | 4% | 12.7 | 1.02x |
| **total** | 350.4 | 100% | 312.8 | 1.12x |

#### histogram_fill

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_aesthetics | 18.1 | 7% | 18.3 | 0.99x |
| train_position_1 | 39.3 | 15% | 18.5 | 2.12x |
| map_position_1 | 40.3 | 16% | 72.4 | 0.56x |
| compute_statistic | 129.1 | 50% | 128.3 | 1.01x |
| other | 31.2 | 12% | 30.9 | 1.01x |
| **total** | 258.0 | 100% | 268.5 | 0.96x |

#### bar_dodge

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_aesthetics | 87.4 | 20% | 92.2 | 0.95x |
| train_position_1 | 30.3 | 7% | 30.8 | 0.98x |
| map_position_1 | 51.1 | 12% | 52.7 | 0.97x |
| compute_statistic | 238.4 | 55% | 230.6 | 1.03x |
| other | 30.0 | 7% | 29.7 | 1.01x |
| **total** | 437.1 | 100% | 436.0 | 1.00x |

#### density_groups

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_aesthetics | 16.0 | 7% | 16.0 | 1.00x |
| train_position_1 | 26.0 | 12% | 18.4 | 1.41x |
| map_position_1 | 40.8 | 18% | 62.0 | 0.66x |
| compute_statistic | 117.3 | 52% | 118.2 | 0.99x |
| other | 25.1 | 11% | 22.7 | 1.11x |
| **total** | 225.1 | 100% | 237.3 | 0.95x |

#### boxplot

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_aesthetics | 16.2 | 4% | 16.3 | 0.99x |
| train_position_1 | 70.0 | 19% | 57.1 | 1.23x |
| map_position_1 | 74.1 | 20% | 83.4 | 0.89x |
| compute_statistic | 194.2 | 52% | 186.8 | 1.04x |
| other | 19.5 | 5% | 19.7 | 0.99x |
| **total** | 373.9 | 100% | 363.2 | 1.03x |

#### smooth_lm

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| train_position_1 | 73.9 | 22% | 41.2 | 1.79x |
| map_position_1 | 83.8 | 25% | 114.2 | 0.73x |
| compute_statistic | 162.8 | 48% | 165.6 | 0.98x |
| other | 20.3 | 6% | 20.3 | 1.00x |
| **total** | 340.8 | 100% | 341.3 | 1.00x |


### Per-step time at 400 panels

#### wrap_fixed_point

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| layout_setup | 4.4 | 9% | 4.5 | 0.99x |
| compute_aesthetics | 2.0 | 4% | 2.0 | 1.00x |
| train_position_1 | 3.2 | 7% | 2.9 | 1.10x |
| map_position_1 | 9.0 | 18% | 6.4 | 1.40x |
| train_position_2 | 6.3 | 13% | 3.3 | 1.90x |
| setup_panel_params | 3.9 | 8% | 3.8 | 1.03x |
| map_position_2 | 10.5 | 21% | 10.4 | 1.01x |
| setup_panel_guides | 2.8 | 6% | 3.0 | 0.95x |
| plot_theme | 1.5 | 3% | 1.5 | 0.97x |
| compute_geom_2 | 2.5 | 5% | 3.8 | 0.66x |
| other | 3.0 | 6% | 3.0 | 1.00x |
| **total** | 49.2 | 100% | 44.6 | 1.10x |

#### wrap_free_point

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| train_position_1 | 131.4 | 4% | 117.5 | 1.12x |
| map_position_1 | 88.9 | 3% | 92.7 | 0.96x |
| setup_panel_params | 1,567.4 | 53% | 1,812.9 | 0.86x |
| map_position_2 | 92.8 | 3% | 107.5 | 0.86x |
| setup_panel_guides | 998.4 | 34% | 1,217.8 | 0.82x |
| other | 85.2 | 3% | 72.9 | 1.17x |
| **total** | 2,964.2 | 100% | 3,421.3 | 0.87x |

#### grid_free_point

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| setup_panel_params | 1,172.7 | 52% | 1,192.7 | 0.98x |
| setup_panel_guides | 1,016.6 | 45% | 1,016.1 | 1.00x |
| other | 67.2 | 3% | 53.4 | 1.26x |
| **total** | 2,256.5 | 100% | 2,262.2 | 1.00x |

#### wrap_histogram

| step | ggplot2_ms | share | alot_ms | speedup |
| --- | ---: | --- | ---: | --- |
| compute_statistic | 1,978.8 | 53% | 1,921.7 | 1.03x |
| compute_position | 1,670.2 | 45% | 1,606.8 | 1.04x |
| other | 80.2 | 2% | 74.8 | 1.07x |
| **total** | 3,729.1 | 100% | 3,603.3 | 1.03x |


## Kernel speed checks (1.25× rule; 2× before T1.3)

### T1.1 Discrete position training (2026-10-30) — kept

`inst/bench/scale-train.R`: the `scale_train` dispatch for one discrete
column, sequential with interleaved reps (same machine as the baseline).

| input | panels | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| factor_10 | 1 | 33.0 | 4.0 | 8.2x |
| factor_10 | 25 | 57.0 | 7.0 | 8.1x |
| character_10 | 1 | 12.0 | 6.0 | 2.0x |
| character_10 | 25 | 42.0 | 8.0 | 5.2x |
| character_1e4 | 1 | 36.0 | 25.0 | 1.4x |
| character_1e4 | 25 | 538.0 | 479.0 | 1.1x |
| logical | 1 | 8.0 | 3.0 | 2.7x |
| logical | 25 | 29.0 | 4.0 | 7.2x |
| mapped_discrete | 1 | 32.0 | 3.0 | 10.7x |
| mapped_discrete | 25 | 47.0 | 6.0 | 7.8x |

The kernel is kept: factors, logicals, low-cardinality strings and
`mapped_discrete` (the second training pass after a stat) all clear 2×.
High-cardinality strings do not, and cannot. Rust's share is 6 ms (1
panel) to 18 ms (25 panels). The rest is the locale-aware `sort()` of the
1e4 unique values per scale, which ggplot2 also does and which must stay
in R.

Step profile (`step-profile.R`, `ALOT_BENCH_CORES=1`, not interleaved):
`train_position_1` is 67.7 → 20.3 ms (3.3×) for `boxplot`, and 38.9 → 21.0 ms
(1.85×) for `bar_dodge`. In `bar_dodge` about 11 ms of that step is
`match(PANEL, …)` in the `Facet$train_scales` mirror, outside the kernel.

### T1.2 Position mapping (2026-10-30) — kept

`inst/bench/scale-map.R`: the `scale_map` dispatch for one column of 1e6
values through trained panel scales, sequential with interleaved reps (same
machine as the baseline). The continuous inputs have 1% NA.

| input | panels | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| double_censor | 1 | 56.0 | 5.0 | 11.2x |
| double_censor | 25 | 74.0 | 11.0 | 6.7x |
| double_squish | 1 | 57.0 | 4.0 | 14.3x |
| double_squish | 25 | 73.0 | 10.0 | 7.3x |
| integer | 1 | 57.0 | 4.0 | 14.3x |
| integer | 25 | 75.0 | 10.0 | 7.5x |
| factor_10 | 1 | 73.0 | 3.0 | 24.3x |
| factor_10 | 25 | 338.0 | 9.0 | 37.6x |
| character_10 | 1 | 74.0 | 11.0 | 6.7x |
| character_10 | 25 | 204.0 | 14.0 | 14.6x |
| character_1e4 | 1 | 73.0 | 12.0 | 6.1x |
| character_1e4 | 25 | 187.0 | 18.0 | 10.4x |
| logical | 1 | 40.0 | 2.0 | 20.0x |
| logical | 25 | 213.0 | 9.0 | 23.7x |
| mapped_discrete | 1 | 56.0 | 6.0 | 9.3x |
| mapped_discrete | 25 | 183.0 | 2.0 | 91.5x |

Both kernels are kept: every input clears 2×. Much of ggplot2's cost is
`scale_apply`'s split, `vec_c()` and reorder, which the kernels skip.
`mapped_discrete` input (the second pass on a discrete scale) needs only a
cast in R and no split.

Step profile (`step-profile.R`, `ALOT_BENCH_CORES=1`, not interleaved, 1e6
rows): for `point_discrete` (the task's target; x and y continuous),
`map_position_1` is 68.2 → 39.1 ms (1.75×) and `map_position_2` 60.8 →
19.1 ms (3.2×); for `boxplot` (discrete x), `map_position_1` is 89.6 →
31.9 ms (2.8×). The step includes more than the kernels. Timed alone on
the `point_discrete` layer, the step is about 19 ms with kernels on, of
which `match(PANEL, …)` in the `Layout$map_position` mirror is 8 ms and
each kernel call about 4 ms.

### T1.3 Scale transforms (2026-10-30) — kept

`inst/bench/scale-transform.R`: `scales_transform_df()` for one column of
1e6 values through one transformed scale, sequential with interleaved reps
and a full gc before each (same machine as the baseline). Doubles are
`rexp()` with 1% NA; the `zeros` inputs also hold 1% zeros and negatives,
so both of R's warnings fire; integers are 1–1000 with NA.

| input | ggplot2_ms | alot_ms | speedup |
| --- | ---: | ---: | --- |
| log10_double | 20.9 | 14.4 | 1.4x |
| log10_zeros | 20.0 | 16.0 | 1.3x |
| log10_integer | 24.6 | 10.5 | 2.3x |
| sqrt_double | 10.4 | 3.8 | 2.8x |
| sqrt_zeros | 15.9 | 9.5 | 1.7x |
| sqrt_integer | 11.4 | 3.8 | 3.0x |
| reverse_double | 4.7 | 1.6 | 2.9x |
| reverse_integer | 4.2 | 1.1 | 3.7x |

- **All three are kept for both types** under the 1.25× rule. log10 of
  doubles was first dropped under the old 2× rule, then restored when the
  threshold changed. Exactness requires calling the C library's `log10`, as
  R does, and that call is most of the time on both sides (about 14 ms of
  21). Rust only saves `check_transformation()`'s `is.finite()` passes, so
  about 1.4× is the ceiling single-threaded. Integer columns, where ggplot2
  also pays for the coercion, reach 2.3×.
- The `zeros` rows include about 5.5 ms that both paths pay for raising the
  two warnings (`cli::cli_warn()` mostly); the transform itself is as fast
  as in the warning-free rows. Warnings stay in R by design (AGENTS.md).
- `identity` needs no kernel: `ScalesList$transform_df` skips such scales
  before any per-scale work, and the mirror does the same.

### T2.3 Continuous colour scales (2026-10-30) — kept

`inst/bench/npscale-continuous.R`: `npscales_train_df()` and
`npscales_map_df()` for one colour column of 1e6 values through one scale,
sequential with interleaved reps and a full gc before each (same machine as
the baseline). Doubles are `rnorm()` with 1% NA, so nearly every value is
distinct; integers are 1–1000 with NA.

| input | step | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| gradient | train | 19.8 | 2.5 | 8.0x |
| gradient | map | 212.3 | 109.5 | 1.9x |
| gradient_integer | train | 5.8 | 2.0 | 2.9x |
| gradient_integer | map | 77.1 | 19.2 | 4.0x |
| gradient2 | train | 5.4 | 2.5 | 2.2x |
| gradient2 | map | 227.2 | 108.7 | 2.1x |
| gradientn_values | train | 5.4 | 2.4 | 2.2x |
| gradientn_values | map | 241.2 | 130.8 | 1.8x |
| distiller | train | 5.4 | 2.4 | 2.2x |
| distiller | map | 234.1 | 113.9 | 2.1x |
| viridis | train | 6.1 | 3.2 | 1.9x |
| viridis | map | 224.3 | 112.4 | 2.0x |
| viridis_alpha | train | 6.2 | 3.2 | 1.9x |
| viridis_alpha | map | 239.6 | 133.7 | 1.8x |

- **Both kernels are kept.** (The first `gradient` train row includes a
  one-off warm-up on the ggplot2 side; the others are about 5.5 ms.)
- **Distinct values cap the map at about 2×.** Each distinct value still
  needs three `pow()` calls in Lab → sRGB (the system libm's, for
  byte-identical hex) and a new CHARSXP, as in farver. Rust skips R's
  `unique()`/`match()`, the four `approxfun()` passes and the intermediate
  vectors.
- **Repeated values are coded first.** Like upstream, Rust colours each
  unique value once and matches rows to it, which matters for integers
  (4×). Hashing a million distinct doubles cost about 70 ms, though, which
  brought the `rnorm()` rows down to 1.2×. So Rust first codes a sample of
  4,096 rows, and if more than half are distinct it colours row by row
  instead.

Step profile (`step-profile.R`, `ALOT_BENCH_CORES=1`, not interleaved, 1e6
rows): for `point_continuous` (the task's target), `npscales_map` is 205.3
→ 106.4 ms (1.93×). The whole build is 435.9 → 220.5 ms (1.98×), counting
the position kernels.

### T2.4 Discrete non-position scales (2026-10-30) — kept

`inst/bench/npscale-discrete.R`: `npscales_train_df()` and
`npscales_map_df()` for one aesthetic column of 1e6 values through one
scale, sequential with interleaved reps and a full gc before each (same
machine as the baseline). Characters hold 10 distinct values, factors 5
and logicals 2, each with 1% NA, in random order.

| input | step | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| hue_character | train | 7.7 | 4.4 | 1.7x |
| hue_character | map | 30.4 | 11.2 | 2.7x |
| hue_factor | train | 19.9 | 2.4 | 8.2x |
| hue_factor | map | 20.3 | 4.5 | 4.5x |
| brewer_factor | train | 19.9 | 2.5 | 8.1x |
| brewer_factor | map | 16.4 | 4.5 | 3.7x |
| manual_named | train | 7.7 | 4.4 | 1.7x |
| manual_named | map | 17.4 | 7.7 | 2.3x |
| shape_factor | train | 19.8 | 2.4 | 8.2x |
| shape_factor | map | 14.3 | 2.2 | 6.4x |
| linetype_character | train | 7.6 | 4.4 | 1.8x |
| linetype_character | map | 13.4 | 7.6 | 1.8x |
| hue_logical | train | 6.4 | 1.6 | 3.9x |
| hue_logical | map | 18.9 | 3.8 | 5.0x |

- **Both kernels are kept.** Character columns gain least: upstream's
  `match()` already hashes CHARSXP pointers, and Rust still has to code
  every row (`rs_factorize_strings()`) before R can map the distinct values,
  then gather. Factors skip `as.character()` and, in training,
  `droplevels()`.

Step profile (`step-profile.R`, `ALOT_BENCH_CORES=1`, not interleaved, 1e6
rows): for `point_discrete` (a 5-level factor colour), `npscales_train` is
33.0 → 1.7 ms and `npscales_map` 29.5 → 7.4 ms (3.97×). The whole build is
287.5 → 150.6 ms (1.91×), counting the position kernels.

### T5.1 Facet layout and panel assignment (2026-10-30) — kept

`inst/bench/facet-map.R`: the `layout_setup` step (`Layout$setup`, whose
`facet$compute_layout` and `facet$map_data` the kernels replace) for one
layer of 1e6 rows, sequential with interleaved reps and a full gc before
each (same machine as the baseline). Facet columns hold 9 values (3 × 3 for
the grid) plus 1% NA, in random order.

| input | ggplot2_ms | alot_ms | speedup |
| --- | ---: | ---: | --- |
| wrap_factor | 67.7 | 12.3 | 5.5x |
| wrap_character | 93.7 | 38.3 | 2.4x |
| wrap_integer | 82.4 | 33.5 | 2.5x |
| grid_factor | 190.2 | 22.0 | 8.6x |

- **Both kernels are kept.**
- **`compute_layout`:** `combine_vars()` spends its time in
  `unique0(vec_rbind0(...))` over every layer's facet values, including the
  plot data. Rust first cuts each layer down to the first row of each
  distinct combination, using an equality at least as strict as vctrs'.
  R's `unique0()` then runs on a few rows. Hashing every row as a
  `Vec<u64>` made character and integer columns slower than before; dense
  per-column codes, combined as `id()` does, fixed that.
- **`map_data`:** Rust replaces `join_keys()` + `match()`. For factor
  columns it also skips `addNA()`, which re-codes the whole column through
  `as.character()` when it holds NA. Character and integer columns still go
  through upstream's `factor()` in R, which is most of what remains for
  them.

Step profile (`step-profile.R`, `ALOT_BENCH_CORES=1`, not interleaved):
for `facet_wrap_point` at 1e6 rows, `layout_setup` is 32.1 → 11.6 ms
(2.78×) and the whole build 257.8 → 138.7 ms (1.86×), counting the
position kernels. For `wrap_fixed_point` at 400 panels, `layout_setup`
is 4.7 → 2.6 ms (1.78×).

### T5.2 Batched `labeling::extended` (2026-10-30) — no kernel yet

`inst/bench/extended-breaks.R`: breaks for 400 axis ranges (as for a
400-panel free-scale facet), `scales::extended_breaks()` per range vs one
`rs_extended_breaks()` call, sequential with interleaved reps and a full gc
before each. The ranges come from 50 normal draws with random centre and
spread.

| input | labeling_ms | alot_ms | speedup |
| --- | ---: | ---: | --- |
| 400 ranges | 134.0 | 1.3 | 103x |

- No build step uses this yet; T5.3 calls it from `setup_panel_params`, and
  the 1.25× rule applies there.
- **Exactness:** `labeling` computes `lmin %% lstep`, and R's `%%` uses x87
  long doubles (and warns only above `1/LDBL_EPSILON`). Doubles give a
  different remainder for about a fifth of break-like inputs, so
  `alot_core::breaks::fmod` emulates the 64-bit-significand operations in
  software. It runs only when the candidate labels span 0, the one case
  where the remainder matters; otherwise only its warning condition is
  checked.

### T5.3 Panel params, deduplicated per axis (2026-10-30) — kept

`inst/bench/panel-params.R`: the `setup_panel_params` step at 100 panels
(200 rows per panel), sequential with interleaved reps and a gc before
each.

| case | ggplot2_ms | alot_ms | speedup |
| --- | ---: | ---: | --- |
| wrap_free_point | 388.4 | 147.5 | 2.63x |
| grid_free_point | 313.2 | 37.3 | 8.39x |
| wrap_fixed_point | 3.7 | 2.2 | 1.68x |

Whole build (`facet-scaling.R`, `ALOT_BENCH_CORES=1`, 100 panels): wrap
free 722 → 470 ms (1.54×), grid free 572 → 299 ms (1.91×), wrap fixed
27 → 20 ms (1.35×). Before this task the free cases were about 1.0×.

- **Kept.**
- Each primary view scale was built twice by ggplot2 (the secondary
  rebuilds it) and once per COORD; breaks are now computed once per
  distinct x and y scale. The grid case gains most: 10 × 10 COORDs, but
  only 10 + 10 distinct scales.
- `extended_breaks()` calls go to one batched Rust call (T5.2), which
  removed `labeling::extended` (about 40% of ggplot2's step).
- Building one `guide_none()` per step and copying it saves about 15%.
- What remains is mostly ggproto `$` lookups inside ggplot2's own helpers
  (`expand_limits_scale`, `get_breaks_minor`) and the `ggproto()` calls
  per COORD, which must stay to give each panel its own objects.

### T5.4 Panel guides, trained per axis (2026-10-31) — kept

`inst/bench/panel-guides.R`: the `setup_panel_guides` step, sequential with
interleaved reps and a gc before each.

| case | panels | ggplot2_ms | alot_ms | speedup |
| --- | ---: | ---: | ---: | --- |
| wrap_free_point | 100 | 241.6 | 92.7 | 2.61x |
| grid_free_point | 100 | 243.7 | 47.9 | 5.09x |
| wrap_fixed_point | 100 | 2.9 | 2.0 | 1.42x |
| wrap_free_point | 400 | 1,052 | 391 | 2.69x |
| grid_free_point (20 × 20) | 400 | 1,057 | 173 | 6.12x |

Whole build (`facet-scaling.R`, `ALOT_BENCH_CORES=1`, 100 panels): wrap free
748 → 340 ms (2.20×), grid free 596 → 111 ms (5.37×), wrap fixed 29 → 21 ms
(1.38×). Together with T5.3 the free cases were about 1.0× before.

- **Kept.**
- ggplot2 trains and transforms two axis guides per COORD through ggproto
  (`inject`, `fetch_ggproto`, `Map`, `coord$transform`, `coord_munch`), about
  2.4 ms per COORD. With default axis guides on CoordCartesian or CoordFixed
  the x guide's params depend on the x view scale alone, apart from the key's
  `y` column, which is the y scale's rescaling of ±Inf (0 or 1). The guides
  are therefore trained once per distinct SCALE_X and SCALE_Y, and the ±Inf
  column is filled in per COORD. This alone helps the grid case (20 + 20
  scales, 400 COORDs); the free `facet_wrap` case has no repeats, so its
  gain comes from replacing the generic path: `extract_key` is inlined (the
  `$<-`/`data_frame` calls dominated), the key, decor and ±Inf go through one
  `rescale()`, and the hash is taken directly.
- `coord$setup_panel_guides` still runs per COORD (about a third of what is
  left): the Guides objects capture the frame of that call, including the
  panel's scales, and `expect_equal()` compares those frames, so they can't
  be cloned.
- Declines (falls back whole): user guides on the plot or a scale, secondary
  axes, `cap`, minor ticks, non-axis guides, no breaks, a non-finite or
  zero-width range (where rescaling ±Inf is no longer 0 or 1), `reverse`,
  other coords, overridden coord or facet methods.

### T5.5 Facet-scaling verification (2026-10-31)

`facet-scaling.R`, release build, `ALOT_BENCH_CORES=1`, 200 rows per panel,
whole `alot_build()` vs `ggplot_build()`:

| case | panels | ggplot2_ms | alot_ms | speedup | alot_ms_per_panel |
| --- | --- | ---: | ---: | --- | ---: |
| wrap_fixed_point | 25 | 21 | 19 | 1.11x | 0.8 |
| wrap_fixed_point | 100 | 25 | 20 | 1.25x | 0.2 |
| wrap_fixed_point | 400 | 40 | 28 | 1.43x | 0.1 |
| wrap_fixed_point | 1600 | 278 | 209 | 1.33x | 0.1 |
| wrap_free_point | 25 | 199 | 95 | 2.09x | 3.8 |
| wrap_free_point | 100 | 754 | 341 | 2.21x | 3.4 |
| wrap_free_point | 400 | 3,017 | 1,335 | 2.26x | 3.3 |
| wrap_free_point | 1600 | 13,508 | 6,113 | 2.21x | 3.8 |
| grid_free_point | 25 | 166 | 44 | 3.77x | 1.8 |
| grid_free_point | 100 | 602 | 109 | 5.52x | 1.1 |
| grid_free_point | 400 | 2,299 | 345 | 6.66x | 0.9 |
| grid_free_point | 1600 | 10,229 | 1,347 | 7.59x | 0.8 |
| wrap_histogram | 25 | 234 | 232 | 1.01x | 9.3 |
| wrap_histogram | 100 | 858 | 853 | 1.01x | 8.5 |
| wrap_histogram | 400 | 3,635 | 3,644 | 1.00x | 9.1 |
| wrap_histogram | 1600 | 21,140 | 20,931 | 1.01x | 13.1 |

- **Targets met.** At 400 panels both free-scale cases are over 2×
  (wrap 2.26×, grid 6.66×), and the fixed-scale control is faster (1.43×),
  not slower.
- **Linear growth.** Per-panel cost is flat from 100 to 1,600 panels for the
  point cases (wrap free 3.4 → 3.8 ms, grid free 1.1 → 0.8, fixed 0.2 →
  0.1); there is no per-panel overhead left to fix. The wrap histogram's
  per-panel cost rises at 1,600 (8.5 → 13.1 ms) in both ggplot2 and alot's
  time, which are equal there, so it is the unported stat/geom work and
  memory pressure, not a facet step.
- **Histogram:** 1.0× at every size. Its 5× target waits for the deferred
  T3.3 and T4.1; these are its current numbers.
- What remains in `wrap_free_point` (about 3.3 ms per panel) is ggplot2's
  own `setup_panel_params`/`setup_panel_guides` object construction per
  COORD, which must stay to give each panel its own objects (T5.3, T5.4).

### T6.2 Overhead around the position scale kernels (2026-10-31)

README plot (1e6 rows, `facet_wrap`, log x, continuous colour, discrete
shape), kernels on, release build, median of 7 `step_times()` runs.

Profile split of one layer's data (ms), before the change:

| piece | ms |
|---|---:|
| `match(layer_data$PANEL, panels$PANEL)` (factor, 1e6 rows) | 12–14 |
| `rs_train_continuous_grouped()` per variable (Rust) | 4 |
| `rs_map_continuous()` per variable (Rust) | 3 |
| `panels$SCALE_X[match_id]`, `as.integer()`, `rebuild`/assignment | 1–2 |

`train_position_1` was 37 ms in `facet_train_scales()` (one `match()` plus
two Rust trains) and `layout_map_position()` 39 ms (one `match()` plus two
maps). The factor `match()` was a third of each: it converts every row to a
string. `match_panel()` matches the 6 levels and indexes by the codes
instead (2 ms); it equals `match()` for any factor, with NA codes kept.

| step | before | after |
|---|---:|---:|
| train_position_1 | 32.2 | 18.0 |
| map_position_1 | 34.4 | 22.2 |
| train_position_2 | 28.4 | 25.6 |
| map_position_2 | 21.7 | 11.2 |

- What remains in train/map is the Rust compute (4 ms per variable train,
  3 ms per map) plus the data-frame column assignment. Called alone,
  `facet_train_scales()` on the final data takes 14 ms, but inside
  `train_position_2` it measures 25 ms; the difference is the garbage
  collection of the previous steps' columns, which lands in that step, not
  work the step does.
- Columns are converted once per variable already (`as.integer(scale_id)` is
  free for the integer match result), so no further conversion was found.

### T6.1 Re-profile after the kernels (2026-10-31)

Kernels on, release build, `ALOT_BENCH_CORES=1`, median of 3 `step_times()`
runs per case. Row cases at 1e6 rows, facet cases at 400 panels. The five
steps T6.1 names, in ms and as a share of that case's build time:

| step | row cases (ms; share) | facet cases (ms; share) |
|---|---|---|
| `compute_geom_2` | point_discrete 14.2 (5%), point_continuous 14.2 (6%), facet_wrap_point 9.0 (9%); the other five 1.6–2.1 (≤1%) | 2.0–2.6 (≤0.7%; 10% of wrap_fixed_point) |
| `compute_geom_1` | 0.2–1.0 (≤0.6%) | 0.2 (wrap_histogram 18.5, 0.5%) |
| `finish_statistics` | 0.1 (<0.1%) | 0.1 (<0.1%) |
| `layout$finish_data` | 0.1 (<0.1%) | 0.1 (<0.1%) |
| `.ignore_data`/`.expose_data` (4 calls) | ≤0.1 each (<0.1%) | ≤0.1 each (<0.1%) |

Ranked by share of build time: `compute_geom_2` (5–9% on the point cases),
`compute_geom_1` (≤0.6%), then `finish_statistics`, `finish_data` and
`.ignore_data`/`.expose_data` (<0.1% each).

- **T6.3 opened** for `compute_geom_2` on `geom_point`: its 14 ms at 1e6 rows
  is dominated by writing constant default-aesthetic columns, which a
  parallel Rust fill could plausibly do 1.25× faster. The task profiles
  first and drops the kernel if the time turns out to be elsewhere.
- **Stays in R:** `compute_geom_1`, `finish_statistics`, `finish_data`,
  `.ignore_data`/`.expose_data`. Each is at most 1 ms at 1e6 rows or 400
  panels, so even an infinite speedup would not move the build.
  `compute_geom_2` on the stat-based geoms (1.6–2.1 ms) stays too.
- **Where the time is now** (not part of this task's list): `compute_statistic`
  is 47–70% of the histogram, bar, density, boxplot and smooth cases at 1.0×
  (smooth 1.87×), and `compute_position` is 44% of `wrap_histogram` at 400
  panels; these wait on the deferred stat and position kernels (T3.x, T4.1).
  `compute_aesthetics` is 5–20% at 1.0× (62 ms on bar_dodge); it evaluates
  the user's aesthetics expressions, so it stays in R. `npscales_map` is
  still 105 ms (55%) on `point_continuous` after T2.3. In the facet cases,
  `setup_panel_params` and `setup_panel_guides` are 87% of `wrap_free_point`
  (T5.3, T5.4).

## Phase 2 prototype: README plot to PNG (2026-10-30)

Experimental (branch `proto/phase2-points`). `inst/bench/render-readme.R`
times the README example plot (1e6 points, `facet_wrap`, log x, viridis
colour, four shapes, `alpha = 0.3`) from ggplot to a 1600 × 1000 PNG at
150 dpi. Medians of 7 interleaved runs:

| step   | ggplot2 | alot   | speedup |
|--------|--------:|-------:|--------:|
| build  | 411 ms  | 195 ms | 2.1×    |
| gtable | 420 ms  | 212 ms | 2.0×    |
| draw   | 2541 ms | 188 ms | 13.5×   |
| total  | 3384 ms | 595 ms | 5.7×    |

ggplot2's path is `ggplot_build()`, `ggplot_gtable()`, then grid drawing on
`ragg::agg_png()`. alot's is `alot_build()`, `alot_gtable()`, then grid
drawing on `ragg::agg_capture()` with the PNG encoded in Rust (what
`alot_png()` does). The images match closely: mean |diff| 0.37 of 255, max
15, and 0.02% of pixels differ by more than 8.

What the prototype does:

- **Points are rasterised in Rust.** `alot_gtable()` gives `GeomPoint`
  layers a lazy grob per panel. At draw time on a ragg device, it renders
  the panel's points into a pixel-aligned raster and draws that with
  `grid.raster()`. Symbols are coverage sprites per (shape, size, lwd) at
  1/8-px offsets, cached for the process, and are blended in parallel row
  bands in data order. Circles use ragg's own polygon step counts; with
  true discs, edges were measurably darker. Anything else falls back to
  ggplot2's `pointsGrob`: other shapes, NA, non-cartesian coords, `clip =
  "off"`, or a non-ragg device.
- **The PNG is encoded in Rust.** libpng at ragg's default zlib level took
  112 ms for this image; the `png` crate's fast mode with capture readback
  takes about 20 ms.

Where the draw time went, in ggplot2's path. 97% of the draw step was
`drawDetails.points`, i.e. ragg rasterising 1e6 point symbols. For alot,
`GeomPoint$draw_panel` (`alpha()` encode/decode and splitting the data by
panel) was about 290 ms of the gtable step; the alot point path takes
17 ms.

Remaining time in alot's 595 ms, roughly:

- **build, 195 ms:** position train and map (T6.2), plus
  `compute_aesthetics`, `guides_build` and the npscales.
- **gtable, 212 ms:** about 17 ms for the point layer. The rest is
  ggplot2's facet render (axes, strips, theme elements, S7 validation,
  guides), which doesn't depend on the row count: 141 ms on the same plot
  with 10 rows.
- **draw, 188 ms:** about 90–115 ms for the Rust point render (six panels,
  each about 15 ms: about 6 ms blending on 16 threads, the rest placing
  points serially and per-call overhead). Then about 50 ms for ragg drawing
  text, axes and backgrounds, and about 20 ms for PNG encoding.

The hybrid's floor (ggplot2's gtable and ragg for everything except points)
is about 210 ms with no points at all. Removing that floor needs the full
Phase 2 design: layout and text in Rust, replacing `ggplot_gtable()`, grid
and ragg. That would leave roughly the build plus the point render (an
estimate of about 0.3 s, not measured). The cheaper next steps inside the
hybrid are rendering all panels in one parallel call and placing points in
parallel (an estimated 50 ms saving).

### R0.1: hybrid tier landed (2026-10-30)

The prototype is now the hybrid tier (`alot_png()`, with
`alot_render_coverage()`). Same benchmark, release build, medians of 7
interleaved runs:

| step   | ggplot2 | alot   | speedup |
|--------|--------:|-------:|--------:|
| build  | 447 ms  | 189 ms | 2.4×    |
| gtable | 388 ms  | 207 ms | 1.9×    |
| draw   | 2531 ms | 170 ms | 14.9×   |
| total  | 3428 ms | 567 ms | 6.0×    |

Pixels as before (max |diff| 15, 0.018% differ by more than 8).
`alot_png()` on the built plot takes about 370 ms end to end; the tier
check (`render_coverage()`) is about 6 ms of that.

### R0.2: point sprites at 1/16-px offsets (2026-10-30)

The render harness showed point edges differing from ragg on 0.2–0.7% of
pixels (more than 8 of 255) with sprites at 1/8-px offsets. At 1/16 px
(`SUB = 16`, still 16 × 16 coverage samples) that drops to about 0.04%;
1/32 px would be near zero but costs 4× more per sprite set again. README
benchmark, release build, 7 interleaved runs: draw 170 → 197 ms, total
567 → 592 ms (ggplot2 3386 ms). Pixels: max |diff| 15 → 11; 0.018% →
0.002% differ by more than 8. A new sprite set (size 7.3 at 300 dpi) costs
about 0.37 s to build, 4× the 1/8-px cost; R1.2's lazy per-offset sprites
should remove most of that.

## Render suite baselines (R0.3, 2026-10-30)

`inst/bench/render-suite.R` replaces the prototype's `render-readme.R`. It
times each stage from a ggplot to a PNG file for ggplot2 + ragg and for the
hybrid tier (build, gtable, draw, encode; "render" is gtable + draw +
encode). Each path uses its own build (`ggplot_build()` / `alot_build()`).
The device is opened before the gtable is built, as `print.ggplot()` does;
this makes ggplot2's README gtable step slower than the prototype measured
(about 780 vs 420 ms: text is measured on ragg, and the measurement is
now inside the step). Runs are sequential, the two paths interleaved,
with an untimed warm-up rep per case. Later tasks add the full tier's
stages (IR, layout, raster, encode).

```sh
NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE); source("inst/bench/render-suite.R")'
```

R version 4.6.1 (2026-06-24); Ubuntu 22.04.5 LTS; ggplot2 4.0.3; ragg 1.5.2; alot 0.0.0.9000; 16 threads available. Medians of interleaved runs, ms.

#### readme (1600 x 1000 px, 150 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 538 | 222.0 | 2.4x |
| gtable | 780 | 211.0 | 3.7x |
| draw | 2,442 | 174.0 | 14.0x |
| encode | 113 | 10.0 | 11.3x |
| render | 3,320 | 395.0 | 8.4x |
| total | 3,766 | 617.0 | 6.1x |

#### readme_page (7 x 7 in, 300 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 530 | 216.0 | 2.5x |
| gtable | 674 | 224.0 | 3.0x |
| draw | 3,951 | 217.0 | 18.2x |
| encode | 384 | 23.0 | 16.7x |
| render | 5,014 | 463.0 | 10.8x |
| total | 5,532 | 682.0 | 8.1x |

#### readme_10 (1600 x 1000 px, 150 dpi; 7 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 29.0 | 30.0 | 1.0x |
| gtable | 148.0 | 148.0 | 1.0x |
| draw | 72.0 | 60.0 | 1.2x |
| encode | 34.0 | 4.0 | 8.5x |
| render | 255.0 | 211.0 | 1.2x |
| total | 284.0 | 242.0 | 1.2x |

#### point_1e6 (1600 x 1000 px, 150 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 338.0 | 136.0 | 2.5x |
| gtable | 302.0 | 49.0 | 6.2x |
| draw | 6,475.0 | 110.0 | 58.9x |
| encode | 44.0 | 4.0 | 11.0x |
| render | 6,821.0 | 164.0 | 41.6x |
| total | 7,163.0 | 294.0 | 24.4x |

#### tile_1000 (1600 x 1000 px, 150 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 1,217 | 681.0 | 1.8x |
| gtable | 368 | 403.0 | 0.9x |
| draw | 935 | 831.0 | 1.1x |
| encode | 195 | 14.0 | 13.9x |
| render | 1,498 | 1,307.0 | 1.1x |
| total | 2,715 | 1,979.0 | 1.4x |

#### line_1e6 (1600 x 1000 px, 150 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 283.0 | 140.0 | 2.0x |
| gtable | 660.0 | 711.0 | 0.9x |
| draw | 513.0 | 488.0 | 1.1x |
| encode | 36.0 | 4.0 | 9.0x |
| render | 1,228.0 | 1,202.0 | 1.0x |
| total | 1,521.0 | 1,342.0 | 1.1x |

#### facets_400 (1600 x 1000 px, 150 dpi; 3 reps)

| step | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| build | 26.0 | 22.0 | 1.2x |
| gtable | 10,185.0 | 9,741.0 | 1.0x |
| draw | 2,025.0 | 2,106.0 | 1.0x |
| encode | 39.0 | 8.0 | 4.9x |
| render | 12,249.0 | 11,855.0 | 1.0x |
| total | 12,275.0 | 11,877.0 | 1.0x |

#### Render (gtable + draw + encode)

| case | ggplot2 | hybrid | speedup |
| --- | ---: | ---: | --- |
| readme | 3,320 | 395 | 8.4x |
| readme_page | 5,014 | 463 | 10.8x |
| readme_10 | 255 | 211 | 1.2x |
| point_1e6 | 6,821 | 164 | 41.6x |
| tile_1000 | 1,498 | 1,307 | 1.1x |
| line_1e6 | 1,228 | 1,202 | 1.0x |
| facets_400 | 12,249 | 11,855 | 1.0x |

Reading these:

- **Points are where the hybrid wins.** 1e6 points with no axes render
  42× faster; the README plot 8.4×, and 10.8× on the default page.
- **Without a Rust drawer the hybrid is ggplot2** plus Rust PNG encoding:
  tiles (1.1×), lines (1.0×) and 400 panels (1.0×). Rects (R1.3) and paths
  (R1.4) are what the hybrid gains next.
- **The fixed cost is ggplot2's gtable.** 148 ms of the 211 ms for the
  README plot with 10 rows, and nearly 10 s for 400 panels, where drawing
  adds 2 s. Only the full tier removes it.
- **Encoding** is 4–23 ms in Rust against 34–384 ms for ragg's libpng.

## R1.1: display list and band executor (2026-10-30)

`cargo run --release -p alot-core --example points_bench`: a white
background plus 1e6 points (the README plot's shapes, size and alpha) on a
1600 × 1000 page, 64-row bands, medians of 7:

| threads | place | execute |
|---:|---:|---:|
| 1 | 6 ms | 304 ms |
| 2 | — | 168 ms |
| 4 | — | 95 ms |
| 8 | — | 55 ms |

The blend scales 5.6× from 1 to 8 threads. Placement is serial (R1.2
parallelises it); right after multi-threaded runs it measured 30–40 ms
instead of 6 ms, which looks like cache or memory effects rather than
work. Streaming a 20 × 20 in page at 300 dpi (6000 × 6000 px, 1e5 points,
8 threads) took 134 ms and raised peak RSS by 40 MB, within the executor's
band bound of 59 MB (8 × 64 rows × 6000 px × 20 bytes); a single f32 canvas
would be 549 MB.

The hybrid now draws each panel's points as a one-item display list. One
README panel (166,667 points, 470 × 420) takes 17.8 ms, the same as the
prototype's drawer at the same sprite resolution (17–19 ms). The render
suite's README draw step read 195 ms (174 ms at R0.3); 8 and 16 threads
give the same time, and the panel benchmark shows no regression, so this
is run-to-run variation.

## R1.2: point batches for every shape (2026-10-30)

Sprites are now rasterised with a port of AGG's exact-area rasteriser and
stroker (`alot-core/src/render/agg.rs`), the code ragg draws symbols with,
at 1/32-px offsets built lazily per offset. Placement is parallel, with no
hashing while the size and stroke stay constant. The hybrid clips each
point to the panel in Rust (geometrically where a clip edge crosses it),
as ragg clips each mark, and draws its raster unclipped.

Distinct sizes (`cargo run --release -p alot-core --example size_bench`,
1e4 points, all sizes distinct, 1600 × 1000): 75 ms cold, 12–14 ms with
the sprites cached.

Render suite, release build (render = gtable + draw + encode, ms):

| case | ggplot2 draw | hybrid draw | ggplot2 render | hybrid render |
|---|---:|---:|---:|---:|
| size_1e4 (size mapped to 1e4 values) | 235 | 55 | 486 | 110 |
| readme | 2445 | 163 | 3249 | 398 |
| readme_page (7 × 7 in, 300 dpi) | 3904 | 333 | 4977 | 576 |
| readme_10 | 74 | 54 | 250 | 200 |
| point_1e6 | 6340 | 141 | 6735 | 213 |

The README draw step is 163 ms (174 ms at R0.3); readme_page is a
pre-row-split measurement. The executor bench (`points_bench`, 1e6 points
on one page) is 62 ms at 8 threads and 327 ms at 1.

Fidelity: every pch 0–25 passes `expect_render_close()` at the default
tolerance across four size/stroke/alpha/dpi combinations, and the render
corpus passes at the default max for all 864 hybrid plots except three
documented overplotting cases (8-bit per-blend rounding in ragg).

## R1.3: rect batches (2026-10-30)

`GeomRect`'s `draw_panel` (and so `geom_tile`, `geom_bar`, `geom_col`,
`geom_histogram`, `annotate("rect")`) draws in Rust in the hybrid tier.
Fill-only rects snap like ragg's `snap_rect`; fills use AGG's coverage
for axis-aligned rects analytically; outlines use the AGG stroker.

Render suite, release build (ms):

| case | ggplot2 draw | hybrid draw | ggplot2 render | hybrid render |
|---|---:|---:|---:|---:|
| tile_1000 (1e6 tiles) | 960 | 62 | 1516 | 330 |
| readme | 2430 | 154 | 3297 | 399 |
| point_1e6 | 6462 | 131 | 6908 | 204 |
| size_1e4 | 240 | 57 | 489 | 112 |

The 1000 × 1000 tile layer draws 15.5× faster than ragg (done-when: 10×)
and is pixel-identical to ragg at 400 × 300 and 1600 × 1000. Rust alone
(`cargo run --release -p alot-core --example rects_bench`): about 48 ms on
8 threads, of which about 37 ms is building the batch.

## R1.4: paths — AGG port vs tiny-skia (2026-10-30)

R1.4 asked for a choice between an AGG-style exact-area rasteriser and
tiny-skia. R1.2 had already ported AGG's rasteriser and stroker (the code
ragg draws with); R1.4 added AGG's dash generator and the even-odd rule.
A scratch comparison (not in the repo, so tiny-skia never became a
dependency) stroked a 1e6-segment polyline at 1600 × 1000, lwd 0.74 px:

| case | AGG port | tiny-skia 0.11 | tiny-skia vs AGG |
|---|---:|---:|---|
| solid | 213 ms | 1370 ms | max 255, 0.51% of pixels differ by > 8 |
| dashed (`lty = 2`) | 159 ms | 643 ms | max 255, 0.55% differ by > 8 |

**Decision: the AGG port.** It is ragg's own algorithm, so coverage
matches ragg exactly (lines, dashes and polygons pass
`expect_render_close()` at max diffs of 0–2), and it is 4–6× faster here
because each row band rasterises only the edges reaching it, in parallel.
tiny-skia differs from ragg on about half a percent of pixels (different
coverage and stroking geometry) and would need its own dash and join
handling to match R.

Render suite, release build (ms):

| case | ggplot2 draw | hybrid draw | ggplot2 render | hybrid render |
|---|---:|---:|---:|---:|
| line_1e6 (`geom_line`, 1e6 points) | 571 | 245 | 1475 | 431 |

## R1.5: PNG output — parallel deflate (2026-10-30)

The encoder now streams rows (from the band executor or a capture) and
compresses in parallel: Sub-filtered rows in ~512 KB chunks, each deflated
at level 1 on its own thread with a sync flush and written as its own IDAT
chunk, the Adler-32 combined from the chunks'. Files carry ragg's IHDR,
bKGD (premultiplied background) and pHYs, in ragg's order, and decode to
the canvas exactly.

Measured first in a scratch crate on deliberately busy synthetic pages
(1e6 points everywhere), median of 5:

| page | fdeflate fast (png crate) | parallel deflate, 8 threads |
|---|---:|---:|
| 1600 × 1000 | 24.5 ms, 2021 KB | 5.4 ms, 2134 KB |
| 2100 × 2100 | 114.3 ms, 6652 KB | 13.2 ms, 7291 KB |

Parallel deflate was adopted (5–9× faster for files 5–10% larger). The
png crate's streaming writer could not use fdeflate's fast path anyway
(streamed encoding measured 20 ms on the README page against 10 ms
whole-image).

On the real README plot (hybrid tier, release), encoding alone takes
8 ms at 1600 × 1000 (1.6 MB) and 19 ms on the 7 × 7 in, 300 dpi page
(3.7 MB). In the render suite the encode step (including ragg's capture
readback) is 10 ms and 25 ms, against ragg's 111 ms and 386 ms.

## R3.1: render IR extraction (2026-10-30)

`inst/bench/render-ir.R`, release build, R functions byte-compiled as in an
installed package; median of 60 runs of `render_ir()` on a built plot.

| Case | render_ir() (ms) | theme only (ms) | Budget |
|---|---:|---:|---:|
| README (1e6 points, 6 panels) | 8.0 | 2.0 | < 10 |
| facets_400 (2e4 points, 400 panels) | 6.0 | 2.0 | < 50 |

- Theme: `calc_element()` on all 160 elements of the element tree costs
  about 53 ms, mostly S7 property validation. `resolve_theme()` resolves
  the tree once, memoised per (element, skip_blank), on plain property
  lists; it equals `calc_element()` on every theme tested.
- Panel params, axis guides and the layers' linear-scale check are taken
  per distinct (SCALE_X, SCALE_Y) pair, so 400 fixed-scale panels cost one
  (59 ms before).
- The README layer's per-row support checks (NA scans and point shapes over
  1e6 rows) went from about 10 ms of separate R passes to one parallel Rust
  scan each (`rs_columns_complete()`, `rs_point_shapes_supported()`), about
  1.5 ms.
- Without byte compilation (`pkgload::load_all()`) the times are the same
  (README 8 ms; theme 3 ms). An earlier draft defined the resolver's helpers
  as closures inside it, which R's JIT recompiled on every call.

## R2.2: glyph drawing in the hybrid tier (2026-10-31)

`inst/bench/render-suite.R`, release build, readme_10 (1600 × 1000, 150 dpi,
7 reps, medians in ms). "Rust text" is `options(alot.hybrid_text = TRUE)`:
each text grob in the gtable draws as a raster from `rs_render_text()`.

| step | ggplot2 | hybrid, ragg text | hybrid, Rust text |
|---|---:|---:|---:|
| draw | 70 | 51 | 70 |
| encode | 35 | 4 | 8 |
| render | 249 | 204 | 225 |

Rust text is slower than ragg's own text in the hybrid (+19 ms draw, +4 ms
encode), so by PHASE2.md's rule that no drawer may be slower than ragg it is
off by default there. The Rust part is only about 5 ms for the page's 12
text grobs; the rest is per-grob grid work (`get.gpar`, `deviceLoc`, a
pushed viewport and a `grid.raster` each, about 0.6 ms) that batching would
only partly remove. The glyph drawer stays for the full tier, where there is
no grid; the hybrid integration remains as the way the tests compare Rust
glyphs with ragg's. Pixel differences from ragg on the tested plots: none
in text pixels.

## R5.1: points in the full tier (2026-10-31)

Release build (`pkgbuild::compile_dll(debug = FALSE)`), 7 × 7 in at 150 dpi,
`alot_png()` end to end (build excluded, PNG written), full tier vs hybrid
tier with reps interleaved, medians:

| case | full | hybrid |
|---|---:|---:|
| 1e3 points | 30 ms | 58 ms |
| 1e6 points | 146 ms | 193 ms |
| 1e6 points, alpha 0.3 | 254 ms (15 reps) | 242 ms (15 reps) |

The alpha case is within run-to-run noise (ranges 205-399 and 227-286 ms).
Its stages, 9-rep medians: `render_ir` 9 ms, `full_points` 24 ms (the point
colours, which the hybrid computes too), `rs_render_page` 157 ms; the whole
`render_full` takes 196 ms against 219 ms for `render_hybrid`, so the full
tier is no slower at drawing. The full tier avoids the hybrid's gtable build
and grid drawing, which is the whole gain at 1e3 points. ggplot2 on ragg took
7.7 s for 1e6 points in an earlier run (debug build of alot, unaffected).

## R5.3: legends in the full tier (2026-10-31)

Release build, 1050 × 1050 px at 150 dpi, the README plot without its facets
(`income`, `spend`, colour `age`, shape `segment`, log x; R5.2's facets are
not built yet), `render_full()` against `render_hybrid()` on a built plot, 5
reps, medians:

| case | full | hybrid |
|---|---:|---:|
| 1e3 points, no legend | 25 ms | 60 ms |
| 1e3 points, colourbar + point legend | 34 ms | 99 ms |
| 1e6 points, no legend | 113 ms | 156 ms |
| 1e6 points, colourbar + point legend | 116 ms | 187 ms |

The legends add 9 ms at 1e3 points, of which `legend_boxes()` (R/render-legend.R:
guide elements, text metrics, key sizes) is 7 ms and Rust's assembly and
drawing under 2 ms. Resolving the guides' theme with ggplot2's own
`setup_elements()` cost 23 ms (S7 validation at every inheritance step), so
`legend_elements()` mirrors it on `theme_calc()`'s property lists, the way
`resolve_theme()` does for the whole theme. The legend adds 3 ms at 1e6
points (within noise), against 31 ms for the hybrid's gtable and grid
drawing.

Pixel fidelity against ggplot2 on ragg at 96 dpi: the colourbar's box differs
by at most 1/255 from ragg's raster, and the legend keys by at most 5 (the
point drawer's sprite coverage, as in the panel). Legend, bar and box sizes
match grid's layout within 0.5 px in every `test-render-legend.R` case.

## R5.2: facet_wrap in the full tier, and the README plot (2026-10-31)

Release build, the README plot (`facet_wrap(~region)`, six panels, colourbar +
shape legend, alpha 0.3, log x), `render_full()` against `render_hybrid()` on a
built plot, 7 reps, medians:

| case | target | full | hybrid |
|---|---:|---:|---:|
| 1e6 rows, 1600 × 1000 at 150 dpi | < 120 ms | 146 ms | 404 ms |
| 10 rows, 1600 × 1000 at 150 dpi | < 25 ms | 47 ms | 218 ms |
| 1e6 rows, 2100 × 2100 at 300 dpi | < 200 ms | 222 ms | 478 ms |

None of the three targets is met yet. Stages (1600 × 1000): `render_ir()` 7-10
ms, `legend_boxes()` 7, the rest of `layout_spec()` 6, `full_panel()` 3,
`full_points()` 20 at 1e6 rows (its colour parsing, 18 ms), and
`rs_render_page()` 23 ms at 10 rows, 101 ms at 1e6. At 10 rows 18 ms of the
Rust time is the blank page (grid lines and panel backgrounds of six panels,
the clear and the raster conversion); the text is about 5 ms. Dealing the
points out to panels in Rust instead of `split()` and subsetting in R took
`full_points()` + page spec from 70 ms to 34 ms.

## R6.1: core geoms in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, one run each:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| `geom_line()`, 1e6 rows | 616 ms | 1704 ms |
| `geom_tile()`, 1000 × 1000 | 386 ms | 947 ms |
| `geom_col()`, 2000 bars | 40 ms | 78 ms |
| `geom_text()`, 5000 labels | 50 ms | 111 ms |

Every drawer is faster than ragg drawing the same marks. These are single
cold runs; the 1e6-row line's steady-state median (5 runs) is 398 ms.

### Line follow-up: R-side preparation in Rust

Profiling the 1e6-row line showed the R-side preparation was about 60% of
the render. The check that aesthetics are constant along each line
(`paths_decline()`) and the grouping and ordering of `full_paths()` now run
in Rust (`rs_constant_by_group()`, `rs_path_groups()`). Steady-state median
of 5 runs: 398 ms before, 280 ms after, with identical pixels. What remains
is `rs_render_page()` (about 230 ms at 8 threads, 460 ms at 1), dominated by
the serial stroke outline of one long path and memory traffic.

Tried and dropped: collapsing runs of vertices in one pixel column to their
first, lowest, highest and last took the draw from about 280 to 75 ms, but
1.4% of pixels differed from ragg by more than 32 (max 235). AGG sums every
edge's signed area, so merging segments is not exact. Computing the stroke
joins in parallel chunks (exact) gave 187 to 125 ms for the joins alone in a
stand-alone benchmark and no change in the plot: the stage is limited by
memory traffic (the outline is over 100 MB). Streaming edges into each band
instead of materialising the outline is the remaining exact option.

## R6.3: facets in full (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, medians of 5–7
runs. `grid_free_1e6` is the new `render-suite.R` case: `facet_grid(a ~ b,
scales = "free", space = "free_x")`, 3 × 4 panels, 1e6 points.

| Plot | Full tier | ggplot2 + ragg | Full tier before R6.3 |
|---|---:|---:|---:|
| `grid_free_1e6` | 194 ms | 3778 ms | (hybrid) |
| README plot, 1e6 rows | 146 ms | 2840 ms | 147 ms |
| README plot, 10 rows | 52 ms | 245 ms | 53 ms |
| `facets_400` (`facet_wrap()`, 400 panels) | 926 ms | 11685 ms | 909 ms |

The fixed-scale cases are unchanged (the "before" column is the parent
commit, run alongside). Per-panel work stays per distinct pair of scales:
panel backgrounds, grid lines, ranges and axes are resolved once per pair
and shared.

## R6.4: legends in full (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, medians of 5
runs. `legends_inside_1e6` is the new `render-suite.R` case: 1e6 points with
`scale_colour_binned()` (colour steps) and `scale_size_binned()` (bins) in a
box inside the panel, with `legend.box.background` and `legend.box.margin`.

| Plot | Full tier | ggplot2 + ragg | Full tier before R6.4 |
|---|---:|---:|---:|
| `legends_inside_1e6` | 141 ms | 6117 ms | (hybrid) |
| README plot, 1e6 rows | 156 ms | 2790 ms | 153 ms |
| README plot, 10 rows | 50 ms | 195 ms | 51 ms |

The README cases are unchanged (the "before" column is the parent commit,
run alongside). The legends themselves cost little: a few dozen marks and
labels. With a continuous `scale_size()` instead of the binned one the same
plot takes about 3.5 s in the full tier (against 4.4 s): every point has its
own size, and drawing 1e6 points of distinct sizes is the point drawer's
cost, not the legend's; it is left to R7.2.

## R6.5a: ribbons in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, median of 3:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| `geom_area(colour = "black")`, 4 stacked groups, 1e6 rows (`area_1e6`) | 2701 ms | 39119 ms |
| `geom_smooth()` (loess) by 3 groups, with ribbons and a legend | 40 ms | 83 ms |

Both are faster than ragg drawing the same marks. The area's 2.7 s has not
been profiled by stage (left to R7.2).

## R6.5b: boxplots, violins and ranges in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, median of 3:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| `geom_errorbar()`, 1e5 bars by 4 colours (`errorbar_1e5`) | 324 ms | 10660 ms |
| `geom_boxplot(notch = TRUE)`, 1e6 rows in 10 groups, with outliers (`boxplot_1e6`) | 58 ms | 199 ms |
| `geom_pointrange()`, 1e4 rows | 50 ms | 240 ms |
| `geom_violin(quantile.linetype = 1)`, 1e5 rows in 5 groups | 39 ms | 120 ms |

Before this task the path drawer rasterised every path over its whole band
of the page (`PathBatch::draw()`, alot-core/src/render/paths.rs), which made
many small paths slower than ragg: 1e5 error bars took 11.4 s, and 1e4
two-point `geom_path()` groups 706 ms to draw. Each path is now rasterised
over its bounding box only (`agg::rasterize_in()` of a box gives the full
rasterisation's alpha); those take 324 ms and 24 ms.

## R6.5c: segments, reference lines and rugs in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, median of 3:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| `geom_segment()`, 1e5 segments by 4 colours (`segment_1e5`) | 295 ms | 402 ms |
| `geom_rug()`, 1e5 rows on two sides (2e5 segments) | 381 ms | 439 ms |
| 100 each of `geom_hline()`, `geom_vline()`, `geom_abline()` over 10 points | 63 ms | 70 ms |

All are faster than ragg, but by less than the other geoms' cases (ragg
draws segments cheaply); not profiled by stage (left to R7.2).


## R6.5d: labels and polygons in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, median of 3:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| `geom_label()`, 2000 overlapping labels filled by 4 groups (`label_2e3`) | 643 ms | 4513 ms |
| `geom_polygon()`, 1e4 outlined triangles filled by 4 groups (`polygon_1e4`) | 62 ms | 130 ms |

Overlapping labels are drawn in batches (a box batch, then a text batch)
that break wherever a label's box would overlap an earlier one in the
batch, so dense labels cost more batches but stay well ahead of ragg.

## R6.6: coord_flip() and coord_transform() in the full tier (2026-10-31)

`render_full()` against ggplot2's gtable drawn on `ragg::agg_capture()` (the
build is not timed), release build, 1600 × 1000 at 150 dpi, median of 3:

| Plot | Full tier | ggplot2 + ragg |
|---|---:|---:|
| 1e5 points coloured by 4 groups, `coord_flip()` (`flip_1e5`) | 344 ms | 798 ms |
| 1e5 log-normal points coloured by 4 groups, `coord_transform(x = "log10", y = "log10")` (`transform_1e5`) | 63 ms | 730 ms |

`coord_flip()` adds only a swap of the marks' columns; `coord_transform()`
places points with `CoordTransform$transform()` in R (vectorised, as ggplot2
does). coord_fixed(), aspect ratios and secondary axes add no per-row work.


## Full benchmark run (2026-10-31)

All suites after R7.1, on a release build: AMD EPYC 9474F, 16 threads; R
4.6.1; Ubuntu 22.04.5 LTS; ggplot2 4.0.3; ragg 1.5.2. The README figures
(`tools/readme-figures.R`) are drawn from these numbers, copied to
`tools/readme-data/bench-*.csv`. Times in ms.

### Render end to end

`inst/bench/render-e2e.R`: from a ggplot to a PNG file, `ggsave()` on
`ragg::agg_png()` vs `alot_png()`, which draws all 18 cases in the full
tier. Sequential, interleaved, medians of 3 (7 for `readme_10`), after a
warm-up rep. Cases are defined in `inst/bench/render-cases.R`; all at 1600
× 1000 px and 150 dpi except `readme_page` (7 × 7 in, 300 dpi).

| case | ggplot2 (ggsave + ragg) | alot (alot_png) | speedup |
| --- | ---: | ---: | --- |
| readme | 3,673 | 315 | 11.7x |
| readme_page | 5,458 | 383 | 14.3x |
| readme_10 | 250 | 79 | 3.2x |
| point_1e6 | 7,408 | 259 | 28.6x |
| size_1e4 | 478 | 72 | 6.6x |
| tile_1000 | 2,832 | 1,027 | 2.8x |
| line_1e6 | 1,738 | 492 | 3.5x |
| facets_400 | 11,801 | 789 | 15.0x |
| grid_free_1e6 | 5,194 | 391 | 13.3x |
| legends_inside_1e6 | 6,628 | 333 | 19.9x |
| area_1e6 | 108,594 | 77,835 | 1.4x |
| errorbar_1e5 | 8,874 | 317 | 28.0x |
| boxplot_1e6 | 715 | 413 | 1.7x |
| segment_1e5 | 535 | 235 | 2.3x |
| label_2e3 | 4,607 | 348 | 13.2x |
| polygon_1e4 | 237 | 87 | 2.7x |
| flip_1e5 | 842 | 83 | 10.1x |
| transform_1e5 | 846 | 104 | 8.1x |

`area_1e6` is dominated by the build: `stat_align` over 1e6 rows takes
about 80 s on both paths (see the render suite below), and drawing is 13×
faster.

### Render suite (hybrid tier)

`inst/bench/render-suite.R`, which times each stage with the full tier off:
build (`ggplot_build()` vs `alot_build()`), then render (gtable + draw +
encode) with ggplot2 + ragg vs the hybrid tier (ggplot2's gtable, marks
drawn in Rust). Medians of 3 (7 for `readme_10`). Per-stage tables are in
the suite's output.

| case | build ggplot2 | build alot | render ggplot2 | render hybrid | render speedup | total speedup |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| readme | 419 | 164 | 3,271 | 426 | 7.7x | 6.4x |
| readme_page | 656 | 185 | 5,064 | 526 | 9.6x | 7.9x |
| readme_10 | 33 | 33 | 277 | 227 | 1.2x | 1.2x |
| point_1e6 | 428 | 114 | 6,933 | 190 | 36.5x | 24.3x |
| size_1e4 | 28 | 27 | 492 | 114 | 4.3x | 3.7x |
| tile_1000 | 1,614 | 777 | 1,624 | 570 | 2.8x | 2.4x |
| line_1e6 | 289 | 128 | 1,568 | 430 | 3.6x | 3.3x |
| facets_400 | 29 | 23 | 12,832 | 13,204 | 1.0x | 1.0x |
| grid_free_1e6 | 746 | 180 | 4,494 | 453 | 9.9x | 8.3x |
| legends_inside_1e6 | 390 | 215 | 6,604 | 258 | 25.6x | 14.8x |
| area_1e6 | 80,640 | 85,383 | 38,272 | 2,909 | 13.2x | 1.3x |
| errorbar_1e5 | 92 | 73 | 9,664 | 345 | 28.0x | 23.3x |
| boxplot_1e6 | 500 | 351 | 264 | 134 | 2.0x | 1.6x |
| segment_1e5 | 66 | 41 | 520 | 271 | 1.9x | 1.9x |
| label_2e3 | 26 | 26 | 4,571 | 4,477 | 1.0x | 1.0x |
| polygon_1e4 | 33 | 28 | 240 | 115 | 2.1x | 1.9x |
| flip_1e5 | 50 | 35 | 828 | 103 | 8.0x | 6.4x |
| transform_1e5 | 52 | 39 | 834 | 127 | 6.6x | 5.2x |

`facets_400` and `label_2e3` gain nothing here because ggplot2 builds their
gtable and draws their strips and labels; the full tier (above) takes them
to 15× and 13×.

### Row scaling

`inst/bench/row-scaling.R`, 6 parallel workers (so read gains under about
1.5× as noise; see "How to read these numbers").

| case | rows | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| point_discrete | 1e4 | 27 | 23 | 1.17x |
| point_discrete | 1e6 | 554 | 182 | 3.04x |
| point_discrete | 1e7 | 7,779 | 2,756 | 2.82x |
| point_continuous | 1e4 | 26 | 24 | 1.08x |
| point_continuous | 1e6 | 598 | 262 | 2.28x |
| point_continuous | 1e7 | 10,394 | 3,396 | 3.06x |
| facet_wrap_point | 1e4 | 25 | 21 | 1.19x |
| facet_wrap_point | 1e6 | 441 | 134 | 3.29x |
| facet_wrap_point | 1e7 | 8,363 | 1,957 | 4.27x |
| histogram_fill | 1e4 | 37 | 35 | 1.06x |
| histogram_fill | 1e6 | 277 | 212 | 1.31x |
| histogram_fill | 1e7 | 4,832 | 2,882 | 1.68x |
| bar_dodge | 1e4 | 61 | 59 | 1.03x |
| bar_dodge | 1e6 | 372 | 281 | 1.32x |
| bar_dodge | 1e7 | 7,563 | 4,165 | 1.82x |
| density_groups | 1e4 | 35 | 33 | 1.06x |
| density_groups | 1e6 | 302 | 228 | 1.32x |
| density_groups | 1e7 | 4,703 | 3,193 | 1.47x |
| boxplot | 1e4 | 37 | 30 | 1.23x |
| boxplot | 1e6 | 506 | 290 | 1.74x |
| boxplot | 1e7 | 7,716 | 2,578 | 2.99x |
| smooth_lm | 1e4 | 29 | 27 | 1.07x |
| smooth_lm | 1e6 | 415 | 342 | 1.21x |
| smooth_lm | 1e7 | 9,255 | 6,057 | 1.53x |

### Facet scaling (200 rows per panel)

`inst/bench/facet-scaling.R`, 6 parallel workers.

| case | panels | ggplot2_ms | alot_ms | speedup |
| --- | --- | ---: | ---: | --- |
| wrap_fixed_point | 25 | 24 | 18 | 1.33x |
| wrap_fixed_point | 100 | 30 | 20 | 1.50x |
| wrap_fixed_point | 400 | 67 | 28 | 2.39x |
| wrap_fixed_point | 1600 | 458 | 62 | 7.39x |
| wrap_free_point | 25 | 207 | 100 | 2.07x |
| wrap_free_point | 100 | 766 | 359 | 2.13x |
| wrap_free_point | 400 | 3,682 | 1,646 | 2.24x |
| wrap_free_point | 1600 | 15,299 | 6,219 | 2.46x |
| grid_free_point | 25 | 164 | 46 | 3.57x |
| grid_free_point | 100 | 684 | 128 | 5.34x |
| grid_free_point | 400 | 2,811 | 415 | 6.77x |
| grid_free_point | 1600 | 10,640 | 1,273 | 8.36x |
| wrap_histogram | 25 | 234 | 232 | 1.01x |
| wrap_histogram | 100 | 999 | 886 | 1.13x |
| wrap_histogram | 400 | 3,810 | 3,683 | 1.03x |
| wrap_histogram | 1600 | 22,243 | 21,508 | 1.03x |

### Per-step time at 1e6 rows

`inst/bench/step-profile.R`, kernels off vs on; the two steps with the most
ggplot2 time, with their speedups. Full tables are in the suite's output.

| case | ggplot2_ms | alot_ms | speedup | largest steps (ggplot2 time), speedup |
| --- | ---: | ---: | --- | --- |
| point_discrete | 424.3 | 175.2 | 2.42x | `map_position_2` 11.67x, `map_position_1` 2.25x |
| point_continuous | 683.2 | 270.2 | 2.53x | `npscales_map` 2.12x, `map_position_2` 11.39x |
| facet_wrap_point | 378.5 | 153.9 | 2.46x | `map_position_2` 6.00x, `map_position_1` 2.72x |
| histogram_fill | 310.3 | 169.7 | 1.83x | `compute_statistic` 1.87x, `map_position_1` 4.89x |
| bar_dodge | 370.4 | 301.9 | 1.23x | `compute_statistic` 0.95x, `compute_aesthetics` 0.96x |
| density_groups | 267.2 | 263.3 | 1.01x | `compute_statistic` 0.80x, `train_position_1` 1.78x |
| boxplot | 412.0 | 303.0 | 1.36x | `compute_statistic` 1.08x, `train_position_1` 2.50x |
| smooth_lm | 324.5 | 289.7 | 1.12x | `compute_statistic` 0.81x, `map_position_1` 2.40x |


### Per-step time at 400 panels

| case | ggplot2_ms | alot_ms | speedup | largest steps (ggplot2 time), speedup |
| --- | ---: | ---: | --- | --- |
| wrap_fixed_point | 50.7 | 25.8 | 1.97x | `map_position_2` 6.24x, `map_position_1` 4.65x |
| wrap_free_point | 3418.0 | 1536.3 | 2.22x | `setup_panel_params` 2.53x, `setup_panel_guides` 2.72x |
| grid_free_point | 2299.8 | 366.4 | 6.28x | `setup_panel_params` 8.78x, `setup_panel_guides` 5.39x |
| wrap_histogram | 3671.7 | 3957.1 | 0.93x | `compute_statistic` 0.94x, `compute_position` 0.90x |

Where the position scales, facets and panel guides dominate, the build is
2–6× faster; plots dominated by stats (`density_groups`, `smooth_lm`,
`wrap_histogram`) stay near 1× until the stat and position kernels land.

## R7.2: performance pass (2026-10-31)

The PHASE2.md targets: the README plot (`render-cases.R`) rendered by
`alot_png()` from a built plot (IR, layout, raster, PNG file; not the
build), release build, 8 threads (the default cap), medians of 9 after a
warm-up rep:

| case | target | before | after |
|---|---:|---:|---:|
| 1e6 rows, 1600 × 1000 at 150 dpi | < 120 ms | 159 ms | 105 ms |
| 1e6 rows, 2100 × 2100 at 300 dpi | < 200 ms | 233 ms | 190 ms |
| 10 rows, 1600 × 1000 at 150 dpi | < 25 ms | 48 ms | 37 ms |

The 10-row target is not met. Of its 37 ms, R takes about 25: `render_ir()`
7 ms (3 of it resolving the theme), `layout_spec()` 13 (titles' and
legends' text metrics, guide elements, facet axes and strips) and the panels
3; Rust draws and encodes the page in about 12. What is left in R is many
small calls, not one stage, and was not worth the restructuring.

What moved:

- **Thread starts.** Display-list batches (paths, rects, buckets, PNG
  chunks) spawned scoped threads even for a handful of marks; at ~25 µs a
  start, a page's 80-100 items cost 5 ms in bucketing alone.
  `raster::par_map()` runs the first chunk on the calling thread, so
  single-chunk work spawns nothing. The 10-row page's Rust time fell from
  19 to 9 ms.
- **First touch of fresh memory.** Faulting in multi-megabyte buffers on
  one thread took longer than filling them. The point spec's columns are
  dealt to panels in one pass of parallel chunks (`deal()`, alot-r
  page.rs), each column read once instead of once per panel (parse 25 → 6
  ms at 1e6 rows); `PointBatch::from_fn()` writes its placements from the
  workers (6 × 2 ms of serial faulting gone) and folds the row range there.
  Bucketing chunks are 16k marks, not 64k, so a 167k-point panel uses all
  workers (9 → 6 ms).
- **Point colours.** `rs_point_colours()` finds the distinct CHARSXPs in
  parallel, parses them on the main thread and maps rows in parallel into
  the R vector (16 → 3 ms at 1e6 rows); the default all-NA fill is no
  longer `as.character()`ed and parsed (12-20 ms).
- **PNG.** `alot_png()` streams the full tier's bands into the encoder
  (`rs_render_page_png()`), without a nativeRaster in R (an 18 MB allocation
  at 300 dpi, which sometimes triggered a 15-20 ms GC) and its separate
  pass; pixels are packed to bytes in the compressing workers, not on the
  main thread. Output is byte-identical (test-render-tiers.R).
- **Unpremultiply** skips the division for opaque pixels and rounds without
  libm's `roundf()`, bit-identical (raster.rs test).
- **R.** `text_fonts()` caches font matches for one render (19 calls of
  `systemfonts::match_fonts()` at 0.3 ms each); the plot background is read
  from the built plot's theme instead of `get_plot_background()`'s second
  `plot_theme()` and `check_theme()` (3 ms).

Tried and dropped: per-row runs of non-zero coverage in point sprites
(slower at 300 dpi: 83 vs 64 ms for 1e6 points), packing each subpixel
slot's masks into one arena (2 ms of 40, not worth the code), a branch-free
blend loop (no gain).

**Thread scaling** (1e6 points of the README's four shapes on 1600 × 1000,
raster draw only, after placement): 1 thread 222 ms, 4 76 ms, 8 40 ms, 16
22 ms: near-linear, so the 8-thread default cap (PHASE2.md decisions) is
what keeps the 300 dpi page at 190 ms; `options(alot.threads = 16)` gives
more on this machine. **Memory at 300 dpi:** the executor holds 8 band
buffers of 64 × 2100 px (21.5 MB with the output rows, `band_memory()`), and the page itself
is no longer materialised for `alot_png()`; the point layer's dealt
columns (about 48 MB for 1e6 rows) and placements (24 MB) dominate.

## S0.2: spatial baseline (2026-11-01)

`inst/bench/spatial.R` (SPATIAL.md, Verification), release build,
sequential with ggplot2 and alot interleaved, 7 × 7 in at 300 dpi (a
2100 × 2100 page) for every case:

```sh
NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE)'
NOT_CRAN=true Rscript -e 'pkgload::load_all(compile = FALSE, helpers = FALSE); source("inst/bench/spatial.R")'
```

The whole suite takes about 3 minutes. R 4.6.1, ggplot2 4.0.3, ragg 1.5.2, sf 1.1.3 (GEOS 3.10.2,
GDAL 3.4.1, PROJ 8.2.1), 16 vCPUs. Cases:

- `raster_<n>`: an n × n raster in EPSG:3577 metres, about half the cells
  absent (an irregular disc of "land"), continuous `suitability`,
  `geom_raster()` + `scale_fill_viridis_c()` + `coord_fixed()`. Rows: 500²
  0.13e6, 1000² 0.51e6, 2000² 2.02e6.
- `sf_<k>_<crs>`: k jagged polygon features (1e2, 1e3, 1e4) with 1e6
  vertices in total, `geom_sf(aes(fill = value), colour = "grey20")`, in
  EPSG:3577 or EPSG:4326, with the default `coord_sf()` (the data's CRS).
  `sf_1e3_reproject` draws the 4326 layer in `coord_sf(crs = 3577)`.
- `north_star`: SPATIAL.md's map. A 2000² raster (2.02e6 rows) and 500
  features with 1e6 vertices, both in 3577. `north_star_facet` has four
  species with a 1000² raster each (2.02e6 rows in all) in `facet_wrap()`,
  with the sf layer drawn in every panel (4e6 vertices drawn).
- `real_sf`, `real_raster`, `real_north_star`: opt-in, read from
  `ALOT_SPATIAL_DATA`. This machine has no real data. The code path was
  checked once with `nc.shp` and a small `.rds` grid.

Stages: **build** (`ggplot_build()` / `alot_build()`); **decide** (alot
only: `render_raster()`'s full-tier attempt and `render_coverage()`);
**gtable** (`ggplot_gtable()` on the open ragg device); **draw**
(`grid.newpage()` + `grid.draw()`); **encode** (`dev.off()`, which writes
the PNG). Today every case goes to the **ggplot2 tier**: the render path
declines `geom_raster()` and `geom_sf()`. So alot's current path is
`alot_build()` + 10 ms of decide + ggplot2's render.

### Baseline per stage (ms; medians of 3 reps, 1 rep for 2000² and the north stars)

| case | gg build | gg gtable | gg draw | gg encode | **gg total** | alot build | alot render | **alot total** | speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| raster_500 | 115 | 80 | 124 | 122 | **439** | 134 | 342 | **476** | 0.92× |
| raster_1000 | 609 | 319 | 135 | 246 | **1,310** | 158 | 709 | **873** | 1.50× |
| raster_2000 | 2,125 | 873 | 183 | 221 | **3,402** | 597 | 1,039 | **1,636** | 2.08× |
| sf_1e2_3577 | 181 | 66 | 803 | 116 | **1,163** | 179 | 1,003 | **1,181** | 0.98× |
| sf_1e3_3577 | 192 | 71 | 711 | 165 | **1,140** | 196 | 950 | **1,146** | 0.99× |
| sf_1e4_3577 | 320 | 128 | 751 | 292 | **1,485** | 321 | 1,167 | **1,488** | 1.00× |
| sf_1e2_4326 | 162 | 86 | 844 | 115 | **1,209** | 165 | 1,053 | **1,220** | 0.99× |
| sf_1e3_4326 | 179 | 71 | 726 | 168 | **1,140** | 181 | 964 | **1,145** | 1.00× |
| sf_1e4_4326 | 326 | 151 | 745 | 334 | **1,556** | 323 | 1,243 | **1,566** | 0.99× |
| sf_1e3_reproject | 978 | 94 | 726 | 164 | **1,965** | 970 | 996 | **1,966** | 1.00× |
| north_star | 2,346 | 912 | 725 | 190 | **4,173** | 809 | 1,621 | **2,430** | 1.72× |
| north_star_facet | 1,925 | 1,139 | 2,435 | 202 | **5,701** | 723 | 3,621 | **4,344** | 1.31× |

Single-rep stage splits move by up to about 100 ms, mostly because of
where garbage collection lands. ggplot2's build leaves more garbage than
alot's, so a collection often falls in ggplot2's gtable stage (e.g.
raster_2000's gtable: 873 vs 643 ms for the same ggplot2 code). Totals are
steadier.

### PROJ floor

The time with PROJ on the stack (`st_transform()`, `sf_project()`,
`st_graticule()`, `CPL_transform`) comes from one Rprof'd rep (10 ms
samples). All of it falls in the build:

| case | gg total | PROJ | share | best possible speedup |
|---|---:|---:|---:|---:|
| raster_* | 439–3,402 | 0 | 0% | — |
| sf_1e2/1e3/1e4_3577 | 1,140–1,485 | 110–170 | 10–12% | 8–10× |
| sf_1e2/1e3/1e4_4326 | 1,140–1,556 | 90–200 | 8–13% | 8–13× |
| sf_1e3_reproject | 1,965 | 900 | 47% | **2.2×** |
| north_star | 4,173 | 70 | 2% | 52× |
| north_star_facet | 5,701 | 60 | 1% | 102× |

Measured directly (median of 3): `st_transform()` of 1e6 vertices from
4326 to 3577 takes 440 ms. From 3577 to 3577 it takes 57 ms. `st_graticule()`
for the north star's panel takes 24 ms.

**The same-CRS transform is not free.** `CoordSf$setup_data` (ggplot2
R/coord-sf.R) calls `sf::st_transform()` on every sf layer whenever
`params$crs` is set, and it is set by default from the first sf layer's
CRS. `st_transform.sfc` always calls `CPL_transform` and then rebuilds the
sfc with `st_sfc()`, which recomputes the bbox and scans types and
emptiness. So a layer that is already in the coord's CRS still spends
100–200 ms of a 160–330 ms build (55–60% of it) in this step. That is
most of the "PROJ" figure for the in-CRS sf cases. For these synthetic
layers the result is `identical()` to the input, in both 3577 and 4326.

### Where the time goes

**Raster build** (ggplot2 2,125 ms → alot 597 ms at 2000²). ggplot2's time
is in scale mapping and training. The per-step table at 2.02e6 rows (3
builds, kernels off → on): `npscales_map` 502 → 246, `map_position_2`
453 → 179, `train_position_2` 201 → 91, `map_position_1` 151 → 25,
`train_position_1` 62 → 31. Each of these already has a kernel (T1.x,
T2.3). `compute_geom_1`, which is `GeomRaster$setup_data` (`resolution()`
on x and y plus the per-row xmin/xmax/ymin/ymax), takes 36 → 40 ms there.
On its own, `GeomRaster$setup_data` takes **19 ms at 1.01e6 rows**, 16 of
them in `resolution()` (vctrs `vec_unique()` and `sort()`). That is
about 1% of the 1e6-row raster's end-to-end time. What alot's raster
build still spends at 2e6 rows: `npscales_map` ~240 ms
(`rs_map_colour()`, which returns one hex string per row),
`map_position_2` 55–180 ms (six columns), `train_position_2` ~90–100 ms
(about 60 ms of R-side self time in `scales_train()`), and `as.integer()` on
the PANEL factor in `match_panel()` and the train/map wrappers (~25 ms).

**Raster render** (ggplot2 tier, 2000²). gtable takes 640–900 ms, which is
`GeomRaster$draw_panel`: `transform_position()`, the `nrow × ncol`
colour matrix, `t()`, `is.na()` and colour encoding. Draw takes 170–180
ms (`grid.newpage()` clears the 2100² page in 80 ms; ragg's
`drawRaster()` takes about 60). Encode takes 220 ms. S1.1 replaces all of
it.

**sf build** (160–330 ms in the data's CRS). `layout_setup` takes 55–65%
(the same-CRS `st_transform()` above). `setup_panel_params` takes 21–35 ms
(`st_graticule()`, mostly `CPL_crs_parameters`), and `compute_geom_2`
(`GeomSf$use_defaults`) takes 18 ms at 1e2 features and 60 ms at 1e4.
About half of the 60 ms is sf's `vec_restore()` re-building the sliced
sfc (`st_sfc()`: bbox, types) and about 10 ms is the per-feature
`st_geometry_type()` `vapply()`. `compute_geom_1` (`detect_sf_type()`,
again `st_geometry_type()`) takes 12 ms at 1e4 features, and
`compute_statistic` (`StatSf`, cached bbox; `detect_missing()`) takes 8–15
ms. alot's build equals ggplot2's here because nothing sf-specific has a
mirror or kernel yet (S0.1).

**sf render** (~1 s, flat in the feature count at 1e6 vertices). Draw
takes 710–850 ms, of which 470–670 ms is ragg filling and stroking the
paths (`grid.Call.graphics`) and 80 ms is `grid.newpage()`. gtable is
small: 66–150 ms for `sf_rescale01()`/`normalize_sfc()` and `st_as_grob()`
per feature. Encode takes 115–330 ms and grows with image complexity (1e4
filled features). SPATIAL.md's expectation that sf's O(vertices) work
happens at render time holds, but the time is in ragg's rasterisation,
not in R's grob building. This is the target for S3.2.

**North star** (ggplot2 4,173 ms). Build 2,346 ms (all raster scale work;
PROJ 70), gtable 912 ms (`GeomRaster$draw_panel` and sf grobs), draw 725
ms (ragg stroking 1e6 vertices: 560), encode 190 ms. The faceted variant
spends 2,435 ms drawing, because the outlines are stroked once per panel.

### Verdicts

**S1.2 (raster build kernels): drop as specified.** The candidate step,
`GeomRaster$setup_data` (`resolution()` and xmin/xmax/ymin/ymax), takes 19
ms at 1e6 rows: about 1% of ggplot2's end-to-end time (≈2.2 s) and 3–6%
of alot's raster build. A Rust `resolution()` would pass the per-step
1.25× rule easily, but would save about 15 ms at 1e6 rows. If S1.1's
drawer computes `resolution()` in Rust anyway, the build can reuse it then.
The raster build time that matters for the north star is overhead in
**existing** kernels at 2e6 rows (`npscales_map` ~240 ms,
`train_position_2` ~95, `map_position_1/2` ~80–200, PANEL `as.integer()`
~25). A performance pass on those (S4.1, or S1.2 re-scoped to it) is
where the north-star budget below is won or lost.

**S2.2 (sf build kernels): drop.** No sf build step is both large and
cuttable under SPATIAL.md's decisions. At 1e4 features (the "1e6 rows"
analogue, since sf build work is O(features) apart from PROJ), the
per-feature candidates are the geometry-type scans in `compute_geom_1`
(12 ms) and in `compute_geom_2` (~10 of its 60 ms), plus
`compute_statistic` (8–15 ms). That is about 2% of the 1,485 ms end to end.
The other half of `compute_geom_2` is sf's own sfc restore after
slicing, which a kernel can't avoid without rewriting the geometry
column. The dominant build step is `CoordSf$setup_data`'s
`st_transform()`, which stays in sf. **Open decision for S2.1:** skipping
that call when the layer's CRS equals `params$crs` (same `crs` object)
would remove 100–200 ms (8–13% end to end, 55–60% of the sf build) with
`identical()` output on these layers. It isn't a PROJ port, but it departs
from "call sf as ggplot2 calls it", so it needs sign-off and tests that
the sfc (coordinates, bbox, crs, classes) is unchanged.

**North-star target: ≥5× kept for both north-star cases. Revised for
reprojecting workloads.**

- `north_star`: ggplot2 takes 4,173 ms, so 5× means ≤ 835 ms. PROJ (70 ms) is
  not the constraint. alot's build alone takes 750–810 ms today. If S1.1/S3.2/S4.1
  bring the render to about 300 ms (the R7.2 page at 2100² with 1e6
  points draws in 190 ms), the total is about 1.1 s, or **≈3.8×**. 5× also
  needs alot's raster build cut to ≈500 ms, through the existing-kernel overheads
  listed under S1.2. The target stays, with that build budget made
  explicit for S4.1.
- `north_star_facet`: ggplot2 takes 5,701 ms, so 5× means ≤ 1,140 ms. alot's build
  takes about 720 ms, leaving about 400 ms for four panels of raster and 4e6
  stroked vertices. That is reachable with the band-parallel drawer.
- `sf_1e3_reproject`, and any sf workload whose layer CRS differs from the
  coord's: `st_transform()` is 47% of ggplot2's time, so the ceiling is
  2.2×. **Target ≥1.6×** (render ≈5× faster, build unchanged).
- sf-only in the layer's own CRS (`sf_*_3577`, `sf_*_4326`): the build
  (160–330 ms, mostly the same-CRS `st_transform()`) stays in R with S2.2
  dropped. With a render around 150 ms, the best case is ≈3–3.5×. **Target
  ≥3×.** It becomes ≥5× only if the same-CRS skip above is adopted.
- Raster-only: no PROJ. raster_2000 is 3,402 → 597 ms build today plus
  the S1.1 render; ≥5× (≤ 680 ms) again depends on the build overheads.
  SPATIAL.md doesn't set a raster-only end-to-end target; S1.1 keeps its
  draw-step target.

## S1.1: geom_raster() drawer (2026-11-01)

`inst/bench/spatial.R` (`ALOT_BENCH_CASES=raster_500,raster_1000,raster_2000
ALOT_BENCH_PROFILE=false`; raster_2000 rerun with `ALOT_BENCH_REPS=3`),
release build, same machine and page (7 × 7 in at 300 dpi) as S0.2. The
raster cases now go to the **full tier**. `run_alot()` times the tier
`alot_png()` picks: for the full tier "decide" is `render_ir()` +
`page_spec()`, "draw" is `rs_render_page()` (layout, display list,
building the colour matrix, band rasterising into a nativeRaster) and
"encode" is `write_png()`. The new hybrid path (`run_hybrid()`,
`options(alot.full_tier = FALSE)`) times `hybrid_gtable()`, grid drawing
(the raster as a lazy Rust grob) and capture + `write_png()`. Medians of 3
interleaved reps, ms:

| case | stage | ggplot2 + ragg | hybrid | full |
|---|---|---:|---:|---:|
| raster_500 | build | 102 | 58 | 58 |
| | gtable / decide | 86 | 57 | 21 |
| | draw | 126 | 44 | **20** |
| | encode | 122 | 27 | 17 |
| | **total** | **437** | 186 | **118** (3.7×) |
| raster_1000 | build | 677 | 149 | 139 |
| | gtable / decide | 376 | 54 | 22 |
| | draw | 135 | 52 | **14** (9.6×) |
| | encode | 247 | 22 | 19 |
| | **total** | **1,420** | 280 | **193** (7.4×) |
| raster_2000 | build | 1,938 | 467 | 479 |
| | gtable / decide | 836 | 63 | 29 |
| | draw | 170 | 65 | **29** (5.9×) |
| | encode | 217 | 24 | 22 |
| | **total** | **3,031** | 620 | **552** (5.5×) |

A single-rep run of raster_2000 gave draw 20 ms (8.5×) and total 555 ms.
**Targets met:** 1000² and 2000² draw faster than ragg, and the 2000²
draw step is ≥5× faster than ragg's (5.9–8.5×). The margin over 5× is
mostly not raster work. Timed inside `rs_render_page()` at 2000², reading
the spec and building the display list, including the 2.0e6-row colour
matrix, takes about 3.5 ms. Rasterising the page takes about 6 ms. The
2100² nativeRaster R allocates for the result takes 1–14 ms, because
garbage collection often lands there. `alot_png()` streams the bands to
the PNG (`rs_render_page_png()`) and allocates no nativeRaster:
`render_full(file)` takes 88–94 ms for the whole render at 2000²
(decide + draw + encode, plus `render_full()`'s missing-row check).

Where the matrix time went: building it took 18–28 ms at first (two
`resolution()` hash passes, sequential min/max, fresh 16 MB buffers). The
current version takes about 8 ms in Rust. It uses one parallel pass for
both columns' ranges and distinct values, computes the matrix size from
the range (the position mapping is monotone), and reuses the matrix and
cell-index buffers from a pool, because a fresh buffer's page faults cost
more than filling it. The scatter stays sequential, so a later row wins a
shared cell as in R. R's `resolution()` on x and y alone takes 80 ms at
2e6 rows, which is why it is ported (checked against upstream through the
render tests, including integer, uneven and shared positions). The
decide stage includes `rs_raster_check()` (finite positions, colours that
parse, alpha 0 or 1): about 7 ms at 2e6 rows.

The end-to-end raster_2000 total is now 5.5×, with alot's build (≈480 ms)
as 87% of it. The build overheads listed under S0.2's verdict for S1.2
are the next lever.


## S2.1: sf build mirrors and the same-CRS skip (2026-11-01)

Release build, same machine as S0.2. Build only (`ggplot_build()` vs
`alot_build()`), medians of 5 interleaved reps, on S0.2's `sf_regions()`
layers (1e6 vertices) with `geom_sf(aes(fill = value), colour = "grey20")`
and the default `coord_sf()`. `layout_setup` is one `step_times()` run
with kernels off (ggplot2's `CoordSf$setup_data`, i.e. `st_transform()`)
and on (the mirror, which skips it):

| case | gg build | alot build | speedup | layout_setup off → on |
|---|---:|---:|---:|---:|
| sf_1e2_3577 | 190 | 86 | 2.21× | 132 → 10 |
| sf_1e4_3577 | 338 | 160 | 2.11× | 383 → 15 |
| sf_1e2_4326 | 172 | 69 | 2.49× | 123 → 7 |
| sf_1e4_4326 | 336 | 197 | 1.71× | 213 → 22 |

What is left of `layout_setup` is `rs_sfc_plain_xy()` (the walk that
proves the skip exact, about 2 ms at 1e6 vertices) and sf's `[<-.sf`,
which the mirror keeps as upstream has it. Layers in another CRS still
call `st_transform()`, so `sf_1e3_reproject` is unchanged.
