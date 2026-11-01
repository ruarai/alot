---
id: TASK-34
title: T6.1 Re-profile and pick targets
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - remaining-per-row-steps
milestone: m-0
dependencies:
  - TASK-35
documentation:
  - doc-2
ordinal: 10330
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T6.2 and the non-deferred 1.1–1.5 kernels
- **Do:** Profile the bench suites with kernels in place. List
  `compute_geom_1`, `compute_geom_2`, `finish_statistics`,
  `layout$finish_data` and `.ignore_data`/`.expose_data` by share of build
  time. Open one task per step that could plausibly pass the 1.25× rule
  (as `T6.3`, `T6.4`, …, under 1.6, listed in the run order), and record
  the rest as "stays in R".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the ranked list is in `RESULTS.md`, and any new tasks are in the backlog and in the run order.
<!-- AC:END -->
