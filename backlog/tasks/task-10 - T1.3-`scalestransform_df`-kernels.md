---
id: TASK-10
title: T1.3 `scales$transform_df` kernels
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
ordinal: 10090
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.3
- **Touches:** `R/build.R`, `R/kernels-scale.R`,
  `alot-core/src/scale/transform.rs` (new)
- **Do:** Mirror `ScalesList$transform_df` with a per-scale dispatch. Add
  kernels for the `identity`, `log10`, `sqrt` and `reverse` transforms,
  identified by `transform$name`. Any other transform falls back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold. A dedicated test checks that Rust's `log10`/`sqrt` match R's bitwise on a dense grid including subnormals, 0, negatives and ±Inf, and that the `NaN produced` warning still appears.
<!-- AC:END -->
