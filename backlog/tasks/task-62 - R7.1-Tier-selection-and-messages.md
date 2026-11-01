---
id: TASK-62
title: R7.1 Tier selection and messages
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - integration
milestone: m-1
dependencies:
  - TASK-55
documentation:
  - doc-3
ordinal: 10650
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R5.3
- **Do:** Finalise automatic tier choice, the one-time message when a plot
  drops below the full tier, and warn-and-fall-back on internal errors.
  Make sure the hybrid tier covers every layer that has a full-tier
  drawer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 every corpus plot renders through some tier, and `alot_render_coverage()` explains each one that isn't full.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`alot_render_coverage()` now decides the full tier as
`full_decline()`/`page_spec()` do (`full_support()`, R/render-full.R):
layers without rows and `geom_blank()` no longer keep a plot out of it
(they draw nothing, and `full_decline()` already ignored them, so plots
such as test-facet-.R "facets split up the data #7" were reported as
hybrid but drawn in full), and with `options(alot.full_tier = FALSE)` its
`full` table names the option. `render_raster()` tries full, then hybrid,
then ggplot2: an internal error in a tier warns (`alot_render_fallback`)
and drops to the next, and the first plot of a session to drop below the
full tier gets a message with the tier and the full tier's reason
(`alot_render_below_full`). The hybrid tier gains a "marks" drawer
(`draw_marks_layer()`, R/render.R): a lazy grob per panel that builds the
layer's full-tier specs at the device's resolution (`full_layer_specs()`,
split out of `full_layers()`) and draws one panel of them in Rust
(`rs_render_panel_layers()`, the full tier's `Panel::draw()` without
background, grid or border). It draws every full-tier geom without a
hybrid drawer of its own (ribbons, areas, densities, smooths, boxplots,
violins, the range geoms, segments, reference lines, rugs) and, for all
of them and points, rects, paths and polygons, `coord_flip()` and (points)
`coord_transform()`; its checks are the full tier's (`marks_decline()`),
so coverage and drawing agree. Text and labels stay with ggplot2 in the
hybrid tier (R6.1). The render corpus now draws each plot in the tier
`alot_render_coverage()` reports (full tier on; `ALOT_RENDER_HYBRID=1`
keeps it off), and fails a plot not drawn in full without a reason: the
default sample draws 195 plots in full, 7 hybrid and 6 with ggplot2, all
passing; with the full tier off, the 211 plots of the 22 ribbon, smooth,
boxplot, violin, range, segment, rug and coord files draw 191 hybrid and
match ragg. `test-render-tiers.R` covers coverage, the message, the
error fallbacks and the marks drawer. At 300 dpi the marks drawer is
faster than ggplot2 + ragg (render step, release build: a 2e5-row ribbon
0.40 s vs 0.49 s, 1e6-row boxplots 0.13 s vs 0.44 s, 5e4 segments 0.19 s
vs 0.27 s; ragg's time includes its PNG encoding).

**Follow-up (full-corpus fixes):** Tags in the plot or panel area are
now drawn at `table_add_tag()`'s manual positions (left/right ones
decline: ggplot2 errors on them); `setup_panel_guides` declines before
`Guides$setup` when a scale's guide isn't the default, so a misplaced
guide warns once.
<!-- SECTION:FINAL_SUMMARY:END -->
