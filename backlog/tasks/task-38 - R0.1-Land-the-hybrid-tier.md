---
id: TASK-38
title: R0.1 Land the hybrid tier
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
ordinal: 10370
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `R/render.R`, `alot-core/src/render/{points,png}.rs`,
  `alot-r/src/render.rs`, `tests/testthat/test-render.R`, `DESCRIPTION`,
  `AGENTS.md`
- **Do:** Rebase the prototype (`proto/phase2-points`) onto `main` as the
  hybrid tier. Rename internals to match the layout above. Add
  `alot_render_coverage()` (tier, plus per layer "rust" or "ggplot2" with a
  reason). Make `alot_png()` signal which tier ran. Keep the prototype's
  fallbacks (shapes, NA, coord, `clip`, device). Catch internal errors: warn
  once with the error and render with ggplot2. Move ragg to Imports as
  `ragg (>= 1.5.0, < 1.6.0)`, and add the ragg pin to AGENTS.md next to the
  ggplot2 pin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the README plot renders via the hybrid tier at the prototype's speed, and every fallback in `test-render.R` is reported by `alot_render_coverage()`.
<!-- AC:END -->
