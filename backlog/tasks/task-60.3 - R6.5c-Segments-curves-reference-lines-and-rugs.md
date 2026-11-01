---
id: TASK-60.3
title: R6.5c Segments, curves, reference lines and rugs
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
ordinal: 10620
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of R6.5 (remaining geoms), split out when it was started.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws `geom_segment()`, `geom_abline()`,
`geom_hline()`, `geom_vline()` and `geom_rug()` (R/render-segments.R) as
two-vertex path marks through `full_marks()`, in ggplot2's order: each
panel's segments in row order; the reference lines of `unique0()` of the
panel's rows with GeomHline's, GeomVline's and GeomAbline's ends (the
panel's range, extended by its width either side for abline as clip is
on); the rug's sides "b", "t", "l", "r" in turn, from the panel's edge to
`length` (npc units) inside or, with `outside`, outside it, skipping a
side's rows at NA as grid does. Free scales, facets, Inf ends, `lineend`
and the line aesthetics are drawn. Keys: `draw_key_abline()` and
`draw_key_vline()` (with `draw_key_path()`, drawn since R6.4).
`test-render-segments.R` has about 30 image + layout cases. With the full
tier forced on, the 29 of 43 render-corpus plots of the segment, curve,
abline/hline/vline and rug files that it draws match ragg, as do the 168
of 208 of the default sample. Declined: `geom_curve()` (grid's
`curveGrob()` places control points in inches and draws an engine
X-spline, not mirrored), arrows, NA segment ends (ggplot2 warns as it
removes them), rug lengths in units other than npc, and the coords and
options the full tier declines elsewhere. No hybrid drawer (left to
R7.1). The render tests' undrawn example is now `geom_curve()`.
<!-- SECTION:FINAL_SUMMARY:END -->
