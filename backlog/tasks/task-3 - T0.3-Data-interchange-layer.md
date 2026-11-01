---
id: TASK-3
title: T0.3 Data interchange layer
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - infrastructure
milestone: m-0
dependencies:
  - TASK-1
documentation:
  - doc-2
ordinal: 10020
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.1
- **Touches:** `alot-r/src/convert.rs` (new), `R/convert.R` (new),
  `tests/testthat/test-convert.R`
- **Do:**
  - Borrowed column views: `&[f64]`, `&[i32]` (`NA_integer_` becomes
    `None`), and logical.
  - A factor type made of codes plus a levels `Strings`. Strings stay as
    `Strings`.
  - A builder that returns a named list of columns.
  - R helper `rebuild_frame(cols, template)`: `data_frame0()` in the
    template's column order, then `merge_attrs()`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 round-trip tests pass for every column type ggplot2 layer data uses (`double`, `integer`, `logical`, `character`, `factor`, `mapped_discrete`, `Date`, `POSIXct`, and list columns passed through untouched). Benchmarks show no copy for numeric columns.
<!-- AC:END -->
