---
id: TASK-69
title: S2.1 Mirror the sf build steps
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - sf-build
milestone: m-2
dependencies:
  - TASK-65
documentation:
  - doc-4
ordinal: 400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S0.1
- **Touches:** `R/build.R`, `R/sf.R` (new), `R/ggplot2-internals.R`,
  `tests/testthat/test-sf-build.R` (new), `tests/testthat/test-internals.R`
- **Do:** In `alot_build()`, mirror the steps that sf layers and
  `coord_sf()` add: `LayerSf`'s `setup_layer` and `compute_geom_1/2`
  (ggplot2 R/layer-sf.R), `StatSf$compute_panel` (R/stat-sf.R), and
  `CoordSf`'s `setup_params`, `setup_data`, `record_bbox` and
  `setup_panel_params` (R/coord-sf.R), so `alot_coverage()` reports each
  one. `st_transform()`, `sf_project()` and `st_graticule()` are still
  called through sf. Add `gg_*` wrappers for the unexported helpers
  (`sf_transform_xy`, `calc_limits_bbox`, `sf_breaks`, ...).
  **Same-CRS skip (decided 2026-11-01):** in the `CoordSf$setup_data`
  mirror, skip `st_transform()` when the layer's crs equals the coord's
  crs. S0.2 measured 100–200 ms for this no-op call at 1e6 vertices.
  Test that the sfc's coordinates, bbox, crs, precision, `n_empty` and
  sfg classes equal ggplot2's, and fall back to calling sf whenever
  equality of the crs objects isn't certain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `expect_build_equal()` passes on the sf corpus plots and on the targeted cases in SPATIAL.md's Verification section, and each mirrored method has a snapshot.
<!-- AC:END -->
