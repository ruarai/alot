---
id: TASK-12
title: T2.2 farver-exact colour encoding
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:55:00Z'
labels:
  - non-position-scales
milestone: m-0
dependencies: []
documentation:
  - doc-2
ordinal: 10110
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `alot-core/src/colour/` (new: `lab.rs`, `hex.rs`)
- **Do:** Port farver's sRGB↔XYZ↔Lab conversions, white point and rounding
  and its hex encoding (including alpha) to Rust.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the hex strings are byte-identical to `farver::encode_colour(farver::convert_colour(...))` on a dense Lab grid and on random inputs (an R test calling the Rust function), and NA gives NA.
<!-- AC:END -->
