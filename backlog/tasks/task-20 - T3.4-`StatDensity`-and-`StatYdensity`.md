---
id: TASK-20
title: T3.4 `StatDensity` and `StatYdensity`
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
ordinal: 10190
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/density.rs`
- **Do:**
  - Port `stats::density.default`: linear binning (`BinDist`), FFT
    convolution and `approx` onto `n` points.
  - Compute bandwidths `nrd0` and `nrd` in Rust. R computes any other
    bandwidth per group and passes it in, and those plots fall back until
    this is done.
  - Support the kernels R supports and `bounds` reflection.
  - For `StatYdensity`, add `scale`, `trim`, `drop` and `quantiles`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the shared criteria hold. FFT round-off (rustfft vs R's `fft`) stays within 1e-8 on the bench data.
<!-- AC:END -->
