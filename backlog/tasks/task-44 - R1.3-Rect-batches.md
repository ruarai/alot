---
id: TASK-44
title: R1.3 Rect batches
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
ordinal: 10430
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/rects.rs`
- **Do:** Draw axis-aligned rects: fill-only with ragg's `snap_rect`
  rounding, and with outlines through the path drawer (R1.4). This is the
  drawer for bars, tiles, raster-like tiles, panel backgrounds and legend
  keys.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 a 1000 × 1000 `geom_tile` matches ragg and draws in under a tenth of ragg's time.
<!-- AC:END -->
