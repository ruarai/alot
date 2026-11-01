---
id: TASK-76
title: S5.2 Degree labels
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - coord-sf-full-tier
milestone: m-2
dependencies:
  - TASK-75
documentation:
  - doc-4
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S5.1
- **Touches:** `R/render-text.R`, `alot-core/src/render/text.rs`
- **Do:** Draw the plotmath forms that `st_graticule()` and
  `CoordSf$fixup_graticule_labels` generate for degree labels (a number,
  `degree` and a hemisphere letter), laid out as plotmath does (R
  `src/main/plotmath.c`). Any other expression still sends the plot to the
  hybrid tier.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the default-labelled `coord_sf()` corpus plots, and the north star, render in the full tier and match ragg.
<!-- AC:END -->
