# alot — Phase 1 sub-tasks

Breaks [PLAN.md](PLAN.md) into tasks of about one PR each. IDs follow the
plan's milestones. Each task lists what it depends on, the files it touches,
and when it is done.

**Status:** a task with no marker is not started. When a task's commit lands,
append `— done` to its heading, or `— dropped (see RESULTS.md)` if the kernel
failed the 1.25× rule.

Every task that adds a kernel shares these completion criteria, so they are
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

### T2.4 Discrete non-position mapping
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

### T2.5 Size, alpha and linewidth scales
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

## 1.3 Stats

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

## 1.4 Positions

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

### T5.1 Panel assignment for `layout$setup` / `map_data`
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

### T5.2 Batched `labeling::extended` in Rust
- **Depends:** —
- **Touches:** `alot-core/src/breaks/extended.rs`
- **Do:** Port `labeling::extended` with the same floating-point operation
  order and the default `Q`, `w` and `only.loose` settings. The batched
  entry point takes many `(dmin, dmax, m)` triples.
- **Done when:** outputs are identical to `labeling::extended` on about 1e5
  random ranges, including degenerate, tiny, huge and negative ranges.

### T5.3 Mirror `setup_panel_params` and deduplicate per axis
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
- **Depends:** T3.3, T4.1, T5.1, T5.3, T5.4
- **Do:** Run the facet-scaling suite and confirm the histogram is at least
  5× faster at 400 panels, the free-scale cases at least 2× faster, and the
  fixed-scale control no slower. Confirm that cost grows linearly from 100 to
  1,600 panels. Fix any per-panel overhead that remains.

---

## 1.6 Remaining per-row steps

### T6.1 Re-profile and pick targets
- **Depends:** 1.1–1.5 kernels merged
- **Do:** Profile the bench suites with kernels in place. List
  `compute_geom_1`, `compute_geom_2`, `finish_statistics`,
  `layout$finish_data` and `.ignore_data`/`.expose_data` by share of build
  time. Open one task per step that could plausibly pass the 1.25× rule, and
  record the rest as "stays in R".

---

## Phase 1 exit

### T7.1 Exit checklist
- **Depends:** everything above
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
