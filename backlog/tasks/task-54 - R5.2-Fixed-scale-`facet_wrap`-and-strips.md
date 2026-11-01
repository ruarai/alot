---
id: TASK-54
title: R5.2 Fixed-scale `facet_wrap` and strips
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - readme-vertical-slice
milestone: m-1
dependencies:
  - TASK-53
documentation:
  - doc-3
ordinal: 10530
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README plot entirely in the full tier, before any breadth. Each task
covers exactly what the plot needs, and declines (drops a tier) for
anything else.

- **Depends:** R5.1
- **Touches:** `alot-core/src/render/facet.rs`
- **Do:** Mirror `FacetWrap$draw_panels` for fixed scales: panel table,
  axes on outer panels, strips on top with `theme_grey()`'s strip elements,
  and panel spacing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 fixed-scale `facet_wrap` point plots pass layout and image checks.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`layout.rs` `WrapSpec` mirrors `FacetWrap$draw_panels()`:
`init_gtable()` (panel grid, `panel.spacing`, `respect` for an aspect
ratio), `attach_axes()` (axes on the outer panels, and beside empty slots
with `measure_axes()`'s zeroed sizes) and `attach_strips()` (strips on top,
inside), built with gtable's weave steps so the cell names and boxes equal
grid's. `page.rs` draws panels, then strips (clipped to the strip as
`strip.clip = "on"`), then axes, as their `z` orders them. R
(`layout_wrap()` in R/render-layout.R) gives the grid, spacing and
strips' text; points are dealt out to panels in Rust. Declines (hybrid
tier): free scales or space, `axes`/`axis.labels`, strips not on top and
inside, strips of more than one variable, blank strip text or text that is
not plain (NA labels, plotmath), strip text wider than its strip (ggplot2
clips it), and `facet_grid`. Facets with `coord_flip` etc. keep declining
in `full_decline()`.
<!-- SECTION:FINAL_SUMMARY:END -->
