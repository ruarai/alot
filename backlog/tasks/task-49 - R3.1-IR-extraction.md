---
id: TASK-49
title: R3.1 IR extraction
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - render-ir
milestone: m-1
dependencies:
  - TASK-42
documentation:
  - doc-3
ordinal: 10480
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R1.1
- **Touches:** `R/render-ir.R`, `alot-r/src/render.rs`,
  `alot-core/src/render/ir.rs`
- **Do:**
  - Convert a built plot into the IR: layer columns (borrowed),
    `panel_params`, the facet layout and strip labels, guide parameters
    from `plot@guides`, labels, and fonts.
  - Resolve theme elements once per plot, keyed by element name.
  - Detect support per layer, guide and element. Anything unsupported picks
    the hybrid tier or ggplot2, with the reason, for
    `alot_render_coverage()`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 extraction takes under 10 ms on the README plot and under 50 ms on 400 panels, and covers every corpus plot within scope.
<!-- AC:END -->
