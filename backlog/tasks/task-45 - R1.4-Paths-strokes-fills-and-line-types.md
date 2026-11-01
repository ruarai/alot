---
id: TASK-45
title: 'R1.4 Paths: strokes, fills and line types'
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
ordinal: 10440
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/paths.rs`
- **Do:**
  - Compare an exact-area AA scanline rasteriser (AGG-style cell
    accumulation) with tiny-skia, measuring fidelity against ragg and speed
    on 1e6-segment lines. Pick one and record why in `RESULTS.md`.
  - Implement stroking with lwd, `lineend`, `linejoin`, `linemitre` and R's
    `lty` dash patterns (named and hex), plus nonzero and even-odd fills.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lines, polygons and dashes at several lwds pass `expect_render_close()`, and a 1e6-point `geom_line` beats ragg.
<!-- AC:END -->
