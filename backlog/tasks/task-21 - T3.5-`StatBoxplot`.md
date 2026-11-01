---
id: TASK-21
title: T3.5 `StatBoxplot`
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
ordinal: 10200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/boxplot.rs`
- **Do:** Port `quantile(type = 7)` exactly, `coef` outliers (returned as a
  list column), `notch`, `relvarwidth`, `width` and `flipped_aes`.
<!-- SECTION:DESCRIPTION:END -->
