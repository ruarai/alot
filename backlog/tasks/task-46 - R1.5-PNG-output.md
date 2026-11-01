---
id: TASK-46
title: R1.5 PNG output
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - raster-engine
milestone: m-1
dependencies:
  - TASK-42
documentation:
  - doc-3
ordinal: 10450
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R1.1
- **Touches:** `alot-core/src/render/png.rs`
- **Do:** Move the prototype's encoder over and make it stream: take bands
  in row order as R1.1 finishes them. Choosing RGB or RGBA needs to know
  whether the page is opaque before the first row; decide it from the
  background and the display list (`bg = "transparent"` gives RGBA). Add
  ragg's `pHYs` chunk from `dpi`. Measure fdeflate's fast mode against
  parallel deflate on large pages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the files decode to the canvas exactly, carry the same metadata as ragg's, and encode the README page in about 20 ms or less.
<!-- AC:END -->
