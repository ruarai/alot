---
id: TASK-47
title: R2.1 Font resolution and metrics
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - text
milestone: m-1
dependencies:
  - TASK-39
documentation:
  - doc-3
ordinal: 10460
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** R0.2
- **Touches:** `R/render-text.R`, `alot-core/src/render/text.rs`
- **Do:** Resolve family and face to font files in R with
  `systemfonts::match_fonts()`, once per distinct style. In Rust, load the
  fonts with `ttf-parser` and shape with `rustybuzz`. Mirror
  `textshaping`/ragg string width, ascent and descent, and grid's fontsize ×
  lineheight rules for multi-line text.
  Check that every glyph exists in the resolved font; if any is missing,
  the plot goes to the hybrid tier (ragg's font fallback isn't mirrored).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 widths are within 0.25 px and heights match grid's `stringWidth()`/`stringHeight()` on a ragg device, across theme fonts, sizes and dpis. Text with missing glyphs (CJK labels with a Latin font, emoji) reports the hybrid tier.
<!-- AC:END -->
