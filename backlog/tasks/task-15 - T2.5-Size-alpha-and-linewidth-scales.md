---
id: TASK-15
title: T2.5 Size, alpha and linewidth scales
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - non-position-scales
  - deferred
milestone: m-0
dependencies:
  - TASK-11
  - TASK-3
documentation:
  - doc-2
priority: low
ordinal: 10140
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T2.1, T0.3
- **Touches:** `R/kernels-npscale.R`, `alot-core/src/scale/map.rs`
- **Do:** Add `rescale` with `area_pal` / `rescale_pal` for continuous size,
  alpha and linewidth. `scale_radius` and `scale_size_area` go through the
  same path when their palettes are recognised.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the shared criteria hold.
<!-- AC:END -->
