---
id: TASK-35
title: T6.2 Overhead around the position scale kernels
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - remaining-per-row-steps
milestone: m-0
dependencies:
  - TASK-8
  - TASK-9
documentation:
  - doc-2
ordinal: 10340
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T1.1, T1.2
- **Touches:** `R/kernels-scale.R`, `R/layout.R`, `R/convert.R`
- **Do:**
  - On the README example plot (1e6 rows, `facet_wrap`, log x, continuous
    colour, discrete shape), the position train and map steps take about
    100 ms (45% of the build, 2026-10-30). That is with kernels on:
    `train_position_1/_2` 28 + 27 ms and `map_position_1/_2` 24 + 21 ms.
  - Profile these steps (e.g. `Rprof` or `profvis` around
    `alot:::step_times(p)`). Split the time into Rust compute and the R work
    around each call: column conversion, per-panel and per-scale splitting,
    `rebuild_frame()` and any copies.
  - Remove the overhead that profiling finds, e.g. by converting each
    column once per step instead of once per scale or panel.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the profile split is recorded in `RESULTS.md`, and any change keeps the shared criteria and makes these steps faster on the example plot.
<!-- AC:END -->
