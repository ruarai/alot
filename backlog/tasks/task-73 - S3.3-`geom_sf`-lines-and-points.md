---
id: TASK-73
title: S3.3 `geom_sf()` lines and points
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T05:13:00Z'
labels:
  - sf-render
milestone: m-2
dependencies:
  - TASK-72
documentation:
  - doc-4
ordinal: 700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S3.2
- **Touches:** `R/render-sf.R`, `tests/testthat/test-render-sf.R`
- **Do:** (MULTI)LINESTRING as `polylineGrob()` and (MULTI)POINT through
  the point sprites, with `sf_grob()`'s size, stroke and `pch`
  arithmetic, in mixed-type layers too (one display item per type run, in
  data order).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the remaining `geom_sf()` corpus plots that don't need GEOMETRYCOLLECTION render through the hybrid tier and match ragg.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
geom_sf() (MULTI)LINESTRING and (MULTI)POINT features, alone or mixed with polygons, draw in Rust in the hybrid tier: polylines through the path drawer, points through the point sprites with GeomSf$draw_panel's gpar (alpha(colour, alpha), fill_alpha(fill, alpha), fontsize = size * .pt + stroke, lwd = stroke) and the layer's lineend/linejoin/linemitre, which point sprites now take per batch (SymbolStyle). Features draw in data order, one display item per run of point or path features. The render-side sfc reader also reads integer coordinates. 34 of the 40 sf-layer render-corpus plots go through the hybrid tier; the other 6 decline for default_crs (3), arrows (2) and GEOMETRYCOLLECTION (1). Draw stage 6.6x (1e6-vertex lines) and 7.2x (1e5 points) faster than ragg.
<!-- SECTION:FINAL_SUMMARY:END -->
