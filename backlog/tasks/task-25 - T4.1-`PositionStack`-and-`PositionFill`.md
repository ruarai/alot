---
id: TASK-25
title: T4.1 `PositionStack` and `PositionFill`
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - positions
  - deferred
milestone: m-0
dependencies:
  - TASK-4
documentation:
  - doc-2
priority: low
ordinal: 10240
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.4
- **Touches:** `alot-core/src/position/stack.rs`, `R/kernels-position.R`
  (new)
- **Do:** Port `collide` (grouping by `xmin`, ordering by `group`,
  `reverse`) and `pos_stack` / `pos_fill`: `vjust`, separate stacking of
  negative values, and NA handling. Support `ymax`-only and `y`-only data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the shared criteria hold. The 400-panel histogram benchmark shows the `collide` share gone.
<!-- AC:END -->
