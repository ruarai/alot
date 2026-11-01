---
id: TASK-29
title: T5.2 Batched `labeling::extended` in Rust
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:55:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies: []
documentation:
  - doc-2
ordinal: 10280
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `alot-core/src/breaks/extended.rs`
- **Do:** Port `labeling::extended` with the same floating-point operation
  order and the default `Q`, `w` and `only.loose` settings. The batched
  entry point takes many `(dmin, dmax, m)` triples.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 outputs are identical to `labeling::extended` on about 1e5 random ranges, including degenerate, tiny, huge and negative ranges.
<!-- AC:END -->
