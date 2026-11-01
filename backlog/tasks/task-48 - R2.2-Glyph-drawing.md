---
id: TASK-48
title: R2.2 Glyph drawing
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - text
milestone: m-1
dependencies:
  - TASK-47
  - TASK-45
documentation:
  - doc-3
ordinal: 10470
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R2.1, R1.4
- **Touches:** `alot-core/src/render/text.rs`
- **Do:** Draw text runs unhinted, from cached glyph coverage (per font,
  size and subpixel offset), with hjust, vjust and rotation. Unrotated text
  uses the cache; other angles use outlines. ragg's FreeType hinting is
  not mirrored, so glyph pixels differ slightly from ragg's.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 axis labels, rotated axis titles and multi-line titles pass `expect_render_close()` (text may get a documented looser tolerance).
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`draw_runs()` mirrors `GEText()` and ragg's `plot_text()`,
including its FreeType hinting, so text is pixel-identical to ragg on the
tested plots (the "unhinted" plan was dropped: mirroring the hinting was
the exact option). Hybrid integration (`hybrid_text()`) is opt-in with
`options(alot.hybrid_text = TRUE)` because it is slower than ragg's text
there (inst/bench/RESULTS.md); the full tier will draw text through Rust.
<!-- SECTION:FINAL_SUMMARY:END -->
