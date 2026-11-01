---
id: TASK-17
title: T3.1 `StatIdentity` short-circuit
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
ordinal: 10160
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Do:** Return the data unchanged without splitting it. Check that
  ggplot2's `compute_layer` would not alter row order or attributes.
<!-- SECTION:DESCRIPTION:END -->
