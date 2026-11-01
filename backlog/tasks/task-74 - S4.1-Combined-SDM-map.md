---
id: TASK-74
title: S4.1 Combined SDM map
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - north-star
milestone: m-2
dependencies:
  - TASK-67
  - TASK-69
  - TASK-72
documentation:
  - doc-4
ordinal: 800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S1.1, S2.1, S3.2
- **Touches:** `R/render-raster.R`, `R/render.R`, `inst/bench/spatial.R`
- **Do:** Let the raster drawer run under `coord_sf()` (linear when
  `default_crs` is NULL) as a hybrid lazy grob, with raster and sf layers
  in the same panels and fixed-scale facets. Do a performance pass on the
  north star and its faceted variant: IR time, per-panel overhead,
  threads, buffer reuse. This pass also takes on the raster build
  overhead that S1.2 left (see S1.2's decision). After S1.1, alot's build
  is about 87% (≈480 ms) of raster_2000's end-to-end time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 both north-star cases render through the hybrid tier, match ragg, and meet SPATIAL.md's target (≥5× end to end, or the target revised in S0.2).
<!-- AC:END -->
