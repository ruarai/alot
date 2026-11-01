---
id: TASK-28
title: T5.1 Panel assignment for `layout$setup` / `map_data`
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies:
  - TASK-3
documentation:
  - doc-2
ordinal: 10270
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.3
- **Touches:** `R/layout.R`, `R/kernels-facet.R` (new),
  `alot-core/src/facet/join.rs`
- **Do:**
  - Mirror `Layout$setup` and dispatch `facet$map_data` for `FacetWrap` and
    `FacetGrid`.
  - Rust hash-joins rows to layout rows on the facet variables. R evaluates
    the facet expressions and handles `margins`, missing facet variables and
    expansion across panels.
  - Fall back for `margins = TRUE` at first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the shared criteria hold. Benchmark target: the 19% `layout$setup` share of `facet_wrap` + point.
<!-- AC:END -->
