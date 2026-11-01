---
id: TASK-56
title: R6.1 Core geoms
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-53
documentation:
  - doc-3
ordinal: 10550
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R5.1
- **Do:** Mirror `draw_panel`/`draw_group` for line, path, step, col/bar,
  rect, tile and text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 each passes `expect_render_close()` across its corpus plots.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws `geom_line()`, `geom_path()`,
`geom_step()`, `geom_rect()`, `geom_tile()`, `geom_bar()`, `geom_col()`
and `geom_text()` (`full_geoms()`, R/render-full.R), in layer order
between the grid and the border. `alot-core/src/render/layers.rs` has
`RectLayer`, `PathLayer` and `TextLayer` (with `PointLayer`, in the
`Layer` enum of `panel.rs`); R prepares each layer as the hybrid
drawers do (`full_rects()`, `full_paths()`, `full_text()`), with the rows
of each panel dealt out in Rust. Text is clipped to the panel's clip box
as ragg clips it (`Painter::text_clip_box()`). The hybrid tier gained
`geom_step()` (`step_data()` stairsteps, then the path drawer); text
stays with ggplot2 there, as ragg draws a few text grobs faster than a
raster per grob (R2.2). Declines: arrows, aesthetics varying along a
line, non-solid rect line types, `check_overlap`, `parse`, labels that
are not character or factor, fonts or glyphs alot doesn't mirror, `polygon`
(hybrid only). Legends for these geoms still decline (R6.4: only
`draw_key_point()` is drawn). The Phase 1 corpus plots with these geoms
nearly all have legends or other parts the full tier doesn't draw yet,
so they run through the hybrid tier; `test-render-geoms.R` covers the
full tier.
<!-- SECTION:FINAL_SUMMARY:END -->
