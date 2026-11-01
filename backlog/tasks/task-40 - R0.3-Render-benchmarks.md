---
id: TASK-40
title: R0.3 Render benchmarks
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - foundations
milestone: m-1
dependencies:
  - TASK-38
documentation:
  - doc-3
ordinal: 10390
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R0.1
- **Touches:** `inst/bench/render-*.R`, `inst/bench/RESULTS.md`
- **Do:** Generalise the prototype's `render-readme.R` into a suite. It
  times each stage (build, IR, layout, raster, encode; or gtable and draw
  for ggplot2 and the hybrid), with interleaved runs, for these cases:
  - the README plot at 1600 × 1000 and 150 dpi, and at the default page
    (7 × 7 in, 300 dpi);
  - the README plot with 10 rows (fixed cost);
  - 1e6-row `geom_point`, no axes;
  - a 1000 × 1000 `geom_tile`;
  - a 1e6-point `geom_line`;
  - 400 small facet panels.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 baselines for ggplot2 + ragg and the hybrid are in `RESULTS.md`, and PHASE2.md has a target for the default page.
<!-- AC:END -->
