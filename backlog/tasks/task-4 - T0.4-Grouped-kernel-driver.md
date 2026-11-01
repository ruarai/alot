---
id: TASK-4
title: T0.4 Grouped-kernel driver
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - infrastructure
milestone: m-0
dependencies:
  - TASK-3
documentation:
  - doc-2
ordinal: 10030
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.3
- **Touches:** `alot-core/src/group.rs` (new), `alot-r/src/lib.rs`,
  `R/grouped.R` (new)
- **Do:**
  - Build a group index over `PANEL` × `group` in one pass: offsets plus a
    row permutation, ordered as `dapply`/`split` would order them.
  - Write a generic `run_grouped(kernel, columns, index)` in `alot-core` that
    concatenates per-group outputs and carries the constant columns through,
    as `Stat$compute_panel` does with `uniquecols`.
  - Add an R wrapper used by stat and position kernels.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 a trivial identity-style kernel passed through the driver reproduces `Stat$compute_layer` output (rows, order, constant columns) for multi-panel, multi-group data, including groups with `group = -1`. A test pins the ordering against `dapply`.
<!-- AC:END -->
