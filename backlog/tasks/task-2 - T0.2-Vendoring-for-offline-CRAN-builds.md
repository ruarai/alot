---
id: TASK-2
title: T0.2 Vendoring for offline / CRAN builds
status: To Do
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - infrastructure
  - deferred
milestone: m-0
dependencies:
  - TASK-1
documentation:
  - doc-2
priority: low
ordinal: 10010
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T0.1
- **Touches:** `src/rust/vendor.tar.xz`, `src/rust/vendor-config.toml`,
  `inst/AUTHORS`, `LICENSE.note`, `tools/config.R`
- **Do:** Run `rextendr::vendor_pkgs()` and make the build use the vendored
  crates when `NOT_CRAN` is unset. List vendored crate authors and licences.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `R CMD build` followed by `R CMD check --as-cran` with networking disabled passes, with no NOTE about crate licences.
<!-- AC:END -->
