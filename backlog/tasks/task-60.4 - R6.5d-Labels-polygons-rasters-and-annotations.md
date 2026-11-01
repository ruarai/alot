---
id: TASK-60.4
title: R6.5d Labels, polygons, rasters and annotations
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
ordinal: 10630
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of R6.5 (remaining geoms), split out when it was started.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws `geom_label()` (R/render-labels.R) as
GeomLabel's `labelGrob()` lays each label out about its position: the
top padding raised to the descent of "gjpqyQ" and the bottom one reduced
by it, the text placed by `titleGrob()`'s margins, and the box as the
polygon of grid's `rrpoints()` (`roundrectGrob()`), all in device pixels
and rotated by `angle`; `label.padding` (one or four values), `label.r`,
`border.colour`, `text.colour`, `linewidth` 0 (no border), `alpha` on the
fill only, justification, faces, facets and free scales. Rust gets a label
layer (a path layer of boxes with per-vertex pixel offsets and a text layer
with per-label offsets) drawn box, text, box, text as grid does, batched
where boxes don't overlap. `geom_polygon()` without subgroups is drawn as
closed filled paths (one per group, styled by its first row, nothing for
a panel of one row). `draw_key_label()` is drawn (its size taken with the
padding in the device's default 12 pt, its raise by the descent at a
fontsize of `size`, as ggplot2 computes them). annotate() layers of the
drawn geoms (text, label, rect, segment, pointrange, polygon, ...) need
nothing of their own and are tested. `test-render-labels.R` has about 30
image + layout cases and the fallbacks. With the full tier forced on, 33
of the 57 render-corpus plots of the label/text, polygon, annotate and
raster files draw in full and match ragg, as do 189 of the 208 of the
default sample. Declined: `geom_raster()` and `annotation_raster()` (a
device-scaled, possibly interpolated `rasterGrob()`; not mirrored within
this task), polygon subgroups (`pathGrob()` with holes and `rule`; the
hybrid tier draws them), parsed, numeric and multi-line labels,
`label.padding`/`label.r` in npc-like units, vectors of `border.colour` or
`text.colour`, non-finite label positions, rotated label keys, and the
coords and options the full tier declines elsewhere. No hybrid label
drawer (left to R7.1).
<!-- SECTION:FINAL_SUMMARY:END -->
