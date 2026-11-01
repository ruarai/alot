---
id: TASK-42
title: R1.1 Display list and band executor
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - raster-engine
milestone: m-1
dependencies:
  - TASK-38
documentation:
  - doc-3
ordinal: 10410
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R0.1
- **Touches:** `alot-core/src/render/{display,raster}.rs`
- **Do:**
  - Define the display-list items and clip stack in device pixels.
  - Build the executor: split the page into row bands, each with an f32
    premultiplied buffer reused across calls, so memory is bounded by band
    size. Each band walks the list in order, skipping items by y extent.
    Finished bands are handed over in row order for encoding (R1.5).
  - Set the thread count from `options(alot.threads)` or `ALOT_THREADS`,
    defaulting to the available cores capped at 8, and at 2 when
    `_R_CHECK_LIMIT_CORES_` is set.
  - Mirror ragg's clipping (`clip_box` at fractional panel edges) and
    background fill.
  - Move the prototype's point drawer onto it, so the hybrid's per-panel
    raster is a one-item display list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 a background plus a 1e6-point batch renders, matching the hybrid's pixels, and the blend scales with threads (record 1 vs 8). A 20 × 20 in page at 300 dpi renders within a memory bound set by the band size.
<!-- AC:END -->
