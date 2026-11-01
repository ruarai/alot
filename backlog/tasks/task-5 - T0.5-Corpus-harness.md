---
id: TASK-5
title: T0.5 Corpus harness
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
ordinal: 10040
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** —
- **Touches:** `tests/testthat/test-corpus.R`, `tools/extract-corpus.R`
  (new), `tests/testthat/corpus/` (generated), `tests/testthat/corpus-allow.R`
- **Do:** Write a script that parses `../ggplot2/man/*.Rd` examples and
  `../ggplot2/tests/testthat/*.R`. It keeps every expression that evaluates
  to a ggplot (with its setup code) and writes them out as corpus files. The
  test runs `expect_build_equal()` on each. Keep an allow-list with a reason
  per entry (missing package, intentionally errors, …). Skip on CRAN.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the corpus runs green against the current build mirror and the count of plots run vs allow-listed is printed. Regenerating the corpus is a single command.
<!-- AC:END -->
