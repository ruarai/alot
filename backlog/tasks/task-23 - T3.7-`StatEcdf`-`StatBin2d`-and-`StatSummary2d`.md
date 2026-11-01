---
id: TASK-23
title: T3.7 `StatEcdf`, `StatBin2d` and `StatSummary2d`
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - stats
  - deferred
milestone: m-0
dependencies:
  - TASK-19
documentation:
  - doc-2
priority: low
ordinal: 10220
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T3.3
- **Do:** Reuse the T3.3 binning core. `StatSummary2d` gets kernels only for
  `fun = mean` and `fun = sum`.
<!-- SECTION:DESCRIPTION:END -->
