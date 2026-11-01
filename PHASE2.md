# alot — Phase 2 scope: rendering to PNG

Phase 2 takes a built plot (a `ggplot_built` from `alot_build()` or
`ggplot2::ggplot_build()`) and draws it to PNG, with layout, text and
rasterisation in Rust. It replaces `ggplot2::ggplot_gtable()`, grid drawing
and the graphics device. Its only input is a built plot, so it doesn't
depend on Phase 1 ([PLAN.md](PLAN.md)) being finished and can run alongside
it. Tasks are in the backlog (`backlog/`), milestone "Phase 2".

The output is **PNG files only**. Interactive devices, PDF and SVG keep
ggplot2's normal drawing (`alot_print()` builds with alot and draws with
grid as before).

## Goal and fidelity target

- The result should be **visually identical** to ggplot2 drawn with
  `ragg::agg_png` at the same size and resolution. It does not need to match
  pixel for pixel, since anti-aliasing and text rasterisation differ. The
  default check is: no pixel off by more than 32 of 255, and under 1% of
  pixels off by more than 8.
- **Layout must match numerically.** Panel, axis, strip, legend and title
  boxes should land within 0.5 px of where grid puts them.
- **Text** should use the same font files as ragg/systemfonts, with string
  widths within 1 px.
- **Fidelity means mirroring ragg, not ideal geometry.** What we draw must
  match what ragg draws, quirks included. Reference sources are ggplot2
  4.0.3 (`../ggplot2`), ragg 1.5.2 (`../ragg`, mainly `src/AggDevice.h`)
  and R's graphics engine (`../r-source`, `src/main/engine.c`: `GESymbol()`,
  line types).

## What the prototype showed

A prototype (branch `proto/phase2-points`; numbers in its
`inst/bench/RESULTS.md`) kept ggplot2's gtable and grid, drew only the point
layers in Rust, and encoded the PNG in Rust. On the README plot (1e6 points,
six facet panels, 1600 × 1000 at 150 dpi) it cut ggplot + PNG from 3.4 s to
0.6 s, with near-identical pixels (max difference 15 of 255).

- **Marks dominate, and sprites work.** ragg spent 97% of the draw step
  rasterising point symbols. Coverage sprites per (shape, size, lwd) at
  1/8-px offsets, cached for the process and blended in parallel row bands
  in data order, blend 166k points in about 6 ms. Filling a path per point
  would be far slower.
- **The fixed cost is ggplot2's layout, not drawing.** With 10 rows,
  `ggplot_gtable()` still takes about 140 ms on six panels. The time goes to
  per-panel axis, strip and theme rendering: `calc_element()` and S7
  validation are about a quarter of it. ragg's text, axes and backgrounds
  add about 50 ms. Removing these needs layout and text in Rust, with theme
  elements resolved once per plot.
- **Encoding matters.** libpng at ragg's default zlib level took 112 ms.
  The `png` crate's fast mode (fdeflate) takes about 20 ms.
- **ragg's details are visible.** These were measured, and checked against
  ragg's source where it was read:
  - symbol size is fontsize × res / 72, and lwd is lwd × res / 96;
  - filled pch 15–17 have no outline; 19 and 20 are a fill then a
    separately blended outline;
  - each line of `+` and `x` blends separately; lines have round caps and
    joins;
  - `drawCircle()` uses fixed polygon step counts below a 20 px radius (4,
    8, 16, 32 or 64; tiny radii clamp to 0.5), so true discs came out
    measurably darker;
  - fill-only axis-aligned rects snap to whole pixels (`snap_rect`, on by
    default);
  - PNGs carry a `pHYs` chunk from `res`.
- **Per-call overhead adds up.** Fresh multi-megabyte buffers cost more in
  page faults than the blending. Drawing panel by panel serialised work
  that could run at once, and point placement was serial.
- **A hybrid is worth keeping.** It accelerates any plot whose heavy layers
  are supported, even when the rest of the plot isn't.

## User API

```r
alot_png(plot, filename, width = 7, height = 7, units = "in", dpi = 300,
         bg = NULL, scaling = 1)
alot_ggsave(filename, plot = last_plot(), ...)  # same signature as ggsave()
alot_render_coverage(plot)                       # which tier, and why
```

- `alot_png()` follows `ggsave()`'s argument names and defaults. `plot` is a
  `ggplot` (built with `alot_build()` first) or a `ggplot_built`.
- `alot_ggsave()` is a drop-in for `ggplot2::ggsave()`. `.png` files go
  through `alot_png()`; any other extension or device is passed to
  `ggsave()` unchanged.
- Threads: `options(alot.threads = )` or the `ALOT_THREADS` environment
  variable. The default is the available cores, capped at 8, and at 2 when
  `_R_CHECK_LIMIT_CORES_` is set.

## Architecture

1. **Three tiers, chosen per plot.** `alot_png()` uses the first tier that
   supports the plot. Nothing fails just because alot doesn't support it
   yet. The hybrid tier is permanent, not a stepping stone: every Rust
   drawer works both in the full tier's page list and as a lazy grob in the
   hybrid. If a tier hits an internal error (a Rust panic or an
   inconsistent IR, as opposed to a declared "unsupported"), `alot_png()`
   catches it, warns once with the error, and renders with the next tier.
   - **Full:** everything below, in Rust.
   - **Hybrid:** ggplot2's `ggplot_gtable()` and grid, drawn on
     `ragg::agg_capture()`. This tier is used for plots with extension
     grobs, plotmath, or text whose glyphs are missing from the resolved
     font. Layers with a Rust drawer become lazy grobs. At
     draw time, each renders its panel to a pixel-aligned raster in Rust.
     The PNG is encoded in Rust.
   - **ggplot2:** `ggplot_gtable()` and ragg, unchanged, with a one-time
     message.
2. **R prepares a render IR**, in O(k) work plus borrowed columns. The IR
   contains:
   - layer data, as borrowed R vectors (colour strings are parsed in Rust
     with a CHARSXP cache);
   - `panel_params`;
   - the facet layout and strip labels;
   - guide parameters (keys, decor, labels) from `plot@guides`;
   - plot labels;
   - theme elements resolved with `calc_element()` **once per plot**, keyed
     by element name, never per panel or axis, so theme inheritance stays
     in R without its per-panel cost;
   - font family and face mapped to font files with
     `systemfonts::match_fonts()`, once per distinct style.

   The budget is under 10 ms on the README plot. Building the IR also
   decides support per layer, guide and element, which picks the tier.
   Each geom's `draw_panel`/`draw_group` logic is ported to Rust and emits
   display-list items directly, so per-row work never returns to R. Each
   mirrored ggproto method gets a body snapshot in `test-internals.R`, as
   in Phase 1.
3. **Rust lays out the page.** A gtable-like solver sizes rows and columns
   in absolute, `null`, summed and text-measured units, plus margins. It
   mirrors the `ggplot_gtable` structure in
   [../ggplot2/R/plot-build.R](../ggplot2/R/plot-build.R) and `plot_table`,
   along with `Facet$draw_panels`, guide assembly, `table_add_legends`, and
   title, caption and tag placement. It outputs boxes in device pixels, with
   a debug export for layout tests.
4. **Text, in pure Rust.** `ttf-parser` loads the files R resolved, and
   `rustybuzz` shapes text for widths (textshaping's unhinted advances).
   Ascent and descent are ragg's hinted glyph bounds, so `skrifa`'s
   TrueType interpreter hints the outline as FreeType does before AGG's
   rasteriser finds its rows. Sizes follow grid's fontsize × lineheight
   rules. Glyphs are drawn unhinted from
   outlines, with coverage cached per font, size and subpixel offset;
   rotated text uses outlines directly. ragg hints with FreeType, so glyph
   pixels differ slightly; layout must still match. ragg's font fallback is
   not mirrored: a string with a glyph missing from its font sends the plot
   to the hybrid tier.
5. **One display list per page.** Rust draws each geom, guide and theme
   element into a flat list of primitives in device pixels and drawing
   order: point batches (shape, size, stroke, colours), rect batches,
   paths (stroke and fill), text runs (shaped glyphs plus font), rasters,
   and clip push/pop. Each item carries its y extent. Batches keep one
   entry per layer, panel and style run, not one per mark, so 1e6 points
   stay a few large arrays. The hybrid tier uses the same drawers, through
   one-item lists.
6. **Raster backend.** The page is drawn in row bands, in parallel. Each
   band has an f32 premultiplied buffer, reused across calls, so memory is
   bounded by band size rather than page size (a 20 × 20 in page at 300 dpi
   would need about 575 MB as one f32 canvas). Each band walks the whole
   list in order, skipping items by y extent, so overlaps composite as on a
   device and all panels draw at once. Clipping mirrors ragg's
   fractional `clip_box`. The drawers are:
   - **points:** sprite stamping, with geometry from `GESymbol()` as ragg
     draws it, including ragg's circle polygons;
   - **rects:** direct fills with ragg's `snap_rect` rounding for
     fill-only rects; outlined rects use the path drawer;
   - **paths:** an exact-area anti-aliased scanline rasteriser (AGG-style,
     like ragg) or `tiny-skia`. R1.4 decides by fidelity against ragg and
     speed, and records why;
   - **text:** the cached glyph coverage, blended like a mask.
7. **PNG output.** Finished bands are converted to 8-bit and streamed to
   the `png` crate in row order, in fast mode. It writes RGB when the page is
   opaque, RGBA otherwise, and adds ragg's `pHYs` chunk.

Code lives in `alot-core/src/render/` (`ir`, `layout`, `text`, `display`,
`raster`, `points`, `rects`, `paths`, `png`), with glue in
`alot-r/src/render.rs` and R code in `R/render*.R`. New crates: `png` (with
`fdeflate`), `ttf-parser`, `rustybuzz`, and `tiny-skia` if R1.4 picks it.
Each must be declared in the licence note for vendored crates. ragg moves
to Imports, pinned to `ragg (>= 1.5.0, < 1.6.0)` like ggplot2: we mirror its
internals, so a new ragg version means re-verifying.

## Performance targets

On the README plot, release build, rendering only (IR, layout, raster,
PNG; not the build). Baselines are R0.3's (`inst/bench/render-suite.R`,
gtable built on the open device):

| Case | ggplot2 + ragg | Hybrid | Full tier target |
|---|---:|---:|---:|
| README plot, 1600 × 1000 at 150 dpi | ~3300 ms | ~400 ms | < 120 ms |
| Same plot, 10 rows | ~255 ms | ~210 ms | < 25 ms |
| README plot, default page (7 × 7 in at 300 dpi) | ~5000 ms | ~460 ms | < 200 ms |

The default page target allows for its 2.8× pixels (2100 × 2100 px) and
about 4× symbol pixels at 300 dpi: in the hybrid, its draw and encode
steps took 240 ms against 185 ms at 150 dpi, while the gtable step,
which the full tier replaces, was the same.

No drawer may be slower than ragg drawing the same marks.

## In scope

| Area | Included |
|---|---|
| Geoms | point (`pch` 0–25, `stroke`), line, path, step, polygon, rect, tile, raster (embedded image), col/bar, histogram, area, ribbon, density, boxplot, violin, errorbar, linerange, pointrange, crossbar, segment, curve, abline/hline/vline, smooth, text, label, rug, text-free annotate layers |
| Line styles | linetype (named and hex dash patterns), `lineend`, `linejoin`, alpha on colour and fill |
| Coords | cartesian, flip, fixed / `aspect.ratio`, transform (after munching), `expand`, `clip` |
| Facets | null, wrap, grid; free and fixed scales; `space = "free"`; strip placement and `switch` |
| Axes | `guide_axis` (position, `angle`, `n.dodge`, `check.overlap`, minor ticks), secondary axes |
| Legends | `guide_legend` (key drawing for each geom's `draw_key`, merged legends, byrow / nrow / ncol), `guide_colourbar`, `guide_coloursteps`, `guide_bins` |
| Legend layout | position right / left / top / bottom / inside, justification, box arrangement |
| Theme | `element_text`, `element_line`, `element_rect`, `element_blank`, margins, `plot.background`, `panel.grid`, built-in complete themes |
| Plot text | title, subtitle, caption, tag, `plot.title.position` `<title>`/`<desc>` |

## Out of scope for Phase 2

- `coord_polar` / `coord_radial`, `coord_sf` and `geom_sf`, map projections.
- `geom_dotplot`, `geom_hex`, and contour fill polygons with holes. These are
  candidates for a later stretch milestone.
- Grobs from extension packages. Extension geoms produce arbitrary grid
  grobs that can't be drawn without grid. Such a plot drops to the hybrid
  tier, where its supported layers still draw in Rust; it drops to ggplot2
  + ragg only if nothing is supported.
- `plotmath` expressions and rich or markdown text (ggtext). These drop to
  a lower tier as above.
- Interactive output, animation, PDF.

## Milestones

| # | Milestone | Done when |
|---|---|---|
| 2.0 | **Hybrid tier, display list and raster engine.** The hybrid tier lands; the display list, band executor, point, rect and path drawers, and PNG output. | The hybrid tier renders the README plot. A 1e6-row `geom_point` and a 1000×1000 `geom_tile` panel (no axes or text) render to PNG faster than ggplot2 + ragg. |
| 2.1 | **Layout engine and text metrics.** | Box positions match grid within 0.5 px on single-panel plots (see Verification). |
| 2.2 | **README vertical slice.** Points, cartesian axes, fixed-scale `facet_wrap`, strips, colourbar and point legend, `theme_grey`. | The README plot renders in the full tier, visually equivalent, and meets the performance targets. |
| 2.3 | **Core geoms and themes.** line, path, step, col/bar, rect, tile and text; every built-in complete theme. | Their corpus plots are visually equivalent. |
| 2.4 | **Facets in full.** `facet_grid`, free scales, `space = "free"`, switched strips. | Facet corpus plots pass layout and image checks. |
| 2.5 | **Legends in full.** All `draw_key` variants, coloursteps and bins, merged legends, all positions. | Legend corpus plots pass. |
| 2.6 | **Remaining in-scope geoms**, secondary axes, `coord_flip/fixed/transform`. | Their corpus plots pass. |
| 2.7 | **Tier selection, performance pass, docs.** | Every corpus plot renders through some tier; the targets are met. |

## Verification

- **Layout tests.** For each plot in a corpus, compute grid's actual
  viewport positions: open a ragg device, run `ggplot_gtable()`, then walk the
  gtable with `grid::convertUnit` / `deviceLoc`. Compare them with the boxes
  the Rust layout engine reports via a debug export. This is a precise
  numeric check that needs no image comparison.
- **Image tests.** `expect_render_close()` draws each corpus plot with
  `alot_png()` and with ggplot2 on `ragg::agg_capture()`, then compares
  pixels against the tolerance above. The reference is rendered live on
  every run; no images are stored in the repo. Corpus plots are kept small
  so this stays fast. Failing pairs and their diff image are written out
  for manual review. Tests also check that no fallback warning was
  raised, so internal errors can't hide behind the fallback.
- **Geometry unit tests.** Rust tests check each drawer against ragg output
  measured once (symbol extents, line widths, circle coverage), so drift
  shows up without R.
- **Coverage.** `alot_render_coverage()` reports the tier and the reason
  for each plot. Tests check that every unsupported case drops a tier
  rather than failing.
- **Performance.** `inst/bench/render-*.R` times each stage against ggplot2
  + ragg and the hybrid, on the README plot (1e6 rows and 10 rows), 1e6
  points, a dense `geom_tile`, a 1e6-point line and 400 panels.

## Decisions

Settled before the Phase 2 tasks start (2026-10-30):

- **Fidelity:** visual, at the tolerance above; it is not pixel-exact.
- **Output:** PNG files only.
- **API:** `ggsave()` names and defaults (7 × 7 in, 300 dpi), plus
  `alot_ggsave()`.
- **Hybrid tier:** permanent.
- **Path rasteriser:** R1.4 measures both candidates and picks one.
- **Text:** pure Rust and unhinted. Missing glyphs drop the plot to the
  hybrid tier.
- **Geom logic:** ported to Rust per geom.
- **Image references:** rendered live with ragg on every run.
- **ragg:** in Imports, pinned to the 1.5 series.
- **Canvas:** f32 per band, streamed to the encoder.
- **Threads:** an option, defaulting to at most 8.
- **Internal errors:** warn and fall back to the next tier.
- **Order:** the README plot first, as a vertical slice through the full
  tier, then breadth.
