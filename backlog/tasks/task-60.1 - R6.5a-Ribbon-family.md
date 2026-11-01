---
id: TASK-60.1
title: R6.5a Ribbon family
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies: []
documentation:
  - doc-3
parent_task_id: TASK-60
ordinal: 10600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of R6.5 (remaining geoms), split out when it was started.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws `geom_ribbon()`, `geom_area()`,
`geom_density()` (GeomRibbon's `draw_group`, `full_ribbons()` in
R/render-full.R) and `geom_smooth()` (its ribbon when `se`, then
GeomLine's path), each group in turn as `Geom$draw_panel()` draws them:
the polygon of the upper line (without `stat_align()`'s padding rows) and
the reversed lower line, then the outline polylines for `outline.type`
"both", "upper" or "lower", or the polygon's own stroke for "full";
flipped orientations, facets and free scales included. They go to Rust as a
path layer whose paths may be closed and filled (`PathLayer::fill`,
alot-core/src/render/layers.rs). `draw_key_smooth()` is drawn (a rect
for `se`, then the path key at alpha 1); the others use
`draw_key_polygon()`, drawn since R6.4. `test-render-ribbons.R` has
about 30 image + layout cases. With the full tier forced on, the 50 of
51 render-corpus plots of the ribbon, density and smooth files that it
now draws match ragg (the other is a smooth with NA bounds), as do the
165 of 208 plots of the default sample it draws. Declined: aesthetics
varying along a ribbon (ggplot2's gradients, or its abort), groups of
fewer than two rows, NA bounds on a smooth, and the coords and options
the full tier declines elsewhere. They have no hybrid drawer (as text):
in the hybrid tier ggplot2 draws them.
<!-- SECTION:FINAL_SUMMARY:END -->
