---
id: TASK-61
title: R6.6 Coords and secondary axes
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
ordinal: 10640
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R6.1
- **Do:** Add `coord_flip`, `coord_fixed`/`aspect.ratio` and
  `coord_transform` (munching mirrored from ggplot2, in Rust where it is per
  row), plus secondary axes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the corpus plots using them pass layout and image checks.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`coord_fixed()`/`coord_equal()`, `theme(aspect.ratio)` and
secondary axes (`sec_axis()`, `dup_axis()`, axes at `position = "top"`/
`"right"`, discrete or continuous, with facets) were already drawn in
full by R4.2/R6.3's layout and axis drawers; they are now tested
(`test-render-coords.R`). `coord_flip()` draws in full for every geom the
full tier draws but rugs: the drawers decompose in data space (as the
geoms do before `Coord$transform()`) with data x on the vertical scale's
range, then `full_flip()` swaps the marks' position columns and ranges as
`CoordFlip$transform()`'s `flip_axis_labels()` does; text and the labels'
text go through `coord$transform()` itself, and the grid lines flip as
`guide_grid()` flips them. `coord_transform()` draws points and text in
full (`full_transform()`: `CoordTransform$transform()` per panel, then
npc), with facets, free scales, limits and discrete scales. The layout now
gives axis labels at NaN positions no room, as grid's text bounds skip
them (the `geom_bar()` + `coord_transform(y = "log10")` corpus plot was
7.45 px off). `test-render-coords.R` has 36 image + layout cases and the fallbacks.
With the full tier forced on, 100 of the 110 render-corpus plots of the
coord and sec-axis files draw in full and match ragg (`ALOT_LAYOUT_ALL=1`),
as do 195 of the 208 of the default sample (189 before). Declined:
`coord_transform()` for every geom it munches (`coord_munch()`: lines,
paths, rects, bars, ribbons, segments, polygons, ...; munching is not
mirrored within this task), `coord_transform()` where the transform makes
a position or a panel range infinite (ggplot2 warns as it squishes them),
rugs with `coord_flip()` (GeomRug flips its sides), reversed coords and the
non-cartesian coords (`coord_polar()`, `coord_radial()`, `coord_sf()`).
No hybrid drawer for the new coords (the hybrid tier still draws only
`coord_cartesian()`; left to R7.1).
<!-- SECTION:FINAL_SUMMARY:END -->
