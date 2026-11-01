---
id: TASK-55
title: R5.3 Colourbar and point legend
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - readme-vertical-slice
  - partial
milestone: m-1
dependencies:
  - TASK-53
  - TASK-51
documentation:
  - doc-3
ordinal: 10540
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README plot entirely in the full tier, before any breadth. Each task
covers exactly what the plot needs, and declines (drops a tier) for
anything else.

- **Depends:** R5.1, R4.1
- **Touches:** `alot-core/src/render/{legend,keys}.rs`
- **Do:** Mirror guide assembly for the right-hand legend box with two
  guides: `guide_colourbar` (bar raster or rects, ticks, labels) and
  `guide_legend` with `draw_key_point` keys. Cover titles, spacing and box
  stacking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the README plot renders in the full tier, passes layout and image checks, and meets both PHASE2.md targets.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The legends are done, and with R5.2 the README plot renders
in the full tier within 4/255 of ragg and passes the layout check at 1600
× 1000 / 150 dpi and 2100 × 2100 / 300 dpi. The speed targets are not met
(inst/bench/RESULTS.md, R5.2): 146 ms against < 120 ms, 47 ms against
< 25 ms for 10 rows, 222 ms against < 200 ms for the default page; R7.2's
performance pass is where they go. `R/render-legend.R` resolves each guide with ggplot2's own
`setup_params()` and `setup_elements()` (so guide `theme`, `legend.*`
theme elements and `rel()` sizes resolve as ggplot2 does) and measures its
text; `alot-core/src/render/legend.rs` does `measure_grobs()`,
`arrange_layout()`, `assemble_drawing()`, `Guide$add_title()` and
`package_box()` on `layout::Table`, and draws background, title, keys and
labels in gtable's order. `guide_legend()` with `draw_key_point()` keys
(`nrow`, `ncol`, `byrow`, `reverse`, `override.aes`, title and text
positions, merged legends) and raster `guide_colourbar()` (both
directions; `page.rs` `bar_image()` is ragg's bilinear raster span, within
1/255 of ragg) at the right, left, top and bottom, one box per position
with `legend.box`, `legend.box.just`, `legend.justification`, spacing and
`legend.location`. The layout takes the legend boxes' sizes from the same
code, so `layout_boxes_rust()` needs no sizes from grid for these plots
(`expect_layout_matches()` checks them). Declined (drop to the hybrid
tier): `inside` legends, other guides (coloursteps, bins), keys other than
`draw_key_point()`, colourbars that are not rasters or have `angle`, a
non-zero `legend.box.margin`, a drawn `legend.box.background`,
`legend.key.justification`, stretched (`null`) sizes, and labels that are
not plain text (including NA).
<!-- SECTION:FINAL_SUMMARY:END -->
