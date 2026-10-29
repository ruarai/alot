# alot — Phase 2 scope: rendering to SVG and PNG

Phase 2 takes a built plot (a `ggplot_built` from `alot_build()` or
`ggplot2::ggplot_build()`) and draws it in Rust, to SVG and to PNG, through
one shared display list. It replaces `ggplot2::ggplot_gtable()`, the grid drawing step and
the graphics device. Phase 2 begins once Phase 1 ([PLAN.md](PLAN.md)) is
finished.

## Goal and fidelity target

- The result should be **visually identical** to ggplot2 drawn with
  `ragg::agg_png` at the same size and resolution. It does not need to match
  pixel for pixel, since anti-aliasing and text rasterisation differ.
- **Layout must match numerically.** Panel, axis, strip, legend and title
  boxes should land within 0.5 px of where grid puts them.
- **Text** should use the same font files as ragg/systemfonts, with string
  widths within 1 px.

## User API

```r
alot_svg(plot, file = NULL, width = 7, height = 5, units = "in", dpi = 96, bg = NULL)
# file = NULL returns the SVG as a string

alot_png(plot, file, width = 7, height = 5, units = "in", dpi = 96, bg = NULL, scaling = 1)
```

Both accept a `ggplot` (built with `alot_build()` first) or a `ggplot_built`.

## Architecture

1. **R prepares a render IR.** R converts the built plot into plain lists that
   extendr turns into Rust structs, with no JSON in between. The IR contains:
   - layer data,
   - `panel_params`,
   - the facet layout and strip labels,
   - guide parameters (keys, decor, labels) from `plot@guides`,
   - plot labels,
   - every theme element resolved with `calc_element()`, so theme
     inheritance stays in R,
   - font family/face mapped to font file paths with
     `systemfonts::match_fonts()`.
2. **Rust lays out the plot.** A gtable-like grid: rows and columns sized in
   absolute, `null` and summed units, plus margins. This mirrors the
   `ggplot_gtable` structure in
   [../ggplot2/R/plot-build.R](../ggplot2/R/plot-build.R) and `plot_table`,
   along with `Facet$draw_panels`, `table_add_legends`, and the
   title/caption/tag placement.
3. **Text measurement.** `fontdb` loads the same files R resolved, and
   `rustybuzz` shapes the text for widths, ascent and descent. Sizes follow
   grid's fontsize × lineheight rules.
4. **Display list.** Rust draws each geom, guide and theme element into a
   flat, backend-neutral list of primitives in device coordinates: paths,
   polylines, rect batches, point batches (shape, size, stroke, colours), text
   runs (shaped glyphs plus font), rasters, and clip push/pop. Layout and geom
   drawing happen once, here. Batches keep one entry per layer and style run,
   not one per mark, so 1e6 points stay a few large arrays.
5. **Backends.** Two consumers of the same display list:
   - **SVG writer** (`alot_svg`). A plain serialiser, with panel clipping
     through `clipPath`. It merges each point batch into one `<path>` per
     style group (or `<defs>` + `<use>`; see open question 1) and writes
     coordinates at fixed, limited precision.
   - **Raster backend** (`alot_png`). Draws the display list directly with
     `tiny-skia`, with no SVG string or DOM in between. It uses fast paths
     SVG can't express: one prebuilt path per point shape and size,
     transformed per point; `fill_rect` for axis-aligned rects and tiles; and
     the paint set once per style run. Glyphs are shaped with `rustybuzz`,
     taken as outlines from `ttf-parser` and filled as `tiny-skia` paths,
     using the same font files as the measurement step.

   PNG does **not** go through SVG. Serialising and reparsing (`usvg` +
   `resvg`) would cost tens of MB of text and a heap node per mark at 1e6
   rows, which is more than the rasterisation itself and would lose to
   ggplot2 + ragg on exactly the dense plots alot exists for.

New Rust crate: `alot-core/src/render/` (IR, layout, text, display list,
svg, raster), plus `tiny-skia`, `ttf-parser`, `rustybuzz` and `fontdb`.
`tiny-skia` is BSD-3-Clause and must be declared in the licence note for
vendored crates.

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
| Plot text | title, subtitle, caption, tag, `plot.title.position`, alt text written to SVG `<title>`/`<desc>` |

## Out of scope for Phase 2

- `coord_polar` / `coord_radial`, `coord_sf` and `geom_sf`, map projections.
- `geom_dotplot`, `geom_hex`, and contour fill polygons with holes. These are
  candidates for a later stretch milestone.
- Grobs from extension packages. Extension geoms produce arbitrary grid grobs
  that can't be drawn without grid. If any layer or guide has no Rust drawer,
  the **whole plot falls back** to ggplot2 + ragg (PNG) or svglite (SVG),
  with a one-time message. This follows the Phase 1 rule that nothing fails
  just because alot doesn't support it yet.
- `plotmath` expressions and rich or markdown text (ggtext). These fall back
  as above.
- Interactive output, animation, PDF.

## Milestones

| # | Milestone | Done when |
|---|---|---|
| 2.0 | **IR, display list and both backends.** A blank canvas with background; `alot_svg()` and `alot_png()` end to end. Point and rect batches drawn by both backends. | A blank theme renders to SVG and PNG. A 1e6-row `geom_point` and a 1000×1000 `geom_tile` panel (no axes or text) render to PNG faster than ggplot2 + ragg. |
| 2.1 | **Layout engine and text metrics.** | Box positions match grid within 0.5 px across the theme and facet corpus (see Verification). |
| 2.2 | **Single-panel cartesian plots.** Panel background, grid lines, axes and core geoms. | `geom_point/line/col/text` plots are visually equivalent. |
| 2.3 | **Facets and strips.** | wrap/grid, free scales, switched strips. |
| 2.4 | **Legends and colourbars.** All `draw_key` variants and legend positions. | |
| 2.5 | **Remaining in-scope geoms**, secondary axes, `coord_flip/fixed/transform`. | |
| 2.6 | **Fallback path, performance pass, docs.** | |

## Verification

- **Layout tests.** For each plot in a corpus, compute grid's actual
  viewport positions: open a ragg device, run `ggplot_gtable()`, then walk the
  gtable with `grid::convertUnit` / `deviceLoc`. Compare them with the boxes
  the Rust layout engine reports via a debug export. This is a precise
  numeric check that needs no image comparison.
- **Image tests.** Draw each corpus plot with `alot_png()` and with
  `ragg::agg_png`, then compare by per-pixel difference with a tolerance
  threshold. Store failing pairs and their diff image as test artefacts for
  manual review.
- **SVG checks.** The output is well-formed and parses with `usvg` (a test
  dependency only), and it is deterministic: the same input gives
  byte-identical output.
- **Backend agreement.** For each corpus plot, rasterise `alot_svg()` output
  with resvg (test-only) and compare it with `alot_png()` by per-pixel
  difference. This catches the two backends drifting apart.
- **Performance.** Rendering time and size of the 1e6-point and dense
  `geom_tile` plots, compared with ggplot2 + ragg (PNG) and with ggplot2 +
  svglite (SVG). The PNG path should beat ragg; the SVG path should beat
  svglite in both time and file size.

## Open questions to settle before 2.0

1. **SVG size for huge layers.** Should very large point layers be drawn as
   one `<path>` per style group or with `<use>` symbol references to keep
   files small? Benchmark both on file size and on how fast browsers render
   them. Separately, should there be an opt-in setting (off by default) that
   rasterises dense layers into an embedded `<image>` with the raster
   backend? That trades exact vector output for size, so it can't be the
   default.
2. **Default DPI and scaling.** Should defaults follow `ggsave()` (300 dpi,
   size taken from the device) or ragg's 72/96 conventions?
3. **SVG fallback.** Should the whole-plot SVG fallback require svglite in
   Suggests (it isn't installed now), or should it error instead?
