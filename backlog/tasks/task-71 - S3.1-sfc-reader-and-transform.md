---
id: TASK-71
title: S3.1 sfc reader and transform
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - sf-render
milestone: m-2
dependencies:
  - TASK-65
documentation:
  - doc-4
ordinal: 500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S0.1
- **Touches:** `alot-r/src/sf.rs`, `alot-core/src/sf/`
- **Do:** Walk an sfc in one pass into the flat `Geometry` struct
  (coordinates; ring, part and feature offsets; kind), borrowing each
  matrix. Decline anything other than XY, GEOMETRYCOLLECTION, and empty
  features. Mirror `CoordSf$transform` → `sf_rescale01()`
  (`st_normalize()`, with `reverse`) and the npc → device-pixel step.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `cargo test` covers each type and the declines, and an R test shows the rescaled coordinates equal `sf_rescale01()`'s (`st_coordinates()` of the result) to 1e-12.
<!-- AC:END -->
