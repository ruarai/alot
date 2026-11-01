# alot — spatial plots: `geom_raster()` and `geom_sf()`

This plan extends the build path ([PLAN.md](PLAN.md)) and the render path
([PHASE2.md](PHASE2.md)) to spatial plots. Two layer types need to get
faster:

- **High-resolution `geom_raster()`**, e.g. a species distribution model
  (SDM) output of 2000 × 2000 cells, mostly continuous fill, with NA
  outside land.
- **High-resolution `geom_sf()`**, e.g. sub-region boundary polygons:
  hundreds to thousands of features and about 1e6 vertices in total.

Tasks are in [TASKS.md](TASKS.md) under "Spatial", with IDs `S<milestone>.<n>`
and branches named `task/S1.1-raster-drawer` as before. The phases' rules
still apply. Build output must equal ggplot2's under
`expect_equal(..., tolerance = 1e-8)`. Rendering is visually equivalent to
ragg at PHASE2.md's tolerance, and layout matches within 0.5 px. Anything
unsupported falls back. Kernels follow the 1.25× rule.

## North star

Every milestone works toward one plot: the **combined SDM map**.

```r
ggplot() +
  geom_raster(aes(x, y, fill = suitability), data = grid_2000) +  # 4e6 cells, ~50% absent
  geom_sf(data = regions, fill = NA, colour = "grey20") +         # ~500 features, ~1e6 vertices
  scale_fill_viridis_c() +
  coord_sf(crs = 3577)                                            # raster and sf share the CRS
```

It is drawn to a 7 × 7 in PNG at 300 dpi with `alot_png()`. A faceted
variant (`facet_wrap(~ species)`, 4 to 9 panels, fixed scales) is the
second case.

**Target:** at least **5× faster end to end** (build + render to PNG,
release build) than `ggplot_build()` + `ggplot_gtable()` + ragg. Any time
spent in PROJ (`st_transform()` / `sf_project()`) counts on both sides and
is a floor alot can't cut. If S0.2's profile shows that this floor makes 5×
unreachable for some workload, record that in RESULTS.md and set that
workload's target there.

## Where we start (2026-10-31)

A 1000 × 1000 `geom_raster()` with continuous fill and `coord_fixed()`,
ggplot2 4.0.3, debug build:

| Step | ggplot2 | alot |
|---|---:|---:|
| build | 1.27 s | 0.40 s (scale train/map and colour map already in Rust) |
| `ggplot_gtable()` | 0.28 s | same: the render path declines `geom_raster()` |
| draw on ragg (1200 px) | 0.18 s | same |

So the raster build is mostly done, and what's left is the render. The
render path declines `geom_raster()` today (R6.5d: "a device-scaled,
possibly interpolated `rasterGrob()`; not mirrored"), so `alot_png()`
hands the whole plot to ggplot2.

For `geom_sf()`, upstream's O(vertices) work happens mostly at **render
time**, not build time:

- build: `StatSf$compute_panel` calls `sf::st_bbox()` once per panel
  (sf caches the bbox on the sfc). `CoordSf$setup_data` reprojects with
  `st_transform()`. `CoordSf$setup_panel_params` calls `st_graticule()`,
  which is O(breaks). `LayerSf` checks geometry types per feature
  (ggplot2 R/stat-sf.R, R/coord-sf.R, R/layer-sf.R).
- render: `CoordSf$transform` → `sf_rescale01()` (`st_normalize()`) over
  every vertex, then `GeomSf$draw_panel` → `sf_grob()` →
  `sf::st_as_grob()` per feature, then grid and ragg fill and stroke each
  path (ggplot2 R/geom-sf.R).

S0.2 replaces this reading with measurements before any kernel is
written.

## Decisions

Settled on 2026-10-31:

- **Scope:** both the build and the render.
- **sf** goes in Suggests and is never needed to load alot. Every sf
  test and corpus file uses `skip_if_not_installed("sf")`. On the dev
  machine, GDAL, GEOS and PROJ come from apt (`libgdal-dev`, `libgeos-dev`,
  `libproj-dev`) and sf from CRAN.
- **Projection always stays in sf.** `st_transform()`, `sf_project()` and
  `st_graticule()` run in R through sf, as ggplot2 calls them. Rust only
  does work after projection: bounding boxes, rescaling to the panel,
  flattening to device coordinates, drawing. alot never ports a PROJ
  projection. One exception, decided 2026-11-01 after S0.2: the
  `CoordSf$setup_data` mirror skips `st_transform()` when the layer is
  already in the coord's crs, because that call is a 100–200 ms no-op
  (S2.1).
- **Geometry input:** `alot-r` walks the sfc list directly, borrowing each
  coordinate matrix as `&[f64]`, and builds a flat struct in `alot-core`
  (coordinates plus ring, part and feature offsets, and the geometry
  type). There is no `st_coordinates()` round-trip and no cache on the
  geometry column. Build kernels never rewrite a geometry column. They
  compute only scalars or new columns, so the sfc's attributes (`bbox`,
  `crs`, `precision`, `n_empty`, sfg classes) pass through untouched.
  Only XY geometries are read. XYZ, XYM and XYZM decline.
- **Geometry types:** POINT, LINESTRING and POLYGON, plus their MULTI
  variants. GEOMETRYCOLLECTION and empty geometries decline (a layer with
  any of them falls back).
- **No vertex decimation.** Every vertex is drawn, as ragg draws it.
  Speed comes from not calling `st_as_grob()` or grid per feature,
  parallel row bands, bbox culling, and batching features whose bboxes
  don't overlap.
- **`geom_raster()` render scope:** `interpolate = FALSE` only, the
  nearest-neighbour path of ragg's `drawRaster()` (ragg
  `src/AggDevice.h`; R `GERaster()` in `src/main/engine.c`). Absent cells
  and `na.value = NA` are drawn as transparent pixels. A partial alpha,
  `interpolate = TRUE`, pattern fills, `annotation_raster()`, and the
  `GeomRect` fallback that `GeomRaster` uses under a non-linear coord all
  decline.
- **Tiers for `coord_sf()`:** **hybrid first, full later.** ggplot2 keeps
  the gtable at first (graticule, degree-label axes) and the heavy raster
  and sf layers become lazy Rust grobs. The full tier, with graticule
  paths and degree labels, comes in milestone S5. `geom_raster()` under
  cartesian, `coord_fixed()` and `coord_flip()` goes to the full tier
  directly (S1.1).
- **Facets:** in scope with fixed scales (`CoordSf$is_free()` is FALSE).
  A raster or an sf layer is drawn per panel.
- **Workloads:** synthetic and generated in `inst/bench/spatial.R`, with
  no downloads. There is also an opt-in real-data bench that reads files
  from `ALOT_SPATIAL_DATA`, a directory of e.g. a boundary shapefile and an
  SDM GeoTIFF. It is never run by tests.
- **Order:** raster first (no sf needed, and it extends existing image
  code), then the sf build, the sf render, the combined north star, and
  the `coord_sf()` full tier.

## Architecture

### Raster (S1)

`GeomRaster$draw_panel` (ggplot2 R/geom-raster.R) does three things, and
each one has a counterpart:

1. **Cell positions.** It finds `x_pos` and `y_pos` from
   `(x - min(x)) / resolution(x, FALSE)` cast to integer. This is ported
   exactly, including `as.integer()` truncation. `resolution()` is O(n)
   and is computed in R once per panel, or in Rust if S0.2 shows it
   matters, checked against `ggplot2::resolution()`.
2. **The colour matrix.** It builds an `nrow × ncol` character matrix of
   `alpha(fill, alpha)`, with `NA_character_` where no cell exists. alot
   skips the strings: Rust writes a premultiplied RGBA image straight from
   the parsed fill colours (R3.2's CHARSXP cache), with transparent pixels
   for absent and NA cells.
3. **Placement.** It draws a `rasterGrob()` at the centre of the
   `xmin`–`xmax` and `ymin`–`ymax` range in native units. Rust converts
   that rectangle to device pixels and samples the image as ragg's
   `drawRaster()` does with `interpolate = FALSE`: the image-to-device
   transform, pixel-centre sampling and clipping to the panel. R5.3's
   `bar_image()` in `page.rs` is the starting point; it mirrors ragg's
   bilinear span.

The drawer adds a `raster` item to the display list (`render/raster.rs`
already holds image items for the colourbar). It works in the full tier's
page list and as a lazy grob in the hybrid tier, like every other drawer.

### sf geometry (S3)

- **Reader** (`alot-r/src/sf.rs` → `alot-core/src/sf/`): one pass over the
  sfc gives `Geometry { kind, coords: Vec<f64>, ring_off, part_off,
  feature_off }`. It returns `None` (decline) for unsupported types,
  dimensions or empty features.
- **Transform:** this mirrors `CoordSf$transform` → `sf_rescale01()`
  (`st_normalize()` to the panel's `x_range` / `y_range`, reversed as
  `reverse` says), then the viewport's npc → device-pixel step. It runs
  in one pass per panel, in Rust.
- **Drawing:** this mirrors `GeomSf$draw_panel` and `sf_grob()`:
  - polygons as ragg draws `st_as_grob()`'s `pathGrob(rule = "evenodd")`,
    fill then stroke, feature by feature in data order, using the
    existing `Rule::EvenOdd` path rasteriser
    ([agg.rs](src/rust/alot-core/src/render/agg.rs));
  - lines as `polylineGrob()`;
  - points through the existing point sprites, with `sf_grob()`'s size,
    stroke and `pch` arithmetic.

  Features whose bboxes don't overlap may be batched into one display
  item. This changes nothing visible, because they composite the same way
  in any order.
- **Build:** the steps `alot_build()` repeats from `build_ggplot` gain
  mirrors of `StatSf`, `LayerSf` and `CoordSf`'s `setup_params`,
  `setup_data` and `setup_panel_params`, so `alot_coverage()` reports
  them. Kernels are added only where S0.2's profile and the 1.25× rule
  justify them.

### `coord_sf()` full tier (S5)

The graticule stays an R computation (`st_graticule()`, O(breaks)). The
IR carries its projected lines and label positions. Rust draws them as
paths, with the panel grid and the axes at the graticule's edge
crossings. Degree labels are plotmath expressions (`150*degree*E`). S5.2
handles only the expression forms that `sf` / `CoordSf` generate for
degree labels, and any other plotmath still sends the plot to the hybrid
tier.

## Verification

- **Build:** `expect_build_equal()` on sf plots, covering NA attributes,
  a single feature, empty layers, MULTI types, mixed point, line and
  polygon layers, a layer CRS that differs from the coord CRS, and facets.
  Fallback tests check that `alot_coverage()` reports `"ggplot2"` for
  each declined input.
- **Render:** `expect_render_close()` and the layout export, in both the
  full and hybrid tiers, for: rasters with absent cells, NA fill, reversed
  scales, `coord_flip()`, facets and odd sizes (a cell narrower than a
  pixel, a cell many pixels wide); and polygons with holes, lines, points,
  outline-only and fill-only styles, linetypes, and `coord_sf()` with
  projected and longlat CRSs.
- **Corpus:** regenerate with `tools/extract-corpus.R` once sf is
  installed. This picks up ggplot2's `man/` sf examples, `test-geom-sf.R`,
  `test-coord_sf.R` and `test-stat-sf-coordinates.R` (plots that errored
  without sf were dropped). Both `test-corpus.R` and `test-render-corpus.R`
  run them when sf is installed.
- **Bench:** `inst/bench/spatial.R` has rasters of 500², 1000² and 2000²
  cells, sf layers of 1e2 to 1e4 features and about 1e6 vertices in one
  projected and one longlat CRS, the north star and its faceted variant.
  It times each stage (build, IR, layout, draw, encode) against ggplot2
  + ragg and the hybrid, and records the results in
  `inst/bench/RESULTS.md`.

## Out of scope

- Porting any PROJ projection, and `coord_sf(default_crs = ...)` for
  non-sf layers. Under that setting `CoordSf$is_linear()` is FALSE, so
  rasters become `GeomRect`, and these plots fall back.
- `stat_sf_coordinates()`, `geom_sf_text()` and `geom_sf_label()`
  (they fall back; candidates after S5).
- `interpolate = TRUE`, partial alpha on rasters, `annotation_raster()`
  and `annotation_map()`.
- terra, stars and raster objects as plot inputs: users convert to a data
  frame or sf themselves, as ggplot2 needs.
- Simplifying geometry.
