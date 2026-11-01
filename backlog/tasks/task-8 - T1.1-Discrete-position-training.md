---
id: TASK-8
title: T1.1 Discrete position training
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - position-scales
milestone: m-0
dependencies:
  - TASK-3
documentation:
  - doc-2
ordinal: 10070
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.3
- **Touches:** `R/kernels-scale.R`, `alot-core/src/scale/discrete.rs` (new),
  `alot-r/src/lib.rs`, `tests/testthat/test-scale-train.R`
- **Do:**
  - For `ScaleDiscretePosition` with a `DiscreteRange`, Rust returns the
    distinct values per scale id in O(n), from factor codes, strings or
    logicals.
  - R merges them with the existing range the way `scales:::discrete_range`
    does: `sort()` stays in R, `drop`/`na.rm` are respected, and factor level
    order is kept.
  - Also cover `range_c`, the continuous range for continuous values plotted
    on a discrete scale.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold, including mixed factor and character input across layers and locale-sensitive strings.
<!-- AC:END -->
