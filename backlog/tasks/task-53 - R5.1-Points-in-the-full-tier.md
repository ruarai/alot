---
id: TASK-53
title: R5.1 Points in the full tier
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - readme-vertical-slice
milestone: m-1
dependencies:
  - TASK-52
  - TASK-43
documentation:
  - doc-3
ordinal: 10520
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README plot entirely in the full tier, before any breadth. Each task
covers exactly what the plot needs, and declines (drops a tier) for
anything else.

- **Depends:** R4.2, R1.2
- **Touches:** `R/render.R`, `alot-core/src/render/geoms/point.rs`
- **Do:** Mirror `GeomPoint$draw_panel` in Rust onto point batches, with
  `coord_cartesian` (`expand`, `clip`) and continuous and log scales. Switch
  `alot_png()` to the full tier when the whole plot is supported.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 single-panel `geom_point` plots without legends render in the full tier and pass `expect_render_close()`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`full_points()` (`R/render-full.R`) turns each `geom_point()`
layer's built data (missing rows removed, shapes translated, as the hybrid
does) into a `PointLayer` of `panel.rs`, which places the points in the
panel cell (`PointBatch`, the hybrid's placement) between the grid and the
border, inside the panel clip. Layers of `geom_point()` and `geom_blank()`
only; `coord_cartesian()` with `clip = "on"` and linear position scales
(log, sqrt and reversed scales are linear in transformed space);
`hybrid_decline()` decides, so other plots drop to the hybrid tier.
`alot_png()` tries the full tier first (`options(alot.full_tier = FALSE)`
skips it; the test helper sets that so the hybrid tests keep their tier).
ggplot2's missing-value warning is raised once, after drawing.
<!-- SECTION:FINAL_SUMMARY:END -->
