---
id: TASK-68
title: S1.2 Raster build steps (conditional)
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - raster
  - dropped
milestone: m-2
dependencies:
  - TASK-66
documentation:
  - doc-4
ordinal: 10710
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S0.2
- **Touches:** `R/kernels-geom.R` (new), `alot-core/src/geom/` (new)
- **Do:** Only if S0.2's profile shows a build step of the raster cases
  (e.g. `GeomRaster$setup_data`'s `resolution()` and per-row
  xmin/xmax/ymin/ymax) worth at least 1.25× at 1e6 rows: mirror it and
  add a kernel. If not, mark this task dropped and record why in
  RESULTS.md.
- **S0.2 verdict:** drop as specified. `GeomRaster$setup_data` takes 19 ms at
  1e6 rows, about 1% end to end. Re-scoping to the existing kernels'
  overhead at 2e6 rows (`npscales_map`, position train and map) is the
  alternative; see RESULTS.md "S0.2: spatial baseline".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the Phase 1 criteria hold, or the task is dropped with the reason recorded.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**Decision (2026-11-01):** Dropped. The overhead of the existing build
kernels on the raster cases (`npscales_map`'s per-row hex strings,
R-side time in position training and mapping) moves to S4.1's
performance pass, because the north-star target is what makes it worth
cutting.
<!-- SECTION:FINAL_SUMMARY:END -->
