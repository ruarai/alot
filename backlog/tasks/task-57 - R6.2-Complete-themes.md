---
id: TASK-57
title: R6.2 Complete themes
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-52
documentation:
  - doc-3
ordinal: 10560
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R4.2
- **Do:** Cover every built-in complete theme, and the theme elements and
  options they use.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 blank and point plots pass in each theme.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Every complete theme (`theme_grey()`/`theme_gray()`,
`_bw`, `_linedraw`, `_light`, `_dark`, `_minimal`, `_classic`, `_void`,
`_test`) renders blank and point plots, with titles, a legend, a
colourbar and `facet_wrap()`, in the full tier and passes the image and
layout checks, as do their arguments (`base_size`, `base_family`,
`header_family`, `ink`, `paper`, `accent`, `base_line_size`,
`base_rect_size`; `test-render-themes.R`). Most of it already held after
R4.2–R5.3; what changed: element rects with dashed line types are drawn
(`Painter::rect()` hands them to the path drawer as ragg's `drawRect()`
builds the path, from grid's bottom-left corner, round ends);
`panel.ontop = TRUE` draws the background and grid over the layers
(`Coord$draw_panel()`; it drew them under, wrongly, once a panel had
layers); `lines` and `char` units are converted with the device's
default gpar wherever no grob sets one (`plot.margin`, `panel.spacing`,
tick lengths, legend sizes; `layout_px()`); `element_text(debug = TRUE)`
declines (it drew without the debug marks). Still declined (hybrid
tier): text margins in `lines`/`char` (titleGrob() sizes them in the
parent's gpar but places the text in its own), arrows on `axis.line`,
debug text, and `legend.box.background`/`legend.box.margin` (R6.4).
`test-internals.R` snapshots the complete themes and
`element_grob()` for rects and lines.
<!-- SECTION:FINAL_SUMMARY:END -->
