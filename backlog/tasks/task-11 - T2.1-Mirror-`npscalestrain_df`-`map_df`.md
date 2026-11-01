---
id: TASK-11
title: T2.1 Mirror `npscales$train_df` / `map_df`
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:55:00Z'
labels:
  - non-position-scales
milestone: m-0
dependencies: []
documentation:
  - doc-2
ordinal: 10100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `R/build.R`, `R/npscales.R` (new)
- **Do:** Mirror `ScalesList$train_df` and `ScalesList$map_df` with
  per-scale `dispatch("np_train", …)` / `dispatch("np_map", …)`. No kernels
  yet; everything falls back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the corpus passes and `alot_coverage()` lists the non-position scale steps.
<!-- AC:END -->
