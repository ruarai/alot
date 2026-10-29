# alot — Phase 1 plan: `ggplot_build()` in Rust

Phase 1 delivers `alot_build(p)`, a drop-in replacement for
`ggplot2::ggplot_build(p)`. The output must equal ggplot2's under
`expect_equal(..., tolerance = 1e-8)`, and the expensive parts must run in
Rust. Rendering is Phase 2 ([PHASE2.md](PHASE2.md)).

## Where we are

Done (milestone 0 plus the first kernel):

- `alot_build()` ([R/build.R](R/build.R)) repeats `ggplot2:::build_ggplot`
  ([../ggplot2/R/plot-build.R](../ggplot2/R/plot-build.R)) step by step.
- Kernel registry with fallback ([R/registry.R](R/registry.R)). A kernel is
  used only when the object's first class exactly matches the registered
  class, and the kernel may return `NULL` to decline. In every other case
  ggplot2's own method runs. `alot_coverage(p)` reports which path each
  component took.
- Rust workspace: `alot-core` (pure Rust, tested with `cargo test`) and
  `alot-r` (extendr 0.9 glue), under [src/rust/](src/rust/).
- Kernel: continuous position-scale range training
  ([R/layout.R](R/layout.R), [R/kernels-scale.R](R/kernels-scale.R),
  [range.rs](src/rust/alot-core/src/scale/range.rs)).
- Equivalence harness `expect_build_equal()` and a snapshot of upstream
  `build_ggplot` that fails if ggplot2 changes it.

## Where the time goes

`ggplot2::ggplot_build()` on 2 million rows (R 4.6.1, ggplot2 4.0.3). The
percentages are each case's share of build time from `Rprof`:

| Plot | Time | Dominant cost |
|---|---|---|
| `geom_point`, discrete colour | 1.26 s | `scale_apply`: 68% (position train 38%, `map_position` 40%) |
| `geom_point`, continuous colour | 1.28 s | non-position `map_df`: 37%; `scale_apply`: 40% |
| `facet_wrap` + point | 0.94 s | `scale_apply`: 50%; `layout$setup` (panel assignment): 19% |
| histogram, 5 fills | 0.56 s | stat: 40%, mostly `dapply` group splitting |
| bar + dodge | 0.80 s | stat_count: 41% |
| density, 5 groups | 0.56 s | stat: 41% |
| boxplot | 0.95 s | stat: 44% |
| smooth (`lm`) | 1.77 s | stat: 73% (model fit + predict) |

Plots with many facets have a different cost profile. They have few rows per
panel, so the time goes to per-panel overhead:

| Plot (200 rows per panel) | Time | Dominant cost |
|---|---|---|
| `facet_wrap`, 400 panels, fixed scales, point | 0.06 s | none; fixed scales are shared, so this is a control case |
| `facet_wrap`, 400 panels, `scales = "free"`, point | 3.34 s | `setup_panel_params`: 46% (`labeling::extended` 15%, ggproto method lookup about 20%); `setup_panel_guides`: 40% |
| `facet_grid` 20×20, `scales = "free"`, point | 2.43 s | same as above: 52% + 41% |
| `facet_wrap`, 400 panels, histogram (`stack`) | 1.81 s | `dapply` once per panel: stat about 30%, `collide`/stack 61% |

So: **anything that costs O(n rows) is a target, and so is per-panel overhead
once there are many panels. Anything that costs O(breaks) or O(levels) for a
single scale stays in R.** This revises the original plan. Computing breaks and
labels for one scale handles a few dozen values, so it would gain nothing and
would put fidelity at risk (R's `format()` for labels is especially hard to
reproduce). Across hundreds of free-scale panels, though, the same steps
dominate the build. Most vectorised R code already runs in C. Rust wins by
doing work in one pass, avoiding per-group and per-panel splitting and copies,
and skipping the overhead of calling ggproto methods.

**Rule for adding a kernel:** keep it only if the benchmark shows at least a
2× speedup for its step at 1e6 rows. Otherwise delete it, because each kernel
adds risk of diverging from ggplot2.

## Milestones

### 1.0 Infrastructure

- **Switch to the full rextendr scaffold** now that usethis is installed:
  `configure` / `tools/config.R` / `Makevars.in`, the `document` binary that
  generates [R/extendr-wrappers.R](R/extendr-wrappers.R), and `tools/msrv.R`.
  Keep the two-crate workspace and point the build at `-p alot-r`.
- **Vendoring** (`rextendr::vendor_pkgs()`) so the package builds offline, as
  CRAN requires. Add `inst/AUTHORS` and a licence note for vendored crates.
- **Data interchange layer** (`alot-r/src/convert.rs`):
  - Borrow double/integer/logical slices without copying.
  - Represent factors as codes plus levels, and strings as `Strings`.
  - Pass integer NA as `None`.
  - Rust returns a named list of columns. The R side rebuilds the frame with
    `data_frame0()` in ggplot2's column order, and `merge_attrs()` (already
    used in the mirrors) restores classes such as `mapped_discrete`.
- **Grouped-kernel driver**: one Rust entry point takes the group index
  (`PANEL` × `group`) and runs a kernel over every group in one pass. Results
  come back concatenated in ggplot2's group order. This replaces the
  `dapply` / `split` / `vec_rbind` overhead behind Stat and Position
  `compute_layer`.
- **Corpus harness** (`tests/testthat/test-corpus.R`): extract every plot from
  ggplot2's `man/` examples and `tests/testthat/` in `../ggplot2`, then run
  `expect_build_equal()` on each. Allow-list the ones that need unavailable
  packages. This is the main regression net.
- **Benchmarks** (`inst/bench/`, using `bench`), timing alot against ggplot2
  overall and per step. Record results in `inst/bench/RESULTS.md`.
  - **Row-scaling suite:** the eight large-data cases above at 1e4, 1e6 and
    1e7 rows.
  - **Facet-scaling suite:** the four many-facet cases above at 25, 100, 400
    and 1,600 panels with 200 rows per panel. This shows whether cost per
    panel stays flat.

### 1.1 Position scales (largest share of time for point plots)

- **Discrete position training** (`DiscreteRange`, via
  `scales:::discrete_range`). Rust computes the unique values / levels present
  in O(n). R then merges and sorts the k levels itself, because `sort()` on
  characters depends on the locale. Also cover `range_c` for continuous values
  plotted on discrete scales.
- **`layout$map_position`**:
  - Continuous: `oob` (censor or squish) plus `na.value`
    ([../ggplot2/R/scale-continuous.R](../ggplot2/R/scale-continuous.R)
    `map`).
  - Discrete: map levels to integers and tag the result `mapped_discrete`.
  - This mirrors `Layout$map_position` the same way `train_position` is
    already mirrored.
- **`scales$transform_df`** for `log10`, `sqrt`, `reverse` and `identity`
  transforms. Check that Rust's `log10` gives results identical to R's (both
  call libm).

### 1.2 Non-position scales

`npscales$train_df` and `npscales$map_df`:

- **Continuous colour/fill**: `rescale`, then `scales::colour_ramp`
  interpolation in CIELAB. The hex strings must match farver's encoding
  byte for byte, so port its Lab↔sRGB conversion and rounding, and test
  against farver on a dense grid.
- **Palettes**: gradient, gradient2, gradientn, viridis. Palette *generation*
  is O(k) and stays in R; only per-row mapping goes to Rust.
- **Discrete scales** (hue, brewer, manual, shape, linetype): map levels to
  palette entries with a hash lookup.
- **Size, alpha, linewidth**: `rescale` + `area_pal` / `rescale_pal`.
- **Binned scales**: last. Fall back until the rest is done.

### 1.3 Stats

All stats run on the grouped driver from 1.0.

| Stat | Notes on matching ggplot2 |
|---|---|
| `StatIdentity` | Becomes a no-op; it avoids the split entirely. |
| `StatCount`, `StatSum`, `StatUnique` | Hashing; first-appearance vs sorted order as in ggplot2. |
| `StatBin` | Port [../ggplot2/R/bin.R](../ggplot2/R/bin.R) exactly: `bins` / `binwidth` / `boundary` / `center` / `breaks`, `closed`, `pad`, and the 1e-8 fuzz. |
| `StatDensity`, `StatYdensity` | `stats::density`: `bw.nrd0` / `nrd` / `ucv`…, linear binning, FFT convolution, `approx`. Hand bandwidths other than `nrd0`/`nrd` to R as a scalar. |
| `StatBoxplot` | `quantile(type = 7)`, outliers, `notch`, `relvarwidth`, `width`. |
| `StatSummary` | Kernels for `mean_se` and `median_hilow`; other `fun`s fall back. Note that R's `mean()` makes two passes in long double. |
| `StatEcdf`, `StatBin2d`, `StatSummary2d` | Straightforward once the binning code exists. |
| `StatSmooth` | `method = "lm"` only: QR least squares, prediction and standard errors. The `qt()` quantile is a scalar computed in R and passed in. `loess` and `gam` fall back. |
| Contour, hex, quantile, sf, ellipse, qq | Fall back. Low priority. |

### 1.4 Positions

- `PositionStack` / `PositionFill`: grouping by `xmin`, `reverse`, `vjust`,
  and handling of negative values.
- `PositionDodge` / `PositionDodge2`: `n`, `width`, `padding`,
  `preserve = "single"`.
- `PositionJitter` and `PositionNudge` are already vectorised R. Measure them
  first. If jitter gets a kernel, the random draws stay in R (`runif` under
  `with_seed_null`) so `set.seed()` and `seed =` give identical output.

### 1.5 Facets and layout setup

- `layout$setup` / `Facet$map_data` for FacetWrap and FacetGrid: assign each
  row to a panel with a hash join on the facet variables (19% of build time
  for faceted plots with large data).
- Computing the layout itself (`compute_layout`) runs once per plot and stays
  in R.
- **Per-panel stat and position work.** The grouped driver (1.0) already
  treats `PANEL` × `group` as one index, so 400 panels cost one Rust call
  instead of 400 `dapply` rounds. Nothing new is needed beyond 1.3 and 1.4,
  but the 400-panel histogram benchmark tracks it.
- **Free-scale panel setup.** Mirror `Layout$setup_panel_params` and
  `Layout$setup_panel_guides`
  ([../ggplot2/R/layout.R](../ggplot2/R/layout.R)) and
  `CoordCartesian$setup_panel_params`
  ([../ggplot2/R/coord-cartesian-.R](../ggplot2/R/coord-cartesian-.R)):
  - **Batched breaks.** Port `labeling::extended` to Rust, matching its
    floating-point operations in the same order, and compute major and minor
    breaks for every panel's x and y scales in one call. Test it against the R
    `labeling` package on a large set of random ranges. Labels stay in R
    (`format()`), but are computed once for each distinct set of breaks.
  - **Separate x and y work.** ggplot2 deduplicates by (x scale, y scale) pair
    (`COORD`). In a free 20×20 grid that means 400 calls, although there are
    only 20 distinct x scales and 20 distinct y scales. View scales and axis
    guides depend on one axis only, so build them once per `SCALE_X` and once
    per `SCALE_Y`, then combine. Each panel still gets its own copy of the
    objects (ggproto clone), so mutating one panel never affects another.
  - **Less ggproto overhead.** Within the mirror, read methods and fields
    once per scale class rather than once per panel, removing the 20% spent in
    `fetch_ggproto` / `make_proto_method`. The objects built must still be
    exactly the view-scale and guide objects that ggplot2 builds.
  - This is all R orchestration plus the Rust breaks kernel. It returns
    ggproto objects that `expect_build_equal()` compares field by field, and
    it falls back for coords other than `CoordCartesian` / `CoordFlip` /
    `CoordFixed`.
- Coords: `CoordCartesian`, `CoordFlip` and `CoordFixed` do no O(n) work
  during the build. `CoordTransform` transforms data only at render time. No
  kernels here.

### 1.6 Remaining per-row steps (do these only if the profile justifies them)

`compute_geom_1` (for example `GeomBar$setup_data` computing `xmin`/`xmax`),
`compute_geom_2` (`use_defaults` filling in default aesthetics),
`finish_statistics`, `layout$finish_data`, and `.ignore_data` /
`.expose_data`. Profile with the 1.1–1.5 kernels in place, then add kernels
only where the 2× rule holds.

## Matching ggplot2 exactly: known hazards

- **Locale-dependent sorting.** Character sorts stay in R, applied to unique
  values only.
- **RNG.** Draws always happen in R.
- **Floating point.** Summation order, long-double `mean()`, and FFT round-off
  (rustfft vs R's `fft`) should all stay inside 1e-8. Test against ggplot2,
  not against hand-computed values.
- **Attributes and types.** Integer vs double, factor levels,
  `mapped_discrete`, and column order are all checked by `expect_equal`.
- **Warnings and messages.** ggplot2's user-facing warnings (for example
  "Removed n rows") must still appear. Kernels return counts and R emits the
  warnings. Add `expect_snapshot` coverage for them.
- **Upstream drift.** Pin `ggplot2 (>= 4.0.0, < 4.1.0)`. Each mirrored ggproto
  method gets a body snapshot test like `test-internals.R`.

## Phase 1 is done when

1. Every plot in the ggplot2 examples and tests corpus passes
   `expect_build_equal()` (allow-listed exceptions are documented).
2. `alot_coverage()` shows Rust running for every component in 1.1–1.5.
3. `inst/bench/RESULTS.md` shows alot at least 2× faster overall than ggplot2
   at 1e6 rows for each of the eight benchmark plots, apart from `smooth`
   whose cost is dominated by the model.
4. In the facet-scaling suite at 400 panels:
   - the histogram (`stack`) case is at least 5× faster than ggplot2, since
     its cost is almost all per-panel overhead;
   - the free-scale `facet_wrap` and `facet_grid` cases are at least 2×
     faster;
   - the fixed-scale control case is no slower;
   - build time grows no faster than linearly from 100 to 1,600 panels.
5. `R CMD check --as-cran` passes with vendored crates, and `cargo test`
   passes.
