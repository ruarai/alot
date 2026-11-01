---
id: TASK-31
title: T5.4 Mirror `setup_panel_guides` and deduplicate per axis
status: Done
assignee: []
created_date: '2026-11-01T02:55:00Z'
updated_date: '2026-11-01T02:56:00Z'
labels:
  - facets-and-layout-setup
milestone: m-0
dependencies:
  - TASK-30
documentation:
  - doc-2
ordinal: 10300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- **Depends:** T5.3
- **Do:** Mirror `Layout$setup_panel_guides` and build axis guides once per
  distinct x and y scale, then clone them per panel. Fall back for non-axis
  position guides and custom guides.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the guides in `layout$panel_params` are equal, and both the `facet_wrap` and the 20×20 `facet_grid` free cases are at least 2× faster.
<!-- AC:END -->
