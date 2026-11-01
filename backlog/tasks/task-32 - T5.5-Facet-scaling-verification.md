---
id: TASK-32
title: T5.5 Facet-scaling verification
status: Done
assignee: []
created_date: '2026-11-01T02:56:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies:
  - TASK-28
  - TASK-30
  - TASK-31
documentation:
  - doc-2
ordinal: 10310
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T5.1, T5.3, T5.4
- **Do:** Run the facet-scaling suite and confirm the free-scale cases are
  at least 2× faster at 400 panels and the fixed-scale control is no slower.
  Confirm that cost grows linearly from 100 to 1,600 panels. Fix any
  per-panel overhead that remains. The histogram case (at least 5× faster)
  waits for the deferred T3.3 and T4.1; record its current numbers but
  don't treat them as a target.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the point cases meet the targets above, recorded in `RESULTS.md`.
<!-- AC:END -->
