---
id: TASK-66
title: S0.2 Spatial bench suite and profile
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - foundations
milestone: m-2
dependencies:
  - TASK-65
documentation:
  - doc-4
ordinal: 10690
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S0.1
- **Touches:** `inst/bench/spatial.R` (new), `inst/bench/RESULTS.md`
- **Do:** Add generators for rasters of 500², 1000² and 2000² cells
  (continuous fill, about 50% absent cells), sf layers of 1e2, 1e3 and 1e4
  polygon features at about 1e6 total vertices (in EPSG:3577 and in
  EPSG:4326), the north star and its faceted variant (SPATIAL.md). Add
  the opt-in real-data cases read from `ALOT_SPATIAL_DATA`. Time and
  `Rprof` each case's build, gtable and draw for ggplot2 + ragg and for
  alot's current path. Report the PROJ floor separately.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 RESULTS.md has the baseline table and the profile per stage. It lists which build steps are worth a kernel (S1.2, S2.2) and confirms the ≥5× north-star target, or records a revised one with the reason.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`inst/bench/spatial.R`; tables in RESULTS.md ("S0.2:
spatial baseline"). Today every spatial case takes the ggplot2 tier.
alot's end-to-end speedup is 1.5–2.1× on rasters ≥1000² (from
the build), 1.0× on sf, 1.72× on the north star (4,173 → 2,430 ms) and
1.31× on the faceted variant. PROJ is 1–2% of the north stars, 8–13% of
in-CRS sf plots (`CoordSf$setup_data` calls `st_transform()` even when
the CRS already matches: 100–200 ms per 1e6 vertices) and 47% when
reprojecting. Verdicts: S1.2 drop as specified (`GeomRaster$setup_data`
takes 19 ms at 1e6 rows, ~1% end to end; the raster build's remaining time
is existing-kernel overhead at 2e6 rows); S2.2 drop (per-feature steps
are ~2% at 1e4 features; the rest is sf's own transform and sfc restore).
The ≥5× target is kept for both north stars, but needs alot's raster build
cut from ~780 to ~500 ms in S4.1. Revised targets: ≥1.6× when sf layers
are reprojected (PROJ ceiling 2.2×), ≥3× for sf-only plots in their own
CRS. Open decision for S2.1: skipping the same-CRS `st_transform()`.
<!-- SECTION:FINAL_SUMMARY:END -->
