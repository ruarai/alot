---
id: TASK-60
title: R6.5 Remaining geoms
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-56
documentation:
  - doc-3
ordinal: 10590
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R6.1
- **Do:** Add drawers for the rest of PHASE2.md's geom list (area, ribbon,
  density, boxplot, violin, the ranges, crossbar, segment, curve, the
  reference lines, smooth, label, rug and annotate layers). These can be
  split into one task per family when started.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 each passes `expect_render_close()` across its corpus plots.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Split into R6.5a–d below. The full tier now draws the ribbon
family and smooths (a), boxplots, violins, crossbars and the range geoms
(b), segments, reference lines and rugs (c), and labels, polygons and
annotate() layers of all of these (d), with their legend keys; every corpus
plot it draws matches ragg (with the full tier forced on, 189 of the 208
plots of the default render-corpus sample draw in full, against 168 after
R6.5c). Declined, and drawn by the hybrid or ggplot2 tier instead:
`geom_curve()` (grid's X-spline), `geom_raster()`, arrows, polygon
subgroups (holes), aesthetics varying along a line or ribbon, parsed or
multi-line labels, and the coords and options the full tier declines
elsewhere. None of these geoms has a hybrid drawer beyond the existing
polygon one (left to R7.1).
<!-- SECTION:FINAL_SUMMARY:END -->
