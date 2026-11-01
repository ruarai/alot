---
id: TASK-1
title: T0.1 Full rextendr scaffold
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:55:00Z'
labels:
  - infrastructure
milestone: m-0
dependencies: []
documentation:
  - doc-2
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `configure`, `configure.win`, `tools/config.R`,
  `tools/msrv.R`, `src/Makevars.in`, `src/Makevars.win.in`, `src/rust/`,
  `R/extendr-wrappers.R`, `.Rbuildignore`
- **Do:** Generate the scaffold with `rextendr::use_extendr()` in a scratch
  copy and port it into the repo. Keep the two-crate workspace and build with
  `-p alot-r`. Add the `document` binary so `rextendr::document()`
  regenerates the wrappers. Set `SystemRequirements` and the MSRV check.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `R CMD INSTALL .` works from a clean checkout, `rextendr::document()` regenerates `R/extendr-wrappers.R` without a diff, and the existing tests pass.
<!-- AC:END -->
