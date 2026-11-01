---
id: TASK-67
title: S1.1 `geom_raster()` drawer
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - raster
milestone: m-2
dependencies:
  - TASK-66
documentation:
  - doc-4
ordinal: 10700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S0.2
- **Touches:** `R/render-raster.R` (new), `alot-core/src/render/raster.rs`,
  `alot-r/src/render.rs`, `tests/testthat/test-render-raster.R` (new),
  `tests/testthat/test-internals.R`
- **Do:** Mirror `GeomRaster$draw_panel` (ggplot2 R/geom-raster.R): the
  `x_pos` and `y_pos` cell indices from `resolution(x, FALSE)` with
  `as.integer()` truncation, an image built in Rust from the parsed fill
  colours (transparent for absent and NA cells), and the `rasterGrob()`
  placement over the xmin–xmax and ymin–ymax range. Draw it as ragg's
  `drawRaster()` does with `interpolate = FALSE` (ragg `src/AggDevice.h`,
  R `GERaster()`), starting from R5.3's `bar_image()`. Use it in the full
  tier (cartesian, `coord_fixed()`, `coord_flip()`, reversed and
  transformed scales, facets) and as a hybrid lazy grob.
- **Declines:** `interpolate = TRUE`, any alpha other than 0 or 1, pattern
  fills, non-linear coords (GeomRaster's `GeomRect` fallback),
  `annotation_raster()`, `coord_sf()` (S4.1).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the raster render-corpus plots draw in full and match ragg. The 1000² and 2000² cases draw faster than ragg, and the 2000² case's draw step is at least 5× faster than ragg's.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Full tier and hybrid ("marks" lazy grob). The matrix is
built per panel in Rust from the fill strings (CHARSXP-cached parse,
`resolution()` ported to Rust, last row wins a shared cell) and sampled
as AGG's `span_image_filter_rgba_nn` + `dda2_line_interpolator` over a
`scanline_u8` span with exact-area edge coverage. Under `coord_flip()`
the matrix stays unflipped and only its placement flips, as upstream.
All 11 raster render-corpus plots draw in full (max channel diff 1 in
spot checks); `coord_cartesian(reverse = )` and `clip = "off"` decline
too. Draw step (release, 7 × 7 in at 300 dpi): 1000² 14 vs 135 ms
(9.6×), 2000² 20–29 vs 170 ms (5.9–8.5×; RESULTS.md "S1.1").
<!-- SECTION:FINAL_SUMMARY:END -->
