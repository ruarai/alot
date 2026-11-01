---
id: TASK-22
title: 'T3.6 `StatSummary`: `mean_se` and `median_hilow`'
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - stats
  - deferred
milestone: m-0
dependencies:
  - TASK-4
documentation:
  - doc-2
priority: low
ordinal: 10210
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Do:** Identify `fun.data` by identity with
  `ggplot2::mean_se`/`median_hilow`. Reproduce R's two-pass long-double
  `mean()`; `f128`/`twofloat` emulation may be needed, so check whether
  `f64` already stays within 1e-8. Any other `fun` falls back.
<!-- SECTION:DESCRIPTION:END -->
