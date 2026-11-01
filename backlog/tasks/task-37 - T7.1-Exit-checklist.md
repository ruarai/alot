---
id: TASK-37
title: T7.1 Exit checklist
status: To Do
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - phase-1-exit
  - deferred
milestone: m-0
dependencies:
  - TASK-2
documentation:
  - doc-2
priority: low
ordinal: 10360
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** everything above, including the deferred stats, positions and
  T0.2
- **Do:** Verify each criterion in "Phase 1 is done when" in PLAN.md:
  - the corpus is green and the allow-list is documented;
  - coverage shows Rust for every component in 1.1–1.5 on representative
    plots;
  - `RESULTS.md` meets the row-scaling and facet-scaling targets;
  - `R CMD check --as-cran` with vendored crates and `cargo test` both pass.
<!-- SECTION:DESCRIPTION:END -->
