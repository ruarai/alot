---
id: TASK-43
title: 'R1.2 Point batches: all shapes'
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - raster-engine
milestone: m-1
dependencies:
  - TASK-42
documentation:
  - doc-3
ordinal: 10420
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 every shape passes `expect_render_close()` at several sizes, strokes, alphas and dpis, and a plot mapping `size` to 1e4 distinct values is no slower than ragg.
<!-- AC:END -->
