---
id: TASK-13
title: T2.3 Continuous colour/fill mapping
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - non-position-scales
milestone: m-0
dependencies:
  - TASK-11
  - TASK-12
  - TASK-3
documentation:
  - doc-2
ordinal: 10120
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T2.1, T2.2, T0.3
- **Touches:** `R/kernels-npscale.R` (new), `alot-core/src/colour/ramp.rs`
- **Do:**
  - Train with the continuous range kernel.
  - Map: `rescale`, then a Rust `colour_ramp` interpolation over a palette
    whose colours R samples (O(k)). Then `oob` and `na.value`.
  - Support the gradient, gradient2 (`rescale_mid`), gradientn, distiller and viridis
    scales. Detect them by the scale's palette and rescaler and fall back for
    anything custom.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold. Benchmark target: the `map_df` share of the continuous-colour `geom_point` case.
<!-- AC:END -->
