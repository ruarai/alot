---
id: TASK-58
title: R6.3 Facets in full
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-54
documentation:
  - doc-3
ordinal: 10570
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R5.2
- **Do:** Add `facet_grid`, free scales, `space = "free"`, axes on every
  panel where ggplot2 draws them, and strip positions, `switch` and
  `strip.placement`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 facet corpus plots pass layout and image checks.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`facet_wrap()` and `facet_grid()` render in the full tier
with free scales, `space = "free"`, `axes`/`axis.labels`, `margins`,
`as.table`, strips at every position, `switch`, `strip.placement =
"outside"` (with `strip.switch.pad.*`), strips of several variables, and
clipped strip text. `layout_facet()` (R/render-layout.R) mirrors which
axis `FacetWrap$attach_axes()`/`FacetGrid$attach_axes()` put beside each
panel (with ggplot2's own `censor_labels()`), the panel sizes of
`init_gtable()` and the strips of `build_strip()`/`assemble_strips()`;
`FacetSpec` (alot-core/src/render/layout.rs, replacing `WrapSpec`) builds
the table with gtable's `weave_tables_row/col()`, `measure_axes()` and
`seam_table()`, and each cell carries the axis or strip it draws.
`page.rs` draws strips (each variable's cell clipped as ragg clips it,
text to `text_clip_box()`) and axes in table order. Panels, grid lines and
layer ranges are per panel, resolved once per pair of scales; text is
transformed per panel. Every plot of the facet corpus files is laid out
as grid does (`ALOT_LAYOUT_ALL=1`) and, with the full tier forced on, the
ones the full tier draws match ragg (`test-render-facet.R`: about 100
cases). Declined (hybrid tier): plotmath or NA strip labels, blank
strip text, outside strips where `facet_wrap()` would put axes beside
empty panels (ggplot2 warns and drops them), free scales with a fixed
coord or free space with an aspect ratio (ggplot2 aborts), `panel.widths`/
`panel.heights`, and facets with `coord_flip()` and the other coords
(`full_decline()`; their layout is mirrored and checked).
<!-- SECTION:FINAL_SUMMARY:END -->
