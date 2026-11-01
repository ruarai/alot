---
id: TASK-72
title: S3.2 `geom_sf()` polygons
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - sf-render
milestone: m-2
dependencies:
  - TASK-71
documentation:
  - doc-4
ordinal: 600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S3.1
- **Touches:** `R/render-sf.R` (new), `alot-core/src/render/paths.rs`,
  `tests/testthat/test-render-sf.R` (new), `tests/testthat/test-internals.R`
- **Do:** Mirror `GeomSf$draw_panel` and `sf_grob()` for (MULTI)POLYGON:
  the per-feature gp (`fill`, `colour`, `linewidth`, `linetype`, `alpha`,
  `linejoin`, `lineend`, `linemitre`) and `st_as_grob()`'s
  `pathGrob(rule = "evenodd")`, drawn fill then stroke per feature in data
  order. Batch features whose bboxes don't overlap. Let the hybrid tier
  accept `CoordSf` panels for these lazy grobs.
- **Declines:** `default_crs` set, legend-only layers, linetypes or
  arrows the path drawer declines elsewhere.
- **Also fix (found in S0.1):** with `coord_sf()` and `breaks = NULL` on
  both axes, `ir_scales()` calls the CoordSf view scale's
  `break_positions()`, which aborts with "Not implemented.". Then
  `alot_render_coverage()` errors and `alot_png()` warns before falling
  back. Affected corpus plots: test-coord_sf "graticule lines and axes can
  be removed via scales" #1 and "coord_sf() can render with empty
  graticules" #1. Widen `tools/render-corpus.R` to admit CoordSf and
  GeomSf plots so the render corpus covers them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the sf polygon corpus plots render through the hybrid tier and match ragg, and the 1e6-vertex outline and choropleth cases draw faster than ragg.
<!-- AC:END -->
