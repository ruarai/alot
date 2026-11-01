---
id: TASK-60.2
title: R6.5b Boxplots and ranges
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
ordinal: 10610
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of R6.5 (remaining geoms), split out when it was started.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws `geom_boxplot()`, `geom_violin()`,
`geom_crossbar()`, `geom_errorbar()`, `geom_linerange()` and
`geom_pointrange()` (R/render-ranges.R) as ggplot2 decomposes them, in its
drawing order: per boxplot (by panel, then group) the outliers, staples,
whiskers, box polygon and median; per violin its polygon then its
quantile lines; per panel all crossbar polygons then their middles, all
linerange segments then the pointrange points, and each error bar as a
polyline broken at NA. They go to Rust as path layers (closed, filled
paths and open ones) and point layers, a layer per run of one kind in each
panel (`full_marks()`). Notches, `staplewidth`, `varwidth`, the
`outlier.*`, `whisker.*`, `staple.*`, `median.*`, `box.*` and
`middle.*` parameters, `quantile.*` lines, flipped orientations, facets
and free scales are drawn, as are NA rows of error bars (kept by
ggplot2, broken by grid). Keys: `draw_key_boxplot()`,
`draw_key_crossbar()` (a key glyph rect can now be a share of the key),
`draw_key_linerange()`/`draw_key_vpath()` and `draw_key_pointrange()`;
violins and error bars use the polygon and path keys. The path drawer
now rasterises each path over its bounding box only, so that many small
paths are faster than ragg (1e5 error bars: 11.4 s before, 324 ms now,
against ragg's 10.7 s). `test-render-ranges.R` has about 30 image +
layout cases. With the full tier forced on, 95 of the 100 render-corpus
plots of the boxplot, violin, errorbar, linerange and summary files draw
in full and match ragg, as do 181 of the 208 of the default sample.
Declined: notches outside the hinges (self-intersecting, with
ggplot2's message), NA positions other than an error bar's (ggplot2
warns as GeomSegment removes them), violins of one row, more than one
boxplot per group, unknown shapes, arrows, and the coords and options the
full tier declines elsewhere. No hybrid drawer (left to R7.1): in the
hybrid tier ggplot2 draws them.
<!-- SECTION:FINAL_SUMMARY:END -->
