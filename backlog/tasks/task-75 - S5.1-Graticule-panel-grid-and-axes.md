---
id: TASK-75
title: S5.1 Graticule, panel grid and axes
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - coord-sf-full-tier
milestone: m-2
dependencies:
  - TASK-74
documentation:
  - doc-4
ordinal: 900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S4.1
- **Touches:** `R/render-ir.R`, `R/render-full.R`, `R/panel-guides.R`,
  `alot-core/src/render/{panel,axis}.rs`
- **Do:** Carry `panel_params$graticule` (from `st_graticule()`, in R)
  in the IR. Mirror `CoordSf$render_bg` and `render_axis_*`
  (ggplot2 R/coord-sf.R): graticule lines as paths, and ticks and labels
  where they cross the panel edge. Non-plotmath labels (e.g.
  `label_axes`, or user labels that are strings) draw in full.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the `coord_sf()` corpus plots with string labels pass the layout and image checks in the full tier.
<!-- AC:END -->
