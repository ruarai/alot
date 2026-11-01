---
id: TASK-24
title: T3.8 `StatSmooth` (`method = "lm"`)
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
ordinal: 10230
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All stat kernels use the grouped driver (T0.4) and register under
`dispatch("stat", …)`.

- **Depends:** T0.4
- **Touches:** `alot-core/src/stat/lm.rs`
- **Do:**
  - Householder QR least squares matching `lm.fit` (LINPACK `dqrdc2` pivoting
    tolerance), then prediction on `xseq` and standard errors.
  - R computes the `qt()` quantile and passes it in.
  - Support the formulas `y ~ x` and `y ~ poly(x, k)`; `poly` basis
    generation stays in R and Rust receives the design matrix. Anything else
    falls back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the shared criteria hold. The 1.25× rule applies to the stat step only.
<!-- AC:END -->
