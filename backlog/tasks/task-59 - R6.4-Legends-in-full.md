---
id: TASK-59
title: R6.4 Legends in full
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-55
  - TASK-56
documentation:
  - doc-3
ordinal: 10580
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R5.3, R6.1
- **Do:** Add `draw_key_*` for every in-scope geom, `guide_coloursteps`,
  `guide_bins`, merged legends, `byrow`, `nrow` and `ncol`, all legend
  positions including inside, and `legend.box`/justification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 legend corpus plots pass layout and image checks.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The full tier draws the keys of every geom it draws:
`draw_key_point()`, `draw_key_polygon()` (rect, tile, bar, col),
`draw_key_rect()`, `draw_key_path()` (path, line, step),
`draw_key_timeseries()`, `draw_key_text()` and `draw_key_blank()`, also
through `key_glyph` (a layer's `key_glyph` geom child draws as its parent:
`drawn_geom()`, R/render.R), with `set_key_size()`'s sizes and
`legend.key.justification`. `guide_coloursteps()` and `guide_colourbar(display
= "rectangles")` draw their rects; `guide_bins()` draws its key stack, axis
line, ticks and labels (`legend_bins()`; `Body::Bins` in
alot-core/src/render/legend.rs). Inside legends (`legend.position =
"inside"` or a numeric position, `legend.position.inside`,
`legend.justification.inside`, per-guide positions and themes, several
inside boxes) are drawn over the panel area, and `legend.box.margin` and
`legend.box.background` (with grid's defaults for unset properties, the
device's background as fill) are placed as grid places the overflowing
`guide-box` layout (`LegendGroup::draw()`). NA legend labels draw as "NA",
as grid does. Merged legends, `byrow`, `nrow`/`ncol`, the outside
positions and `legend.box`/`legend.box.just`/justification were R5.3's.
`test-render-legend.R` has about 90 image + layout cases; with the full
tier forced on, the 478 plots of the 45 corpus files that gained full-tier
legends draw in full and match ragg, laid out as grid lays them out
(`ALOT_LAYOUT_ALL=1`). Over the render corpus, 1119 of 1663 plots now pass
the full tier's checks (974 before). Still declined (hybrid tier):
stretched (`null`) legend sizes or spacing, `guide_colourbar(display =
"gradient")`, label `angle`, plotmath labels, arrows in keys, rotated or
non-centred text keys, keys of functions alot doesn't mirror (custom
`draw_key`s, `draw_key_dotplot()` and the keys of geoms the full tier
doesn't draw yet, which come with R6.5), and guides other than legend,
colourbar, coloursteps and bins.
<!-- SECTION:FINAL_SUMMARY:END -->
