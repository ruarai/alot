---
id: TASK-71
title: S3.1 sfc reader and transform
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T04:29:00Z'
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
- [x] #1 `cargo test` covers each type and the declines, and an R test shows the rescaled coordinates equal `sf_rescale01()`'s (`st_coordinates()` of the result) to 1e-12.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
alot-core sf::{Kind, Geometry, Builder, rescale01, to_device} (src/sf/geometry.rs) and alot-r sfc_geometry() (src/sf.rs), which extends the rs_sfc_plain_xy() walker to fill a flat Geometry in the same pass. rescale01() mirrors sf_rescale01()/st_normalize() bit for bit ((v + -min) * (1 / range), then -v + 1 for a reversed range) and returns false where st_normalize() errors (zero, negative or non-finite range). to_device() places npc in a panel cell as render/layers.rs does. Declines: GEOMETRYCOLLECTION and other types, empty features, XYZ/XYM/XYZM, non-finite or integer coordinates, any extra attribute (e.g. the matrix class sf arithmetic adds), empty sfc. cargo test covers every type and decline; test-sf-geometry.R checks rs_sf_rescale01() is identical to st_coordinates(sf_rescale01()) for every type, multiple features, mixed sfc_GEOMETRY, reversed ranges and real coord_sf() panel ranges.
<!-- SECTION:FINAL_SUMMARY:END -->
