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
