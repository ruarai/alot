---
id: TASK-36
title: R6.3 Keep faceted step and ECDF expansion within each panel
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - breadth
milestone: m-1
dependencies:
  - TASK-56
  - TASK-58
  - TASK-62
documentation:
  - doc-3
type: bug
ordinal: 100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R6.1, R6.3, R7.1
- **Touches:** `R/render.R` (`step_data()`, `draw_paths_layer()`),
  `R/render-full.R` (`full_paths()`), `tests/testthat/test-render-geoms.R`
- **Problem:**
  `step_data()` applies `stairstep()` by `group` across an entire layer.
  Facets reuse group IDs, so expanded paths acquire values from other panels.
  Both the full and hybrid tiers are affected, including `stat_ecdf()`.
  Fuzz campaign found 12 step and seven ECDF image failures; the largest
  differed on 14.1484% of pixels.
- **Do:** Mirror the panel-local invocation of `GeomStep$draw_panel()`
  (`ggplot2 R/geom-path.R`): expand each panel's groups independently in the
  shared helper, retaining panel/group order, aesthetics and attributes.
  Preserve `hv`, `vh` and `mid`, flipped orientation, and ggplot2's handling
  of missing values and groups with fewer than two rows. Verify that both
  `full_paths()` and `draw_paths_layer()` use the corrected expansion.
- **Regression coverage:** compare expanded data against ggplot2's per-panel
  step expansion, using repeated group IDs and clearly separated y ranges
  across panels. Check `geom_step()` and `stat_ecdf()` images in both tiers;
  include wrap/grid facets, fixed/free scales, multiple groups, all three
  directions, flipped orientation, NA and singleton groups. Assert the
  expected accelerated tier and absence of internal fallback warnings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the reproducer and targeted build/layout/image checks pass at the existing tolerances in both tiers; add faceted step and ECDF plots to the rendering corpus. Run the shared Phase 2 checks, Rust and R suites, a relevant build-corpus subset and the full render corpus.
<!-- AC:END -->
