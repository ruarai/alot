---
id: TASK-65
title: S0.1 sf environment and corpus
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - foundations
milestone: m-2
dependencies: []
documentation:
  - doc-4
ordinal: 10680
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `DESCRIPTION`, `AGENTS.md`, `tests/testthat/helper-*.R`,
  `tests/testthat/corpus/`, `tests/testthat/render-corpus` files
- **Do:** Install `libgdal-dev`, `libgeos-dev` and `libproj-dev` (apt) and
  sf (CRAN). Add sf to Suggests. Add the install line to AGENTS.md's
  commands. Regenerate the corpus with `tools/extract-corpus.R` so it
  picks up ggplot2's sf examples and tests. Corpus files that use sf get a
  `skip_if_not_installed("sf")` guard. Record which new plots pass and
  which fall back today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the full R suite passes with sf installed and with it absent (the sf files skip), and the new corpus plots pass through the ggplot2 fallback.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sf 1.1.3 (GEOS 3.10.2, GDAL 3.4.1, PROJ 8.2.1). The corpus
gains 57 plots in 4 new files (`man-ggsf.R` 5, `man-stat_sf_coordinates.R`
2, `test-coord_sf.R` 29, `test-geom-sf.R` 17) plus the `coord_sf()` plot
in `test-guides.R` ("exotic coords" #3; the `coord_polar()` plot there
is now #4). `tools/extract-corpus.R` prepends
`skip_if_not_installed("sf")` to every block that uses sf (`uses_sf()`),
since Rd examples' `if (requireNamespace("sf"))` is unrolled; this also
makes the whole "exotic coords" block skip without sf. The `test-*`
blocks already carry upstream's guard. No other corpus file changed;
`_dropped.tsv` loses its 35 sf rows. `tools/render-corpus.R` adds 5
sf plots that are in Phase 2 scope (cartesian coord, in-scope geoms).
- **Build (`test-corpus.R`):** all 57 pass. 53 equal ggplot2's build;
  for 4 ggplot2 errors and alot raises the same error (`test-coord_sf.R`
  "axis labels can be set manually" #3, #4, "default crs works" #2;
  `test-geom-sf.R` "geom_sf data type renders appropriate legends" #1).
  Everything sf-specific falls back to ggplot2 today: `StatSf` (41
  plots), `StatSfCoordinates` (5), `CoordSf` `setup_panel_params` and
  `setup_panel_guides` (44), plus `FacetNull` and the positions as
  elsewhere. Only position scale train/map (and non-position scales
  where present) run in Rust. Targets for S2.1: the 44 `CoordSf` plots
  and the 41 `StatSf` plots.
- **Render:** the 5 render-corpus plots (`stat_sf_coordinates.Rd` #1,
  #2; `test-geom-sf.R` "geom_sf() removes rows containing missing aes"
  #1, "geom_sf_text() and geom_sf_label() draws correctly" #1, #2) and
  "exotic coords" #1, #2 are drawn in the full tier and pass
  `expect_render_close()`. All `CoordSf`/`GeomSf` plots (45 that build)
  are outside PHASE2.md's scope and go to ggplot2 ("no Rust drawer for
  this geom", "coord not in Phase 2 scope", plus plotmath degree
  labels in 21 and sf legend keys in 6). Known issue for S3.x/S5.x:
  for `coord_sf()` with `breaks = NULL` on both axes ("graticule lines
  and axes can be removed via scales" #1, "coord_sf() can render with
  empty graticules" #1), `render_ir()` calls the `CoordSf` view scale's
  `break_positions()`, which aborts "Not implemented.", so
  `alot_render_coverage()` errors and `alot_png()` warns "alot's full
  renderer failed" before falling back. Neither plot is in the render
  corpus.
- **sf absent:** checked with a library path that hides sf
  (`R_LIBS_USER` pointing at symlinks to every user package except sf):
  the 28 sf blocks skip in `test-corpus.R` and the 4 sf blocks skip in
  `test-render-corpus.R`; no other test file or R file uses sf.
<!-- SECTION:FINAL_SUMMARY:END -->
