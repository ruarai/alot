---
id: TASK-30
title: T5.3 Mirror `setup_panel_params` and deduplicate per axis
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies:
  - TASK-29
documentation:
  - doc-2
ordinal: 10290
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T5.2
- **Touches:** `R/layout.R`, `R/panel-params.R` (new)
- **Do:**
  - Mirror `Layout$setup_panel_params` and
    `CoordCartesian$setup_panel_params` (also covering `CoordFlip` and
    `CoordFixed`).
  - Build view scales once per distinct `SCALE_X` and `SCALE_Y`, using the
    batched breaks from T5.2 for major and minor breaks. Compute labels in R
    once per distinct break set.
  - Assemble per-panel params as clones.
  - Read ggproto methods and fields once per scale class.
  - Dispatch on coord class; any other coord falls back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `panel_params` are equal field by field (the existing harness check), including view-scale ggproto objects. Mutating one panel's objects does not affect another (test). The free-scale facet benchmarks improve.
<!-- AC:END -->
