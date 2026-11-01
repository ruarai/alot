---
id: TASK-73
title: S3.3 `geom_sf()` lines and points
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - sf-render
milestone: m-2
dependencies:
  - TASK-72
documentation:
  - doc-4
ordinal: 700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S3.2
- **Touches:** `R/render-sf.R`, `tests/testthat/test-render-sf.R`
- **Do:** (MULTI)LINESTRING as `polylineGrob()` and (MULTI)POINT through
  the point sprites, with `sf_grob()`'s size, stroke and `pch`
  arithmetic, in mixed-type layers too (one display item per type run, in
  data order).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the remaining `geom_sf()` corpus plots that don't need GEOMETRYCOLLECTION render through the hybrid tier and match ragg.
<!-- AC:END -->
