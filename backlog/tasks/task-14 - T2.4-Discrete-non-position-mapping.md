---
id: TASK-14
title: T2.4 Discrete non-position mapping
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - non-position-scales
milestone: m-0
dependencies:
  - TASK-11
  - TASK-3
documentation:
  - doc-2
ordinal: 10130
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T2.1, T0.3
- **Touches:** `R/kernels-npscale.R`, `alot-core/src/scale/discrete.rs`
- **Do:**
  - Training reuses T1.1.
  - Map: R computes the palette for the limits (O(k)), handling named
    `values` in manual scales and `na.translate`. Rust looks each row up by
    hash in a single pass.
  - Cover the hue, brewer, manual, shape and linetype scales. The output type
    must match: character for colours, integer or character for shapes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold.
<!-- AC:END -->
