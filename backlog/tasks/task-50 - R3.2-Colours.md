---
id: TASK-50
title: R3.2 Colours
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - render-ir
milestone: m-1
dependencies:
  - TASK-49
documentation:
  - doc-3
ordinal: 10490
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R3.1
- **Touches:** `alot-core/src/colour/`, `alot-r/src/render.rs`
- **Do:**
  - Parse colours in Rust: hex, R's named colours (the `colors()` table),
    and `NA` as transparent, with a CHARSXP cache.
  - Apply alpha as `scales::alpha()` and `fill_alpha()` do (farver's
    `double2int`).
  - Support numeric palette indices if ggplot2 can produce them, or decline
    them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 results equal `col2rgb(alpha(colour, a), alpha = TRUE)` on every colour R accepts, or decline.
<!-- AC:END -->
