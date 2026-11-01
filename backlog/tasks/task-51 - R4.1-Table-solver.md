---
id: TASK-51
title: R4.1 Table solver
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - layout
milestone: m-1
dependencies:
  - TASK-47
  - TASK-49
documentation:
  - doc-3
ordinal: 10500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R2.1, R3.1
- **Touches:** `alot-core/src/render/layout.rs`
- **Do:** Build a gtable-like row and column solver over absolute, `null`,
  summed and text-measured units, with margins, mirroring
  `ggplot_gtable()`'s `plot_table` assembly and title, subtitle, caption
  and tag placement (`plot.title.position`, `plot.caption.position`, tag
  positions). Add the debug box export.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the layout export matches grid within 0.5 px for every single-panel corpus plot.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`layout.rs` has the table (gtable's add rows, columns, padding
and grobs), grid's `calcViewportLayout()` and the single-panel plot
table (`FacetNull`, axis titles, legends, title, subtitle, caption, tag,
margin, background). Text-measured units are `titleGrob()` sizes from
`text_metrics()`, and axis sizes follow `GuideAxis$measure_grobs()` (tick
length plus label grobs, `angle`, `n.dodge`, minor ticks).
`layout_boxes_rust()` is the debug export; every single-panel render
corpus plot matches grid's boxes (`test-render-corpus.R`).
Facets with more than one panel decline ("more than one panel"; R5.2, R6.x).
Legend boxes are inputs: the corpus test takes their sizes from grid until
the legend layout lands in R5.
<!-- SECTION:FINAL_SUMMARY:END -->
