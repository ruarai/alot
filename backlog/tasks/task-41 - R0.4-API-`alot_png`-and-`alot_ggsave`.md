---
id: TASK-41
title: 'R0.4 API: `alot_png()` and `alot_ggsave()`'
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - foundations
milestone: m-1
dependencies:
  - TASK-38
documentation:
  - doc-3
ordinal: 10400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R0.1
- **Touches:** `R/render.R`, `R/ggsave.R`, `tests/testthat/test-render.R`
- **Do:**
  - Give `alot_png()` `ggsave()`'s names and defaults (`width = 7`,
    `height = 7`, `units`, `dpi = 300`, `bg`, `scaling`), as in PHASE2.md's
    User API.
  - Add `alot_ggsave()` with `ggplot2::ggsave()`'s signature (mirror
    ggplot2 R/save.R for sizes and units). `.png` files go through
    `alot_png()`; anything else is passed to `ggsave()` unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `alot_ggsave()` gives the same file size, dimensions and `pHYs` as `ggsave(device = ragg::agg_png)` for PNGs, passes other formats through, and both functions are documented.
<!-- AC:END -->
