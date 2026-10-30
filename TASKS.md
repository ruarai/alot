# alot — sub-tasks

Breaks [PLAN.md](PLAN.md) (Phase 1) and [PHASE2.md](PHASE2.md) (Phase 2,
from "Phase 2: rendering" below) into tasks of about one PR each. IDs follow
the plans' milestones. Each task lists what it depends on, the files it touches,
and when it is done.

**Status:** a task with no marker is not started. When a task's commit lands,
append `— done` to its heading, or `— dropped (see RESULTS.md)` if the kernel
failed the 1.25× rule.

## Run order

Work through this queue in order, one task at a time (a range such as
R1.2–R1.5 means each in turn), skipping tasks marked done. Tasks marked
deferred (in their heading or their section's) or "ignore for later" are not
in it. Each task still follows its own entry and its phase's shared
criteria.

1. **Phase 1:** T0.7 → T5.4 → T5.5 → T6.2 → T6.1, then any tasks T6.1
   opens, in the order it lists them.
2. **Phase 2:** in "Suggested order (Phase 2)": R0.1, R0.2 → R0.3, R0.4 →
   R1.1 → R1.2–R1.5 → R2.1, R3.1 → R3.2, R2.2, R4.1 → R4.2 → R5.1 → R5.2 →
   R5.3 → R6.1–R6.6 → R7.1 → R7.2 → R7.3.

## Phase 1 completion criteria

Every Phase 1 task that adds a kernel shares these completion criteria, so they are
not repeated below:

- **Equivalence:** targeted `expect_build_equal()` tests cover the kernel's
  parameter space, including NA, empty, single-row, and integer vs double
  inputs. The corpus (T0.5) still passes.
- **Fallback:** unsupported params, subclasses and input types return `NULL`,
  with a test showing that `alot_coverage()` reports `"ggplot2"` for each.
- **Coverage:** `alot_coverage()` reports `"rust"` for the supported case.
- **Speed (1.25× rule):** the step is at least 1.25× faster at 1e6 rows in the
  bench suite (T0.6). If not, delete the kernel and record why in
  `inst/bench/RESULTS.md`.
- **Drift:** each newly mirrored ggproto method gets a body snapshot in
  `test-internals.R`.
- **Rust:** algorithms live in `alot-core` with `cargo test` unit tests. Only
  conversion code goes in `alot-r`.

---

## 1.0 Infrastructure

### T0.1 Full rextendr scaffold — done
- **Depends:** —
- **Touches:** `configure`, `configure.win`, `tools/config.R`,
  `tools/msrv.R`, `src/Makevars.in`, `src/Makevars.win.in`, `src/rust/`,
  `R/extendr-wrappers.R`, `.Rbuildignore`
- **Do:** Generate the scaffold with `rextendr::use_extendr()` in a scratch
  copy and port it into the repo. Keep the two-crate workspace and build with
  `-p alot-r`. Add the `document` binary so `rextendr::document()`
  regenerates the wrappers. Set `SystemRequirements` and the MSRV check.
- **Done when:** `R CMD INSTALL .` works from a clean checkout,
  `rextendr::document()` regenerates `R/extendr-wrappers.R` without a diff,
  and the existing tests pass.

### T0.2 Vendoring for offline / CRAN builds - (ignore for later)
- **Depends:** T0.1
- **Touches:** `src/rust/vendor.tar.xz`, `src/rust/vendor-config.toml`,
  `inst/AUTHORS`, `LICENSE.note`, `tools/config.R`
- **Do:** Run `rextendr::vendor_pkgs()` and make the build use the vendored
  crates when `NOT_CRAN` is unset. List vendored crate authors and licences.
- **Done when:** `R CMD build` followed by `R CMD check --as-cran` with
  networking disabled passes, with no NOTE about crate licences.

### T0.3 Data interchange layer — done
- **Depends:** T0.1
- **Touches:** `alot-r/src/convert.rs` (new), `R/convert.R` (new),
  `tests/testthat/test-convert.R`
- **Do:**
  - Borrowed column views: `&[f64]`, `&[i32]` (`NA_integer_` becomes
    `None`), and logical.
  - A factor type made of codes plus a levels `Strings`. Strings stay as
    `Strings`.
  - A builder that returns a named list of columns.
  - R helper `rebuild_frame(cols, template)`: `data_frame0()` in the
    template's column order, then `merge_attrs()`.
- **Done when:** round-trip tests pass for every column type ggplot2 layer
  data uses (`double`, `integer`, `logical`, `character`, `factor`,
  `mapped_discrete`, `Date`, `POSIXct`, and list columns passed through
  untouched). Benchmarks show no copy for numeric columns.

### T0.4 Grouped-kernel driver — done
- **Depends:** T0.3
- **Touches:** `alot-core/src/group.rs` (new), `alot-r/src/lib.rs`,
  `R/grouped.R` (new)
- **Do:**
  - Build a group index over `PANEL` × `group` in one pass: offsets plus a
    row permutation, ordered as `dapply`/`split` would order them.
  - Write a generic `run_grouped(kernel, columns, index)` in `alot-core` that
    concatenates per-group outputs and carries the constant columns through,
    as `Stat$compute_panel` does with `uniquecols`.
  - Add an R wrapper used by stat and position kernels.
- **Done when:** a trivial identity-style kernel passed through the driver
  reproduces `Stat$compute_layer` output (rows, order, constant columns) for
  multi-panel, multi-group data, including groups with `group = -1`. A test
  pins the ordering against `dapply`.

### T0.5 Corpus harness — done
- **Depends:** —
- **Touches:** `tests/testthat/test-corpus.R`, `tools/extract-corpus.R`
  (new), `tests/testthat/corpus/` (generated), `tests/testthat/corpus-allow.R`
- **Do:** Write a script that parses `../ggplot2/man/*.Rd` examples and
  `../ggplot2/tests/testthat/*.R`. It keeps every expression that evaluates
  to a ggplot (with its setup code) and writes them out as corpus files. The
  test runs `expect_build_equal()` on each. Keep an allow-list with a reason
  per entry (missing package, intentionally errors, …). Skip on CRAN.
- **Done when:** the corpus runs green against the current build mirror and
  the count of plots run vs allow-listed is printed. Regenerating the corpus
  is a single command.

### T0.6 Benchmark suites — done
- **Depends:** —
- **Touches:** `inst/bench/row-scaling.R`, `inst/bench/facet-scaling.R`,
  `inst/bench/step-profile.R`, `inst/bench/RESULTS.md`
- **Do:**
  - Row-scaling suite: the eight plots in PLAN.md at 1e4, 1e6 and 1e7 rows.
  - Facet-scaling suite: the four many-facet plots at 25, 100, 400 and 1,600
    panels with 200 rows per panel.
  - Per-step timing: wrap `alot_build` steps with timers behind an option, or
    use `Rprof` aggregation, so each kernel's 1.25× check measures its own step.
  - Record the baseline numbers (ggplot2 vs current alot) in `RESULTS.md`
    with machine, R and ggplot2 versions.
- **Done when:** one command per suite reproduces the tables in
  `RESULTS.md`.

### T0.7 Warning and message parity
- **Depends:** —
- **Touches:** `tests/testthat/test-warnings.R`, `helper-equivalence.R`
- **Do:** Extend `expect_build_equal()` (or add `expect_build_conditions_equal()`)
  so it captures warnings and messages from both builds and compares them.
  Add `expect_snapshot` cases for "Removed n rows", stat_bin's default-bins
  message, and so on.
- **Done when:** the corpus also checks condition parity.

---

## 1.1 Position scales

### T1.1 Discrete position training — done
- **Depends:** T0.3
- **Touches:** `R/kernels-scale.R`, `alot-core/src/scale/discrete.rs` (new),
  `alot-r/src/lib.rs`, `tests/testthat/test-scale-train.R`
- **Do:**
  - For `ScaleDiscretePosition` with a `DiscreteRange`, Rust returns the
    distinct values per scale id in O(n), from factor codes, strings or
    logicals.
  - R merges them with the existing range the way `scales:::discrete_range`
    does: `sort()` stays in R, `drop`/`na.rm` are respected, and factor level
    order is kept.
  - Also cover `range_c`, the continuous range for continuous values plotted
    on a discrete scale.
- **Done when:** the shared criteria hold, including mixed factor and
  character input across layers and locale-sensitive strings.

### T1.2 `layout$map_position` mirror and kernels — done
- **Depends:** T0.3, T1.1
- **Touches:** `R/layout.R`, `R/build.R`, `R/kernels-scale.R`,
  `alot-core/src/scale/map.rs` (new)
- **Do:**
  - Mirror `Layout$map_position` and `scale_apply(method = "map")`, routing
    through `dispatch("scale_map", …)`.
  - Continuous kernel: `oob` (`censor`, `squish`, `squish_infinite`,
    `keep`), then `na.value`. Any other `oob` function falls back.
  - Discrete kernel: map to integer positions through the limits and tag the
    result `mapped_discrete`. Continuous input on a discrete scale passes
    through as ggplot2 does.
- **Done when:** the shared criteria hold, including `mapped_discrete` class
  preservation and NA handling. Benchmark target: the `map_position` share
  of the discrete `geom_point` case.

### T1.3 `scales$transform_df` kernels — done
- **Depends:** T0.3
- **Touches:** `R/build.R`, `R/kernels-scale.R`,
  `alot-core/src/scale/transform.rs` (new)
- **Do:** Mirror `ScalesList$transform_df` with a per-scale dispatch. Add
  kernels for the `identity`, `log10`, `sqrt` and `reverse` transforms,
  identified by `transform$name`. Any other transform falls back.
- **Done when:** the shared criteria hold. A dedicated test checks that
  Rust's `log10`/`sqrt` match R's bitwise on a dense grid including
  subnormals, 0, negatives and ±Inf, and that the `NaN produced` warning
  still appears.

---

## 1.2 Non-position scales

### T2.1 Mirror `npscales$train_df` / `map_df` — done
- **Depends:** —
- **Touches:** `R/build.R`, `R/npscales.R` (new)
- **Do:** Mirror `ScalesList$train_df` and `ScalesList$map_df` with
  per-scale `dispatch("np_train", …)` / `dispatch("np_map", …)`. No kernels
  yet; everything falls back.
- **Done when:** the corpus passes and `alot_coverage()` lists the
  non-position scale steps.

### T2.2 farver-exact colour encoding — done
- **Depends:** —
- **Touches:** `alot-core/src/colour/` (new: `lab.rs`, `hex.rs`)
- **Do:** Port farver's sRGB↔XYZ↔Lab conversions, white point and rounding
  and its hex encoding (including alpha) to Rust.
- **Done when:** the hex strings are byte-identical to
  `farver::encode_colour(farver::convert_colour(...))` on a dense Lab grid
  and on random inputs (an R test calling the Rust function), and NA gives NA.

### T2.3 Continuous colour/fill mapping — done
- **Depends:** T2.1, T2.2, T0.3
- **Touches:** `R/kernels-npscale.R` (new), `alot-core/src/colour/ramp.rs`
- **Do:**
  - Train with the continuous range kernel.
  - Map: `rescale`, then a Rust `colour_ramp` interpolation over a palette
    whose colours R samples (O(k)). Then `oob` and `na.value`.
  - Support the gradient, gradient2 (`rescale_mid`), gradientn, distiller and viridis
    scales. Detect them by the scale's palette and rescaler and fall back for
    anything custom.
- **Done when:** the shared criteria hold. Benchmark target: the `map_df`
  share of the continuous-colour `geom_point` case.

### T2.4 Discrete non-position mapping — done
- **Depends:** T2.1, T0.3
- **Touches:** `R/kernels-npscale.R`, `alot-core/src/scale/discrete.rs`
- **Do:**
  - Training reuses T1.1.
  - Map: R computes the palette for the limits (O(k)), handling named
    `values` in manual scales and `na.translate`. Rust looks each row up by
    hash in a single pass.
  - Cover the hue, brewer, manual, shape and linetype scales. The output type
    must match: character for colours, integer or character for shapes.
- **Done when:** the shared criteria hold.

### T2.5 Size, alpha and linewidth scales (deferred)
- **Depends:** T2.1, T0.3
- **Touches:** `R/kernels-npscale.R`, `alot-core/src/scale/map.rs`
- **Do:** Add `rescale` with `area_pal` / `rescale_pal` for continuous size,
  alpha and linewidth. `scale_radius` and `scale_size_area` go through the
  same path when their palettes are recognised.
- **Done when:** the shared criteria hold.

### T2.6 Binned non-position scales (deferred)
- **Depends:** T2.3–T2.5
- **Do:** Only after the rest of 1.2 is done and the profile shows they
  matter. Until then they fall back, as T2.1 already ensures.

---

## 1.3 Stats (all deferred)

All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

### T3.1 `StatIdentity` short-circuit
- **Depends:** T0.4
- **Do:** Return the data unchanged without splitting it. Check that
  ggplot2's `compute_layer` would not alter row order or attributes.

### T3.2 `StatCount`, `StatSum` and `StatUnique`
- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/count.rs`, `R/kernels-stat.R` (new)
- **Do:** Hash-based counting. Match ggplot2's output order exactly
  (`StatCount` sorts by x; `StatSum` and `StatUnique` follow `count()` /
  `unique()` semantics), along with `weight`, `width`, `flipped_aes` and the
  computed `prop`.

### T3.3 Binning core and `StatBin`
- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/bin.rs`, `R/kernels-stat.R`
- **Do:**
  - Breaks stay in R: `compute_bins()` is O(bins) and runs once per layer.
    Pass the breaks and `closed` to Rust.
  - Port the 1e-8 fuzz and `bin_cut` assignment exactly.
  - Rust computes `count`, `density`, `ncount`, `ndensity`, `width` and
    `pad`, handling `weight`, NA and Inf.
  - Also handle the `breaks`, `boundary`, `center`, `bins` and `binwidth`
    paths (all decided in R).
- **Done when:** the shared criteria hold, with a property test of random data
  and bin params against ggplot2 that includes values exactly on bin edges.

### T3.4 `StatDensity` and `StatYdensity`
- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/density.rs`
- **Do:**
  - Port `stats::density.default`: linear binning (`BinDist`), FFT
    convolution and `approx` onto `n` points.
  - Compute bandwidths `nrd0` and `nrd` in Rust. R computes any other
    bandwidth per group and passes it in, and those plots fall back until
    this is done.
  - Support the kernels R supports and `bounds` reflection.
  - For `StatYdensity`, add `scale`, `trim`, `drop` and `quantiles`.
- **Done when:** the shared criteria hold. FFT round-off (rustfft vs R's
  `fft`) stays within 1e-8 on the bench data.

### T3.5 `StatBoxplot`
- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/boxplot.rs`
- **Do:** Port `quantile(type = 7)` exactly, `coef` outliers (returned as a
  list column), `notch`, `relvarwidth`, `width` and `flipped_aes`.

### T3.6 `StatSummary`: `mean_se` and `median_hilow`
- **Depends:** T0.4
- **Do:** Identify `fun.data` by identity with
  `ggplot2::mean_se`/`median_hilow`. Reproduce R's two-pass long-double
  `mean()`; `f128`/`twofloat` emulation may be needed, so check whether
  `f64` already stays within 1e-8. Any other `fun` falls back.

### T3.7 `StatEcdf`, `StatBin2d` and `StatSummary2d`
- **Depends:** T3.3
- **Do:** Reuse the T3.3 binning core. `StatSummary2d` gets kernels only for
  `fun = mean` and `fun = sum`.

### T3.8 `StatSmooth` (`method = "lm"`)
- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/lm.rs`
- **Do:**
  - Householder QR least squares matching `lm.fit` (LINPACK `dqrdc2` pivoting
    tolerance), then prediction on `xseq` and standard errors.
  - R computes the `qt()` quantile and passes it in.
  - Support the formulas `y ~ x` and `y ~ poly(x, k)`; `poly` basis
    generation stays in R and Rust receives the design matrix. Anything else
    falls back.
- **Done when:** the shared criteria hold. The 1.25× rule applies to the stat
  step only.

---

## 1.4 Positions (all deferred)

### T4.1 `PositionStack` and `PositionFill`
- **Depends:** T0.4
- **Touches:** `alot-core/src/position/stack.rs`, `R/kernels-position.R`
  (new)
- **Do:** Port `collide` (grouping by `xmin`, ordering by `group`,
  `reverse`) and `pos_stack` / `pos_fill`: `vjust`, separate stacking of
  negative values, and NA handling. Support `ymax`-only and `y`-only data.
- **Done when:** the shared criteria hold. The 400-panel histogram benchmark
  shows the `collide` share gone.

### T4.2 `PositionDodge` and `PositionDodge2`
- **Depends:** T0.4
- **Do:** Implement `n`, `width`, `padding`, `preserve = "single"/"total"`,
  `reverse`, and the `order` aesthetic in 4.0.

### T4.3 Measure jitter and nudge
- **Depends:** T0.6
- **Do:** Profile both at 1e6 rows. If jitter clears the 1.25× rule, add a
  kernel that takes the `runif` draws from R (under `with_seed_null`) and does
  only the arithmetic in Rust. Otherwise record "no kernel" in `RESULTS.md`.

---

## 1.5 Facets and layout setup

### T5.1 Panel assignment for `layout$setup` / `map_data` — done
- **Depends:** T0.3
- **Touches:** `R/layout.R`, `R/kernels-facet.R` (new),
  `alot-core/src/facet/join.rs`
- **Do:**
  - Mirror `Layout$setup` and dispatch `facet$map_data` for `FacetWrap` and
    `FacetGrid`.
  - Rust hash-joins rows to layout rows on the facet variables. R evaluates
    the facet expressions and handles `margins`, missing facet variables and
    expansion across panels.
  - Fall back for `margins = TRUE` at first.
- **Done when:** the shared criteria hold. Benchmark target: the 19%
  `layout$setup` share of `facet_wrap` + point.

### T5.2 Batched `labeling::extended` in Rust — done
- **Depends:** —
- **Touches:** `alot-core/src/breaks/extended.rs`
- **Do:** Port `labeling::extended` with the same floating-point operation
  order and the default `Q`, `w` and `only.loose` settings. The batched
  entry point takes many `(dmin, dmax, m)` triples.
- **Done when:** outputs are identical to `labeling::extended` on about 1e5
  random ranges, including degenerate, tiny, huge and negative ranges.

### T5.3 Mirror `setup_panel_params` and deduplicate per axis — done
- **Depends:** T5.2
- **Touches:** `R/layout.R`, `R/panel-params.R` (new)
- **Do:**
  - Mirror `Layout$setup_panel_params` and
    `CoordCartesian$setup_panel_params` (also covering `CoordFlip` and
    `CoordFixed`).
  - Build view scales once per distinct `SCALE_X` and `SCALE_Y`, using the
    batched breaks from T5.2 for major and minor breaks. Compute labels in R
    once per distinct break set.
  - Assemble per-panel params as clones.
  - Read ggproto methods and fields once per scale class.
  - Dispatch on coord class; any other coord falls back.
- **Done when:** `panel_params` are equal field by field (the existing
  harness check), including view-scale ggproto objects. Mutating one panel's
  objects does not affect another (test). The free-scale facet benchmarks
  improve.

### T5.4 Mirror `setup_panel_guides` and deduplicate per axis
- **Depends:** T5.3
- **Do:** Mirror `Layout$setup_panel_guides` and build axis guides once per
  distinct x and y scale, then clone them per panel. Fall back for non-axis
  position guides and custom guides.
- **Done when:** the guides in `layout$panel_params` are equal, and both the
  `facet_wrap` and the 20×20 `facet_grid` free cases are at least 2× faster.

### T5.5 Facet-scaling verification
- **Depends:** T5.1, T5.3, T5.4
- **Do:** Run the facet-scaling suite and confirm the free-scale cases are
  at least 2× faster at 400 panels and the fixed-scale control is no slower.
  Confirm that cost grows linearly from 100 to 1,600 panels. Fix any
  per-panel overhead that remains. The histogram case (at least 5× faster)
  waits for the deferred T3.3 and T4.1; record its current numbers but
  don't treat them as a target.
- **Done when:** the point cases meet the targets above, recorded in
  `RESULTS.md`.

---

## 1.6 Remaining per-row steps

### T6.1 Re-profile and pick targets
- **Depends:** T6.2 and the non-deferred 1.1–1.5 kernels
- **Do:** Profile the bench suites with kernels in place. List
  `compute_geom_1`, `compute_geom_2`, `finish_statistics`,
  `layout$finish_data` and `.ignore_data`/`.expose_data` by share of build
  time. Open one task per step that could plausibly pass the 1.25× rule
  (as `T6.3`, `T6.4`, …, under 1.6, listed in the run order), and record
  the rest as "stays in R".
- **Done when:** the ranked list is in `RESULTS.md`, and any new tasks are
  in this file and in the run order.

### T6.2 Overhead around the position scale kernels
- **Depends:** T1.1, T1.2
- **Touches:** `R/kernels-scale.R`, `R/layout.R`, `R/convert.R`
- **Do:**
  - On the README example plot (1e6 rows, `facet_wrap`, log x, continuous
    colour, discrete shape), the position train and map steps take about
    100 ms (45% of the build, 2026-10-30). That is with kernels on:
    `train_position_1/_2` 28 + 27 ms and `map_position_1/_2` 24 + 21 ms.
  - Profile these steps (e.g. `Rprof` or `profvis` around
    `alot:::step_times(p)`). Split the time into Rust compute and the R work
    around each call: column conversion, per-panel and per-scale splitting,
    `rebuild_frame()` and any copies.
  - Remove the overhead that profiling finds, e.g. by converting each
    column once per step instead of once per scale or panel.
- **Done when:** the profile split is recorded in `RESULTS.md`, and any
  change keeps the shared criteria and makes these steps faster on the
  example plot.

---

## Phase 1 exit

### T7.1 Exit checklist (deferred)
- **Depends:** everything above, including the deferred stats, positions and
  T0.2
- **Do:** Verify each criterion in "Phase 1 is done when" in PLAN.md:
  - the corpus is green and the allow-list is documented;
  - coverage shows Rust for every component in 1.1–1.5 on representative
    plots;
  - `RESULTS.md` meets the row-scaling and facet-scaling targets;
  - `R CMD check --as-cran` with vendored crates and `cargo test` both pass.

## Suggested order

1. T0.1 → T0.2, alongside T0.5, T0.6 and T0.7. Baselines and the regression
   net come first.
2. T0.3 → T0.4.
3. T1.1 → T1.2, then T1.3 (largest share for point plots).
4. T3.3, T4.1 and T5.1 (they unlock the histogram and facet benchmarks).
5. T5.2 → T5.3 → T5.4.
6. T2.1 → T2.2 → T2.3–T2.5.
7. The remaining stats and positions, then T5.5, T6.1 and T7.1.

---

# Phase 2: rendering

Phase 2 tasks use IDs `R<milestone>.<n>`, with branches named as before
(`task/R1.2-point-batches`). [PHASE2.md](PHASE2.md) has the scope, what the
prototype (`proto/phase2-points`) showed, the architecture (full, hybrid and
ggplot2 tiers; IR; layout; one page display list; banded raster backend)
and the performance targets. Phase 2 only needs a built plot, so it runs
alongside Phase 1's remaining tasks.

## Shared completion criteria (Phase 2)

- **Visual equivalence with ggplot2 + ragg** at the same size and dpi,
  checked with `expect_render_close()` (R0.2) at PHASE2.md's tolerance. Any
  looser case is documented in the test, with the reason.
- **Layout:** boxes within 0.5 px of grid's (R0.2 layout export), for tasks
  that place things.
- **Both tiers:** each drawer works in the full tier's page list and as a
  lazy grob in the hybrid tier, with tests for both.
- **Fallback:** anything unsupported is reported by
  `alot_render_coverage()` and drops to the next tier, with a test per case.
  Tests of supported cases also check that no fallback warning was raised
  (an internal error would otherwise pass as a fallback).
- **Speed:** each task's benchmark case in `inst/bench/render-*.R` is
  recorded in `RESULTS.md`. No drawer may be slower than ragg drawing the
  same marks.
- **Rust:** algorithms live in `alot-core` with `cargo test` unit tests,
  including geometry checks against measured ragg output. Only conversion
  code goes in `alot-r`.
- Each mirrored function cites its ggplot2, ragg or R source. Each newly
  mirrored ggproto method (a geom's `draw_panel`, a facet's `draw_panels`,
  a guide's drawing) gets a body snapshot in `test-internals.R`.

## R0 Foundations

### R0.1 Land the hybrid tier — done
- **Depends:** —
- **Touches:** `R/render.R`, `alot-core/src/render/{points,png}.rs`,
  `alot-r/src/render.rs`, `tests/testthat/test-render.R`, `DESCRIPTION`,
  `AGENTS.md`
- **Do:** Rebase the prototype (`proto/phase2-points`) onto `main` as the
  hybrid tier. Rename internals to match the layout above. Add
  `alot_render_coverage()` (tier, plus per layer "rust" or "ggplot2" with a
  reason). Make `alot_png()` signal which tier ran. Keep the prototype's
  fallbacks (shapes, NA, coord, `clip`, device). Catch internal errors: warn
  once with the error and render with ggplot2. Move ragg to Imports as
  `ragg (>= 1.5.0, < 1.6.0)`, and add the ragg pin to AGENTS.md next to the
  ggplot2 pin.
- **Done when:** the README plot renders via the hybrid tier at the
  prototype's speed, and every fallback in `test-render.R` is reported by
  `alot_render_coverage()`.

### R0.2 Fidelity and layout harness — done
- **Depends:** —
- **Touches:** `tests/testthat/helper-render.R`, `tools/render-corpus.R`,
  `tests/testthat/test-render-corpus.R`, `.Rbuildignore`
- **Do:**
  - `expect_render_close(p, ..., max = 32, share = 0.01, tier = "full")`
    draws `p` live with ggplot2 + `agg_capture()` and with alot in the given
    tier, and compares pixels. It fails if alot raised a fallback warning
    or used a different tier. On failure it writes reference, result and
    diff images to a temp directory and prints the path. No reference
    images are stored.
  - A layout export: walk the gtable on a ragg device and record each
    named grob's box in device pixels via `deviceLoc()`. Compare it with
    the Rust layout's debug export (used from R4.1).
  - A render corpus: a subset of the Phase 1 corpus within PHASE2.md's
    scope, drawn at a small size so live references stay fast, and
    filtered by `ALOT_RENDER_CORPUS` like `ALOT_CORPUS`.
  - Fetch the ragg 1.5.2 and R sources to `../ragg` and `../r-source`, and
    note them in AGENTS.md.
- **Done when:** the harness runs on the hybrid tier over the render corpus.
  Plots whose layers the hybrid supports pass; the rest are reported as
  fallbacks.

### R0.3 Render benchmarks — done
- **Depends:** R0.1
- **Touches:** `inst/bench/render-*.R`, `inst/bench/RESULTS.md`
- **Do:** Generalise the prototype's `render-readme.R` into a suite. It
  times each stage (build, IR, layout, raster, encode; or gtable and draw
  for ggplot2 and the hybrid), with interleaved runs, for these cases:
  - the README plot at 1600 × 1000 and 150 dpi, and at the default page
    (7 × 7 in, 300 dpi);
  - the README plot with 10 rows (fixed cost);
  - 1e6-row `geom_point`, no axes;
  - a 1000 × 1000 `geom_tile`;
  - a 1e6-point `geom_line`;
  - 400 small facet panels.
- **Done when:** baselines for ggplot2 + ragg and the hybrid are in
  `RESULTS.md`, and PHASE2.md has a target for the default page.

### R0.4 API: `alot_png()` and `alot_ggsave()` — done
- **Depends:** R0.1
- **Touches:** `R/render.R`, `R/ggsave.R`, `tests/testthat/test-render.R`
- **Do:**
  - Give `alot_png()` `ggsave()`'s names and defaults (`width = 7`,
    `height = 7`, `units`, `dpi = 300`, `bg`, `scaling`), as in PHASE2.md's
    User API.
  - Add `alot_ggsave()` with `ggplot2::ggsave()`'s signature (mirror
    ggplot2 R/save.R for sizes and units). `.png` files go through
    `alot_png()`; anything else is passed to `ggsave()` unchanged.
- **Done when:** `alot_ggsave()` gives the same file size, dimensions and
  `pHYs` as `ggsave(device = ragg::agg_png)` for PNGs, passes other formats
  through, and both functions are documented.

## R1 Raster engine (milestone 2.0)

### R1.1 Display list and band executor — done
- **Depends:** R0.1
- **Touches:** `alot-core/src/render/{display,raster}.rs`
- **Do:**
  - Define the display-list items and clip stack in device pixels.
  - Build the executor: split the page into row bands, each with an f32
    premultiplied buffer reused across calls, so memory is bounded by band
    size. Each band walks the list in order, skipping items by y extent.
    Finished bands are handed over in row order for encoding (R1.5).
  - Set the thread count from `options(alot.threads)` or `ALOT_THREADS`,
    defaulting to the available cores capped at 8, and at 2 when
    `_R_CHECK_LIMIT_CORES_` is set.
  - Mirror ragg's clipping (`clip_box` at fractional panel edges) and
    background fill.
  - Move the prototype's point drawer onto it, so the hybrid's per-panel
    raster is a one-item display list.
- **Done when:** a background plus a 1e6-point batch renders, matching the
  hybrid's pixels, and the blend scales with threads (record 1 vs 8). A
  20 × 20 in page at 300 dpi renders within a memory bound set by the band
  size.

### R1.2 Point batches: all shapes — done
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/points.rs`
- **Do:**
  - Cover pch 0–25 per `GESymbol()` as drawn by ragg: outlines, fills,
    fill + outline for 21–25 with `fill` and `stroke`, the diamond and
    star shapes, and 7–14's compound symbols.
  - Handle character pch and `"."` too, or decline them.
  - Place points in parallel, with sprite lookups that avoid per-point
    hashing.
  - Build sprites lazily, per offset actually used, so size-mapped plots
    with many distinct sizes stay cheap.
- **Done when:** every shape passes `expect_render_close()` at several
  sizes, strokes, alphas and dpis, and a plot mapping `size` to 1e4
  distinct values is no slower than ragg.

### R1.3 Rect batches — done
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/rects.rs`
- **Do:** Draw axis-aligned rects: fill-only with ragg's `snap_rect`
  rounding, and with outlines through the path drawer (R1.4). This is the
  drawer for bars, tiles, raster-like tiles, panel backgrounds and legend
  keys.
- **Done when:** a 1000 × 1000 `geom_tile` matches ragg and draws in under a
  tenth of ragg's time.

### R1.4 Paths: strokes, fills and line types — done
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/paths.rs`
- **Do:**
  - Compare an exact-area AA scanline rasteriser (AGG-style cell
    accumulation) with tiny-skia, measuring fidelity against ragg and speed
    on 1e6-segment lines. Pick one and record why in `RESULTS.md`.
  - Implement stroking with lwd, `lineend`, `linejoin`, `linemitre` and R's
    `lty` dash patterns (named and hex), plus nonzero and even-odd fills.
- **Done when:** lines, polygons and dashes at several lwds pass
  `expect_render_close()`, and a 1e6-point `geom_line` beats ragg.

### R1.5 PNG output
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/png.rs`
- **Do:** Move the prototype's encoder over and make it stream: take bands
  in row order as R1.1 finishes them. Choosing RGB or RGBA needs to know
  whether the page is opaque before the first row; decide it from the
  background and the display list (`bg = "transparent"` gives RGBA). Add
  ragg's `pHYs` chunk from `dpi`. Measure fdeflate's fast mode against
  parallel deflate on large pages.
- **Done when:** the files decode to the canvas exactly, carry the same
  metadata as ragg's, and encode the README page in about 20 ms or less.

## R2 Text (milestone 2.1)

### R2.1 Font resolution and metrics
- **Depends:** R0.2
- **Touches:** `R/render-text.R`, `alot-core/src/render/text.rs`
- **Do:** Resolve family and face to font files in R with
  `systemfonts::match_fonts()`, once per distinct style. In Rust, load the
  fonts with `ttf-parser` and shape with `rustybuzz`. Mirror
  `textshaping`/ragg string width, ascent and descent, and grid's fontsize ×
  lineheight rules for multi-line text.
  Check that every glyph exists in the resolved font; if any is missing,
  the plot goes to the hybrid tier (ragg's font fallback isn't mirrored).
- **Done when:** widths are within 0.25 px and heights match grid's
  `stringWidth()`/`stringHeight()` on a ragg device, across theme fonts,
  sizes and dpis. Text with missing glyphs (CJK labels with a Latin font,
  emoji) reports the hybrid tier.

### R2.2 Glyph drawing
- **Depends:** R2.1, R1.4
- **Touches:** `alot-core/src/render/text.rs`
- **Do:** Draw text runs unhinted, from cached glyph coverage (per font,
  size and subpixel offset), with hjust, vjust and rotation. Unrotated text
  uses the cache; other angles use outlines. ragg's FreeType hinting is
  not mirrored, so glyph pixels differ slightly from ragg's.
- **Done when:** axis labels, rotated axis titles and multi-line titles pass
  `expect_render_close()` (text may get a documented looser tolerance).

## R3 Render IR (milestone 2.1)

### R3.1 IR extraction
- **Depends:** R1.1
- **Touches:** `R/render-ir.R`, `alot-r/src/render.rs`,
  `alot-core/src/render/ir.rs`
- **Do:**
  - Convert a built plot into the IR: layer columns (borrowed),
    `panel_params`, the facet layout and strip labels, guide parameters
    from `plot@guides`, labels, and fonts.
  - Resolve theme elements once per plot, keyed by element name.
  - Detect support per layer, guide and element. Anything unsupported picks
    the hybrid tier or ggplot2, with the reason, for
    `alot_render_coverage()`.
- **Done when:** extraction takes under 10 ms on the README plot and under
  50 ms on 400 panels, and covers every corpus plot within scope.

### R3.2 Colours
- **Depends:** R3.1
- **Touches:** `alot-core/src/colour/`, `alot-r/src/render.rs`
- **Do:**
  - Parse colours in Rust: hex, R's named colours (the `colors()` table),
    and `NA` as transparent, with a CHARSXP cache.
  - Apply alpha as `scales::alpha()` and `fill_alpha()` do (farver's
    `double2int`).
  - Support numeric palette indices if ggplot2 can produce them, or decline
    them.
- **Done when:** results equal `col2rgb(alpha(colour, a), alpha = TRUE)` on
  every colour R accepts, or decline.

## R4 Layout (milestone 2.1)

### R4.1 Table solver
- **Depends:** R2.1, R3.1
- **Touches:** `alot-core/src/render/layout.rs`
- **Do:** Build a gtable-like row and column solver over absolute, `null`,
  summed and text-measured units, with margins, mirroring
  `ggplot_gtable()`'s `plot_table` assembly and title, subtitle, caption
  and tag placement (`plot.title.position`, `plot.caption.position`, tag
  positions). Add the debug box export.
- **Done when:** the layout export matches grid within 0.5 px for every
  single-panel corpus plot.

### R4.2 Panel decorations and axes
- **Depends:** R4.1, R1.3, R1.4, R2.2
- **Touches:** `alot-core/src/render/{panel,axis}.rs`
- **Do:** Draw the panel background, major and minor grid lines and the
  border from theme elements. Mirror `guide_axis` drawing: ticks, labels,
  `angle`, `n.dodge`, `check.overlap`, minor ticks and axis lines, for
  positions bottom, left, top and right.
- **Done when:** blank-layer plots with `theme_grey()` pass
  `expect_render_close()` and the layout check.

## R5 README vertical slice (milestone 2.2)

The README plot entirely in the full tier, before any breadth. Each task
covers exactly what the plot needs, and declines (drops a tier) for
anything else.

### R5.1 Points in the full tier
- **Depends:** R4.2, R1.2
- **Touches:** `R/render.R`, `alot-core/src/render/geoms/point.rs`
- **Do:** Mirror `GeomPoint$draw_panel` in Rust onto point batches, with
  `coord_cartesian` (`expand`, `clip`) and continuous and log scales. Switch
  `alot_png()` to the full tier when the whole plot is supported.
- **Done when:** single-panel `geom_point` plots without legends render in
  the full tier and pass `expect_render_close()`.

### R5.2 Fixed-scale `facet_wrap` and strips
- **Depends:** R5.1
- **Touches:** `alot-core/src/render/facet.rs`
- **Do:** Mirror `FacetWrap$draw_panels` for fixed scales: panel table,
  axes on outer panels, strips on top with `theme_grey()`'s strip elements,
  and panel spacing.
- **Done when:** fixed-scale `facet_wrap` point plots pass layout and image
  checks.

### R5.3 Colourbar and point legend
- **Depends:** R5.1, R4.1
- **Touches:** `alot-core/src/render/{legend,keys}.rs`
- **Do:** Mirror guide assembly for the right-hand legend box with two
  guides: `guide_colourbar` (bar raster or rects, ticks, labels) and
  `guide_legend` with `draw_key_point` keys. Cover titles, spacing and box
  stacking.
- **Done when:** the README plot renders in the full tier, passes layout and
  image checks, and meets both PHASE2.md targets.

## R6 Breadth (milestones 2.3–2.6)

### R6.1 Core geoms
- **Depends:** R5.1
- **Do:** Mirror `draw_panel`/`draw_group` for line, path, step, col/bar,
  rect, tile and text.
- **Done when:** each passes `expect_render_close()` across its corpus
  plots.

### R6.2 Complete themes
- **Depends:** R4.2
- **Do:** Cover every built-in complete theme, and the theme elements and
  options they use.
- **Done when:** blank and point plots pass in each theme.

### R6.3 Facets in full
- **Depends:** R5.2
- **Do:** Add `facet_grid`, free scales, `space = "free"`, axes on every
  panel where ggplot2 draws them, and strip positions, `switch` and
  `strip.placement`.
- **Done when:** facet corpus plots pass layout and image checks.

### R6.4 Legends in full
- **Depends:** R5.3, R6.1
- **Do:** Add `draw_key_*` for every in-scope geom, `guide_coloursteps`,
  `guide_bins`, merged legends, `byrow`, `nrow` and `ncol`, all legend
  positions including inside, and `legend.box`/justification.
- **Done when:** legend corpus plots pass layout and image checks.

### R6.5 Remaining geoms
- **Depends:** R6.1
- **Do:** Add drawers for the rest of PHASE2.md's geom list (area, ribbon,
  density, boxplot, violin, the ranges, crossbar, segment, curve, the
  reference lines, smooth, label, rug and annotate layers). These can be
  split into one task per family when started.
- **Done when:** each passes `expect_render_close()` across its corpus
  plots.

### R6.6 Coords and secondary axes
- **Depends:** R6.1
- **Do:** Add `coord_flip`, `coord_fixed`/`aspect.ratio` and
  `coord_transform` (munching mirrored from ggplot2, in Rust where it is per
  row), plus secondary axes.
- **Done when:** the corpus plots using them pass layout and image checks.

## R7 Integration (milestone 2.7)

### R7.1 Tier selection and messages
- **Depends:** R5.3
- **Do:** Finalise automatic tier choice, the one-time message when a plot
  drops below the full tier, and warn-and-fall-back on internal errors.
  Make sure the hybrid tier covers every layer that has a full-tier
  drawer.
- **Done when:** every corpus plot renders through some tier, and
  `alot_render_coverage()` explains each one that isn't full.

### R7.2 Performance pass
- **Depends:** R6.3, R6.4
- **Do:** Profile the render suite end to end. Remove serial stages and
  per-call allocations, and check thread scaling and memory at 300 dpi.
- **Done when:** the PHASE2.md performance targets are met and recorded in
  `RESULTS.md`.

### R7.3 Phase 2 exit
- **Depends:** everything above
- **Do:** Verify the render corpus passes, the targets are met, PHASE2.md
  reflects what shipped, and the README documents `alot_png()` and
  `alot_ggsave()`.
- **Done when:** the checklist is recorded in this file.

## Suggested order (Phase 2)

1. R0.1 and R0.2 in parallel, then R0.3 and R0.4.
2. R1.1, then R1.2–R1.5 in parallel. The hybrid tier gains rects and paths
   as they land.
3. R2.1 and R3.1 in parallel, then R3.2, R2.2 and R4.1, then R4.2.
4. The README vertical slice: R5.1 → R5.2 → R5.3.
5. Breadth: R6.1–R6.6, mostly in parallel.
6. R7.1 → R7.2 → R7.3.

The README plot's remaining build time (about 195 ms) is Phase 1's T6.2.
