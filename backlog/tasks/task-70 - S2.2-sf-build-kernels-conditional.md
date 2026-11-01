---
id: TASK-70
title: S2.2 sf build kernels (conditional)
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - sf-build
  - dropped
milestone: m-2
dependencies:
  - TASK-69
  - TASK-66
documentation:
  - doc-4
ordinal: 10730
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** S2.1, S0.2
- **Touches:** `R/kernels-sf.R` (new), `alot-core/src/sf/` (new),
  `alot-r/src/sf.rs` (new)
- **Do:** Write a kernel only for the per-feature steps that S0.2's
  profile picks (candidates: the geometry-type scan in `LayerSf`, bboxes
  when the sfc's cached bbox can't be used). The sfc reader from
  SPATIAL.md lands here if S2.2 needs it, otherwise in S3.1. Any other
  candidate fails the 1.25× rule and is recorded in RESULTS.md.
- **S0.2 verdict:** drop. The per-feature steps are about 2% end to end at 1e4
  features. The build is dominated by `st_transform()` in
  `CoordSf$setup_data`, which stays in sf (see RESULTS.md, "S0.2: spatial
  baseline", including the open same-CRS question).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the Phase 1 criteria hold for each kept kernel.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
**Decision (2026-11-01):** Dropped, per the S0.2 verdict below.
<!-- SECTION:FINAL_SUMMARY:END -->
