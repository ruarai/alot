---
id: TASK-52
title: R4.2 Panel decorations and axes
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - layout
milestone: m-1
dependencies:
  - TASK-51
  - TASK-44
  - TASK-45
  - TASK-48
documentation:
  - doc-3
ordinal: 10510
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R4.1, R1.3, R1.4, R2.2
- **Touches:** `alot-core/src/render/{panel,axis}.rs`
- **Do:** Draw the panel background, major and minor grid lines and the
  border from theme elements. Mirror `guide_axis` drawing: ticks, labels,
  `angle`, `n.dodge`, `check.overlap`, minor ticks and axis lines, for
  positions bottom, left, top and right.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 blank-layer plots with `theme_grey()` pass `expect_render_close()` and the layout check.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`render-full.R` resolves the theme elements into a spec for
`rs_render_page()`, which solves the table (R4.1), draws the plot
background, the panel (`panel.rs`: background, grid lines, border, `clip`),
the axes (`axis.rs`: `GuideAxis$assemble_drawing()`'s gtable, line, major
and minor ticks, labels with `angle`, `n.dodge`, `check.overlap`) and the
title grobs (`title.rs`: axis titles, title, subtitle, caption, tag) into
one display list. Text becomes image items from R2.2's `draw_runs()`. Blank
layers (`geom_blank()`) only, `CoordCartesian`/`CoordFixed`, one panel, no
legends; other plots decline. `alot_png()` still doesn't use the tier
(`options(alot.full_tier = TRUE)` tries it first; R5.1 switches it on).
Every complete theme and the axis options pass `expect_render_close()` at
96 and 150 dpi with a largest pixel difference of 1 (of 255).
<!-- SECTION:FINAL_SUMMARY:END -->
