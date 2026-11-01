---
id: TASK-9
title: T1.2 `layout$map_position` mirror and kernels
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - position-scales
milestone: m-0
dependencies:
  - TASK-3
  - TASK-8
documentation:
  - doc-2
ordinal: 10080
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.3, T1.1
- **Touches:** `R/layout.R`, `R/build.R`, `R/kernels-scale.R`,
  `alot-core/src/scale/map.rs` (new)
- **Do:**
  - Mirror `Layout$map_position` and `scale_apply(method = "map")`, routing
    through `dispatch("scale_map", …)`.
  - Continuous kernel: `oob` (`censor`, `squish`, `squish_infinite`,
    `keep`), then `na.value`. Any other `oob` function falls back.
  - Discrete kernel: map to integer positions through the limits and tag the
    result `mapped_discrete`. Continuous input on a discrete scale passes
    through as ggplot2 does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold, including `mapped_discrete` class preservation and NA handling. Benchmark target: the `map_position` share of the discrete `geom_point` case.
<!-- AC:END -->
