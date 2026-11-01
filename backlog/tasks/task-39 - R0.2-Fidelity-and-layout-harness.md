---
id: TASK-39
title: R0.2 Fidelity and layout harness
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - foundations
milestone: m-1
dependencies: []
documentation:
  - doc-3
ordinal: 10380
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `tests/testthat/helper-render.R`, `tools/render-corpus.R`,
  `tests/testthat/test-render-corpus.R`, `.Rbuildignore`
- **Do:**
  - `expect_render_close(p, ..., max = 32, share = 0.01, tier = "full")`
    draws `p` live with ggplot2 + `agg_capture()` and with alot in the given
    tier, and compares pixels. It fails if alot raised a fallback warning
    or used a different tier. On failure it writes reference, result and
    diff images to a temp directory and prints the path. No reference
    images are stored.
  - A layout export: walk the gtable on a ragg device and record each
    named grob's box in device pixels via `deviceLoc()`. Compare it with
    the Rust layout's debug export (used from R4.1).
  - A render corpus: a subset of the Phase 1 corpus within PHASE2.md's
    scope, drawn at a small size so live references stay fast, and
    filtered by `ALOT_RENDER_CORPUS` like `ALOT_CORPUS`.
  - Fetch the ragg 1.5.2 and R sources to `../ragg` and `../r-source`, and
    note them in AGENTS.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the harness runs on the hybrid tier over the render corpus. Plots whose layers the hybrid supports pass; the rest are reported as fallbacks.
<!-- AC:END -->
