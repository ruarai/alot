---
id: TASK-33
title: T5.6 Facet variables without per-row `factor()`
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies:
  - TASK-28
documentation:
  - doc-2
ordinal: 200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T5.1
- **Touches:** `R/kernels-facet.R`, `tests/testthat/test-facet-map.R` (or
  the existing facet test file), `inst/bench/RESULTS.md`
- **Why:** `kernel_facet_map_data` turns each non-factor facet column into
  a factor with `gg_as_unordered_factor()` (ggplot2's
  `as_unordered_factor()`, R/utilities.R), i.e. `factor()` over every row.
  `factor()` calls `as.character()` on all n values to match them to the
  levels. On a 9.8e6-row `geom_raster()` + `facet_wrap(~c)` (10 distinct
  doubles in `c`), that is 4.3 s of `layout_setup`'s 4.6 s. The Rust panel
  assignment (`rs_facet_panels`) takes about 0.2 s.
- **Do:** Build the same factor while formatting only the unique values
  (O(k) work stays in R; AGENTS.md):
  `u <- unique(x); lab <- as.character(u); lev <- unique(lab[order(u)])`
  (levels as `factor()` picks them: sorted values, `NA` dropped), then
  codes `match(lab, lev)[match(x, u)]`, with `NA` where `factor()` gives
  `NA`. Set the levels and class as `as_unordered_factor()` does. Apply it
  to the data columns and the layout columns at
  `R/kernels-facet.R:228-242`. `match(x, u)` on doubles is hashed. If
  profiling shows it matters, it can move to Rust. Check whether
  `facet_combine_vars` / `rs_facet_distinct_rows` or the grid layout
  kernel have the same per-row `factor()` pattern, and fix them the same
  way.
- **Exactness:** the result must be `identical()` to `factor(x)` with the
  ordered class dropped. Cover `NA`, `NaN`, `-0` vs `0`, values that differ
  but format the same (e.g. `0.1 + 0.2` and `0.3` under `as.character()`),
  `Inf`, integer, double, character (locale sort stays in R), logical and
  Date columns, and a factor input (which must pass through untouched).
  Fall back to `gg_as_unordered_factor()` for any other class.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `expect_build_equal()` passes on facet_wrap and facet_grid plots with those columns, the facet corpus files pass, and the 9.8e6-row case above drops `layout_setup` to well under 0.5 s (record it in `RESULTS.md`).
<!-- AC:END -->
