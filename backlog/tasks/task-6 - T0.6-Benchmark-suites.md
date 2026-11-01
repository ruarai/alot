---
id: TASK-6
title: T0.6 Benchmark suites
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:55:00Z'
labels:
  - infrastructure
milestone: m-0
dependencies: []
documentation:
  - doc-2
ordinal: 10050
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `inst/bench/row-scaling.R`, `inst/bench/facet-scaling.R`,
  `inst/bench/step-profile.R`, `inst/bench/RESULTS.md`
- **Do:**
  - Row-scaling suite: the eight plots in PLAN.md at 1e4, 1e6 and 1e7 rows.
  - Facet-scaling suite: the four many-facet plots at 25, 100, 400 and 1,600
    panels with 200 rows per panel.
  - Per-step timing: wrap `alot_build` steps with timers behind an option, or
    use `Rprof` aggregation, so each kernel's 1.25× check measures its own step.
  - Record the baseline numbers (ggplot2 vs current alot) in `RESULTS.md`
    with machine, R and ggplot2 versions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 one command per suite reproduces the tables in `RESULTS.md`.
<!-- AC:END -->
