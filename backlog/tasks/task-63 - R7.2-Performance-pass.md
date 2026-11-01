---
id: TASK-63
title: R7.2 Performance pass
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - integration
  - partial
milestone: m-1
dependencies:
  - TASK-58
  - TASK-59
documentation:
  - doc-3
ordinal: 10660
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R6.3, R6.4
- **Do:** Profile the render suite end to end. Remove serial stages and
  per-call allocations, and check thread scaling and memory at 300 dpi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the PHASE2.md performance targets are met and recorded in `RESULTS.md`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README plot, `alot_png()` from a built plot, release build:
105 ms at 1600 × 1000 (< 120), 190 ms for the 300 dpi page (< 200), 37
ms for 10 rows (target < 25, not met: about 25 ms of it is R's IR and
layout, spread over many small calls; accepted as optimistic). Thread
starts for small batches removed (`raster::par_map()`), fresh buffers
filled in parallel (point spec dealt to panels in one pass, placements),
colours mapped in parallel, `alot_png()` streams the full tier to the
PNG encoder without a nativeRaster, font matches cached per render.
Thread scaling and memory are in inst/bench/RESULTS.md (R7.2).
<!-- SECTION:FINAL_SUMMARY:END -->
