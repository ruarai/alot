---
id: TASK-18
title: T3.2 `StatCount`, `StatSum` and `StatUnique`
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
ordinal: 10170
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/count.rs`, `R/kernels-stat.R` (new)
- **Do:** Hash-based counting. Match ggplot2's output order exactly
  (`StatCount` sorts by x; `StatSum` and `StatUnique` follow `count()` /
  `unique()` semantics), along with `weight`, `width`, `flipped_aes` and the
  computed `prop`.
<!-- SECTION:DESCRIPTION:END -->
