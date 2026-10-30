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
