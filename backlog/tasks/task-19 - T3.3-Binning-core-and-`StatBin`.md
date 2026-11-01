---
id: TASK-19
title: T3.3 Binning core and `StatBin`
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - stats
  - deferred
milestone: m-0
dependencies:
  - TASK-4
documentation:
  - doc-2
priority: low
ordinal: 10180
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/bin.rs`, `R/kernels-stat.R`
- **Do:**
  - Breaks stay in R: `compute_bins()` is O(bins) and runs once per layer.
    Pass the breaks and `closed` to Rust.
  - Port the 1e-8 fuzz and `bin_cut` assignment exactly.
  - Rust computes `count`, `density`, `ncount`, `ndensity`, `width` and
    `pad`, handling `weight`, NA and Inf.
  - Also handle the `breaks`, `boundary`, `center`, `bins` and `binwidth`
    paths (all decided in R).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the shared criteria hold, with a property test of random data and bin params against ggplot2 that includes values exactly on bin edges.
<!-- AC:END -->
