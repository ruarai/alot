---
id: TASK-69
title: S2.1 Mirror the sf build steps
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T03:47:00Z'
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
- [x] #1 `expect_build_equal()` passes on the sf corpus plots and on the targeted cases in SPATIAL.md's Verification section, and each mirrored method has a snapshot.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
R/sf.R mirrors LayerSf's setup_layer/compute_geom_1/compute_geom_2, StatSf's compute_layer/compute_panel and CoordSf's setup_params/determine_crs/setup_data/record_bbox/setup_panel_params as kernels, so alot_coverage() reports each one (dispatch() gained a cls argument for layers). CoordSf$setup_data skips st_transform() when sfc_transform_is_noop() proves the result would be identical: crs identical to the target (a crs or a finite EPSG code; not NA or geocentric), only the attributes st_sfc() rebuilds (precision 0, n_empty 0L, correct class/classes/bbox), and every feature a plain finite XY POINT/LINESTRING/POLYGON/MULTI* as CPL_transform() writes it (checked by rs_sfc_plain_xy() in alot-r, bbox via alot-core sf::Bbox). Anything else calls sf. In-CRS sf builds are 1.7–2.5x faster than ggplot2 (layout_setup 120–380 ms → 7–22 ms; RESULTS.md, S2.1).
<!-- SECTION:FINAL_SUMMARY:END -->
