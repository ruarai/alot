---
id: TASK-27
title: T4.3 Measure jitter and nudge
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - positions
  - deferred
milestone: m-0
dependencies:
  - TASK-6
documentation:
  - doc-2
priority: low
ordinal: 10260
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.6
- **Do:** Profile both at 1e6 rows. If jitter clears the 1.25× rule, add a
  kernel that takes the `runif` draws from R (under `with_seed_null`) and does
  only the arithmetic in Rust. Otherwise record "no kernel" in `RESULTS.md`.
<!-- SECTION:DESCRIPTION:END -->
