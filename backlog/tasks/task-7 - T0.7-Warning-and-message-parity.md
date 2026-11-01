---
id: TASK-7
title: T0.7 Warning and message parity
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
ordinal: 10060
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `tests/testthat/test-warnings.R`, `helper-equivalence.R`
- **Do:** Extend `expect_build_equal()` (or add `expect_build_conditions_equal()`)
  so it captures warnings and messages from both builds and compares them.
  Add `expect_snapshot` cases for "Removed n rows", stat_bin's default-bins
  message, and so on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the corpus also checks condition parity.
<!-- AC:END -->
