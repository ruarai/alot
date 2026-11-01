test_that("upstream build function matches the version alot mirrors", {
  # If this fails, ggplot2's build pipeline changed: update R/build.R to
  # match, then update the snapshot.
  expect_snapshot(print(body(utils::getFromNamespace("build_ggplot", "ggplot2"))))
})

test_that("upstream grouped compute methods match the versions alot mirrors", {
  # Mirrored by R/grouped.R. If these fail, update the mirror to match, then
  # update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::Stat$compute_layer)$f)))
  expect_snapshot(print(body(environment(ggplot2::Stat$compute_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::Position$compute_layer)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("dapply", "ggplot2"))))
})

test_that("upstream discrete position training matches what alot relies on", {
  # kernel_train_discrete (R/kernels-scale.R) assumes training depends only
  # on the distinct values (discrete input) or the finite extremes
  # (continuous input) of each slice. If these change, recheck that, then
  # update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscretePosition$train)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("discrete_range", "scales"))))
  expect_snapshot(print(body(utils::getFromNamespace("clevels", "scales"))))
  expect_snapshot(print(body(scales::train_continuous)))
})

test_that("upstream position mapping matches the versions alot mirrors", {
  # Mirrored by layout_map_position() and scales_map() (R/layout.R); the
  # map kernels (R/kernels-scale.R) reproduce the scales' map() methods and
  # the oob functions they recognise. If these fail, update the mirror and
  # kernels to match, then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::Layout$map_position)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("scale_apply", "ggplot2"))))
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuousPosition$map)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscretePosition$map)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("mapped_discrete", "ggplot2"))))
  expect_snapshot(print(body(scales::oob_censor)))
  expect_snapshot(print(body(scales::oob_censor_any)))
  expect_snapshot(print(body(scales::oob_squish)))
  expect_snapshot(print(body(scales::oob_squish_any)))
  expect_snapshot(print(body(scales::oob_squish_infinite)))
  expect_snapshot(print(body(scales::oob_keep)))
})

test_that("upstream scale transformation matches the versions alot mirrors", {
  # Mirrored by scales_transform_df() (R/build.R); kernel_transform
  # (R/kernels-scale.R) reproduces Scale$transform_df with default_transform
  # for the scales transforms it recognises. If these fail, update the
  # mirror and kernel to match, then update the snapshots.
  expect_snapshot(print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$transform_df)$f)))
  expect_snapshot(print(body(environment(ggplot2::Scale$transform_df)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("default_transform", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("has_default_transform", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("check_transformation", "ggplot2"))))
  expect_snapshot(print(body(scales::transform_log)))
  expect_snapshot(print(body(scales::transform_sqrt)))
  expect_snapshot(print(body(scales::transform_reverse)))
})

test_that("upstream non-position scale training and mapping match the versions alot mirrors", {
  # Mirrored by npscales_train_df() and npscales_map_df() (R/npscales.R),
  # which dispatch each scale's train_df() and map_df(). If these fail,
  # update the mirror to match, then update the snapshots.
  expect_snapshot(print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$train_df)$f)))
  expect_snapshot(print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$map_df)$f)))
  expect_snapshot(print(body(environment(ggplot2::Scale$train_df)$f)))
  expect_snapshot(print(body(environment(ggplot2::Scale$map_df)$f)))
})

test_that("upstream continuous colour training and mapping match the versions alot mirrors", {
  # Mirrored by kernel_np_train_continuous() and kernel_np_map_continuous()
  # (R/kernels-npscale.R), which also read the environments of the
  # pal_gradient_n(), colour_ramp(), approxfun() and mid_rescaler()
  # closures. If these fail, update the kernels (and alot-core's
  # colour::ramp) to match, then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuous$train)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuous$map)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuous$rescale)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("mid_rescaler", "ggplot2"))))
  expect_snapshot(print(body(scales::pal_gradient_n)))
  expect_snapshot(print(body(scales::colour_ramp)))
  expect_snapshot(print(body(utils::getFromNamespace("rescale.numeric", "scales"))))
  expect_snapshot(print(body(utils::getFromNamespace("rescale_mid.numeric", "scales"))))
  expect_snapshot(print(body(scales::zero_range)))
  expect_snapshot(print(body(stats::approxfun)))
  expect_snapshot(print(body(farver::encode_colour)))
})

test_that("upstream discrete non-position training and mapping match what alot relies on", {
  # kernel_np_train_discrete and kernel_np_map_discrete (R/kernels-npscale.R)
  # assume training depends only on the distinct values and that map() is
  # elementwise in `x`. If these change, check both assumptions still hold,
  # then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscrete$train)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscrete$map)$f)))
  expect_snapshot(print(body(scales::train_discrete)))
})

test_that("upstream print method matches the version alot_print mirrors", {
  # Mirrored by alot_print() (R/print.R). If this fails, update the mirror to
  # match, then update the snapshot.
  # alot's autoprint method (R/print.R) wraps ggplot2's, which it keeps.
  getS3method <- function(...) {
    method <- utils::getS3method(...)
    environment(method)$print_original %||% method
  }
  expect_snapshot(print(body(getS3method("print", "ggplot2::ggplot"))))
})

test_that("upstream layout setup and facet panel assignment match the versions alot mirrors", {
  # Mirrored by layout_setup() (R/layout.R) and kernel_facet_map_data()
  # (R/kernels-facet.R), which replaces join_keys() + match() by a join on
  # factor labels. If these fail, update the mirror and kernel to match,
  # then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::Layout$setup)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("map_facet_data", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("join_keys", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("id", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("id_var", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("as_unordered_factor", "ggplot2"))))
})

test_that("upstream facet layout computation matches the versions alot mirrors", {
  # Mirrored by kernel_facet_wrap_layout(), kernel_facet_grid_layout() and
  # facet_combine_vars() (R/kernels-facet.R). If these fail, update the
  # mirrors to match, then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::FacetWrap$compute_layout)$f)))
  expect_snapshot(print(body(environment(ggplot2::FacetGrid$compute_layout)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("combine_vars", "ggplot2"))))
})

test_that("upstream labeling::extended matches the version alot ports", {
  # Ported by alot_core::breaks::extended, called through
  # extended_breaks_batch() (R/breaks.R). If these fail, update the port to
  # match, then update the snapshots.
  expect_identical(as.character(utils::packageVersion("labeling")), "0.4.3")
  expect_snapshot(print(body(labeling::extended)))
  for (f in c(".simplicity", ".simplicity.max", ".coverage", ".coverage.max", ".density", ".density.max", ".legibility")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "labeling"))))
  }
  expect_snapshot(print(body(scales::extended_breaks)))
})

test_that("upstream panel guides setup matches the version alot mirrors", {
  # Mirrored by layout_setup_panel_guides() and kernel_panel_guides() with its
  # helpers (R/panel-guides.R). If these fail, update the mirror to match,
  # then update the snapshots.
  body_of <- function(obj, name) body(environment(obj[[name]])$f)
  expect_snapshot(print(body_of(ggplot2::Layout, "setup_panel_guides")))
  expect_snapshot(print(body_of(ggplot2::Coord, "setup_panel_guides")))
  expect_snapshot(print(body_of(ggplot2::Coord, "train_panel_guides")))
  expect_snapshot(print(body_of(ggplot2::CoordCartesian, "transform")))
  expect_snapshot(print(body_of(ggplot2::Guide, "train")))
  expect_snapshot(print(body_of(ggplot2::Guide, "extract_key")))
  expect_snapshot(print(body_of(ggplot2::GuideAxis, "extract_key")))
  expect_snapshot(print(body_of(ggplot2::GuideAxis, "extract_decor")))
  expect_snapshot(print(body_of(ggplot2::GuideAxis, "extract_params")))
  expect_snapshot(print(body_of(ggplot2::GuideAxis, "transform")))
  expect_snapshot(print(body_of(ggplot2::Facet, "setup_panel_params")))
  for (m in c("get_breaks", "get_labels", "map", "is_discrete", "rescale")) {
    expect_snapshot(print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m)))
  }
})

test_that("upstream panel params setup matches the version alot mirrors", {
  # Mirrored by layout_setup_panel_params(), kernel_panel_params() and its
  # helpers (R/panel-params.R). If these fail, update the mirror to match,
  # then update the snapshots.
  expect_snapshot(print(body(environment(ggplot2::Layout$setup_panel_params)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordCartesian$setup_panel_params)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordFlip$setup_panel_params)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuous$get_breaks)$f)))
  for (f in c("view_scales_from_scale", "view_scale_primary", "view_scale_secondary", "flip_axis_labels", "scale_flip_position")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "ggplot2"))))
  }
  expect_snapshot(print(body(ggplot2::ggproto)))
})

test_that("upstream point drawing matches what the hybrid tier mirrors", {
  # draw_points_layer() and hybrid_data() (R/render.R) mirror these for
  # GeomPoint; the Rust drawer mirrors pointsGrob() as GESymbol() draws it
  # with gg_par()'s fontsize and lwd. If these fail, update the mirror,
  # then the snapshots.
  expect_snapshot(print(body(environment(ggplot2::GeomPoint$draw_panel)$f)))
  expect_snapshot(print(body(environment(utils::getFromNamespace("Layer", "ggplot2")$draw_geom)$f)))
  expect_snapshot(print(body(environment(ggplot2::Geom$handle_na)$f)))
  expect_snapshot(print(body(environment(ggplot2::Geom$draw_layer)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("gg_par", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("translate_shape_string", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("remove_missing", "ggplot2"))))
})

test_that("upstream rect drawing matches what the hybrid tier mirrors", {
  # draw_rects_layer() (R/render.R) mirrors GeomRect$draw_panel for linear
  # coords; linear_range() relies on the position scales' rescale and map.
  # If these fail, update the mirror, then the snapshots.
  expect_snapshot(print(body(environment(ggplot2::GeomRect$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleContinuous$rescale)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscretePosition$rescale)$f)))
  expect_snapshot(print(body(environment(ggplot2::ScaleDiscretePosition$map)$f)))
})

test_that("upstream path drawing matches what the hybrid tier mirrors", {
  # draw_paths_layer() and draw_polygons_layer() (R/render.R) mirror these.
  # If they fail, update the mirror, then the snapshots.
  expect_snapshot(print(body(environment(ggplot2::GeomPath$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomPath$handle_na)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomPolygon$draw_panel)$f)))
})

test_that("upstream step and text drawing match what the full tier mirrors", {
  # step_data() (R/render.R) mirrors GeomStep$draw_panel(); full_text()
  # (R/render-full.R) mirrors GeomText$draw_panel(). If these fail, update
  # the mirror, then the snapshots.
  expect_snapshot(print(body(environment(ggplot2::GeomStep$draw_panel)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("stairstep", "ggplot2"))))
  expect_snapshot(print(body(environment(ggplot2::GeomText$draw_panel)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("compute_just", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("resolve_text_unit", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("validate_labels", "ggplot2"))))
})

test_that("upstream ribbon and smooth drawing match what the full tier mirrors", {
  # full_ribbons() (R/render-full.R) mirrors GeomRibbon$draw_group() and
  # GeomSmooth$draw_group() (by way of Geom$draw_panel()); point_handle_na()
  # calls GeomRibbon$handle_na(); legend_glyph() mirrors draw_key_smooth().
  expect_snapshot(print(body(environment(ggplot2::GeomRibbon$draw_group)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomRibbon$handle_na)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomSmooth$draw_group)$f)))
  expect_snapshot(print(body(environment(ggplot2::Geom$draw_panel)$f)))
  expect_snapshot(print(body(ggplot2::draw_key_smooth)))
})

test_that("upstream boxplot, violin and range drawing match what the full tier mirrors", {
  # R/render-ranges.R mirrors these draw methods (and GeomSegment's and
  # GeomPoint's, which they call); legend_glyph() mirrors the keys.
  expect_snapshot(print(body(environment(ggplot2::GeomBoxplot$draw_group)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomViolin$draw_group)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomCrossbar$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomErrorbar$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomLinerange$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomPointrange$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomSegment$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomPoint$draw_panel)$f)))
  for (f in c("draw_key_boxplot", "draw_key_crossbar", "draw_key_linerange", "draw_key_pointrange", "draw_key_vpath")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "ggplot2"))))
  }
})

test_that("upstream segment, reference line and rug drawing match what the full tier mirrors", {
  # R/render-segments.R mirrors these draw methods (GeomSegment's is
  # snapshotted above); legend_glyph() mirrors the keys.
  expect_snapshot(print(body(environment(ggplot2::GeomAbline$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomHline$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomVline$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomRug$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::GeomRug$handle_na)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordCartesian$backtransform_range)$f)))
  for (f in c("draw_key_abline", "draw_key_vline")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "ggplot2"))))
  }
})

test_that("upstream label drawing matches what the full tier mirrors", {
  # R/render-labels.R mirrors GeomLabel$draw_panel(), labelGrob() (with
  # titleGrob() and font_descent()), grid's rrpoints() and
  # draw_key_label() (GeomPolygon$draw_panel() is snapshotted above).
  expect_snapshot(print(body(environment(ggplot2::GeomLabel$draw_panel)$f)))
  for (f in c("labelGrob", "titleGrob", "font_descent", "draw_key_label")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "ggplot2"))))
  }
  expect_snapshot(print(body(utils::getFromNamespace("rrpoints", "grid"))))
  expect_snapshot(print(body(utils::getFromNamespace("roundCorner", "grid"))))
})

test_that("upstream raster drawing matches what the full tier mirrors", {
  # full_raster() (R/render-raster.R) and CellImage / RasterLayer
  # (alot-core/src/render/raster.rs, layers.rs) mirror
  # GeomRaster$draw_panel(); raster::resolution() mirrors resolution(). If
  # these fail, update the mirror and recheck test-render-raster.R, then
  # the snapshots.
  expect_snapshot(print(body(environment(ggplot2::GeomRaster$draw_panel)$f)))
  expect_snapshot(print(body(ggplot2::resolution)))
})

test_that("upstream theme and label resolution match what the render IR mirrors", {
  # resolve_theme() (R/render-ir.R) mirrors calc_element() and
  # combine_elements(); ir_labels() mirrors Layout$render()'s axis titles.
  # If these fail, update the mirror, then the snapshots.
  expect_snapshot(print(body(ggplot2::calc_element)))
  expect_snapshot(print(body(utils::getFromNamespace("combine_elements", "ggplot2"))))
  expect_snapshot(print(body(environment(ggplot2::Layout$render)$f)))
})

test_that("upstream table assembly matches what the Rust layout mirrors", {
  # layout_spec() (R/render-layout.R) and alot-core/src/render/layout.rs
  # mirror these for a single panel. If these fail, update the mirror, then
  # the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  expect_snapshot(print(body(utils::getS3method("ggplot_gtable", "ggplot2::ggplot_built", envir = asNamespace("ggplot2")))))
  for (f in c("table_add_tag", "table_add_legends", "plot_extent", "find_panel", "titleGrob", "widthDetails.titleGrob", "heightDetails.titleGrob", "rotate_just", "font_descent", "draw_axis_labels", "label_angle_heuristic", "panel_guides_grob")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  expect_snapshot(print(body(environment(ggplot2::FacetNull$draw_panels)$f)))
  expect_snapshot(print(body(environment(ggplot2::Facet$draw_labels)$f)))
  expect_snapshot(print(body(environment(ggplot2::Facet$set_panel_size)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$measure_grobs)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$override_elements)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$build_labels)$f)))
  expect_snapshot(print(body(environment(ggplot2::Guide$draw)$f)))
  expect_snapshot(print(body(environment(ggplot2::Layout$render_labels)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordCartesian$labels)$f)))
  expect_snapshot(print(body(gtable::gtable_add_padding)))
})

test_that("upstream panel and axis drawing match what the Rust drawers mirror", {
  # full_panel() (R/render-full.R), layout_axis() (R/render-layout.R) and
  # alot-core/src/render/{panel,axis,title}.rs mirror these. If these fail,
  # update the mirror, then the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  for (f in c("guide_grid", "breaks_as_grid", "axis_label_priority", "axis_label_priority_between", "element_render")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  expect_snapshot(print(body(environment(ggplot2::Coord$draw_panel)$f)))
  expect_snapshot(print(body(environment(ggplot2::Coord$render_fg)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordCartesian$render_bg)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordCartesian$transform)$f)))
  expect_snapshot(print(body(environment(ggplot2::Guide$build_ticks)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$build_ticks)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$build_decor)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$assemble_drawing)$f)))
  expect_snapshot(print(body(environment(ggplot2::GuideAxis$draw_early_exit)$f)))
})

test_that("upstream guide assembly matches what the legend drawers mirror", {
  # legend_boxes() and friends (R/render-legend.R) and
  # alot-core/src/render/legend.rs mirror these; guides' setup_params() and
  # setup_elements() are called, not mirrored. If these fail, update the
  # mirror, then the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  for (f in c("draw_key_point", "measure_legend_keys", "get_key_size", "set_key_size", "position_margin", "keep_key_data")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  guides <- gg_fn("Guides")
  for (m in c("assemble", "draw", "package_box")) {
    expect_snapshot(print(body(environment(guides[[m]])$f)))
  }
  expect_snapshot(print(body(environment(ggplot2::Guide$add_title)$f)))
  expect_snapshot(print(body(environment(ggplot2::Guide$setup_elements)$f)))
  for (m in c("setup_params", "setup_elements", "override_elements", "build_decor", "build_labels", "measure_grobs", "arrange_layout", "assemble_drawing")) {
    expect_snapshot(print(body(environment(ggplot2::GuideLegend[[m]])$f)))
  }
  for (m in c("setup_params", "setup_elements", "build_labels", "build_ticks", "build_decor", "measure_grobs")) {
    expect_snapshot(print(body(environment(ggplot2::GuideColourbar[[m]])$f)))
  }
})

test_that("upstream key glyphs, bins and colour steps match what the legend drawers mirror", {
  # legend_glyph(), legend_text_glyph(), legend_bar() and legend_bins()
  # (R/render-legend.R), the glyphs and bins of alot-core/src/render/legend.rs
  # and drawn_geom() (R/render.R) mirror these (R6.4). If these fail, update
  # the mirror, then the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  for (f in c("draw_key_polygon", "draw_key_rect", "draw_key_path", "draw_key_timeseries", "draw_key_text", "draw_key_blank", "set_draw_key")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  for (m in c("setup_params", "setup_elements", "build_labels", "build_ticks", "build_decor", "measure_grobs")) {
    expect_snapshot(print(body(environment(ggplot2::GuideBins[[m]])$f)))
  }
  expect_snapshot(print(body(environment(ggplot2::GuideColoursteps$build_decor)$f)))
})

test_that("upstream facet_wrap() assembly matches what the Rust layout mirrors", {
  # layout_facet() (R/render-layout.R) and FacetSpec in
  # alot-core/src/render/layout.rs mirror these. If these fail, update the
  # mirror, then the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  for (f in c("weave_tables_row", "weave_tables_col", "weave_axes", "measure_axes", "convertInd", "build_strip", "assemble_strips", "render_axes", "censor_labels", "max_height")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  for (m in c("draw_panels", "init_gtable")) {
    expect_snapshot(print(body(environment(ggplot2::Facet[[m]])$f)))
  }
  for (m in c("draw_panels", "attach_axes", "attach_strips", "format_strip_labels")) {
    expect_snapshot(print(body(environment(ggplot2::FacetWrap[[m]])$f)))
  }
})

test_that("upstream facet_grid() assembly matches what the Rust layout mirrors", {
  # layout_facet() (R/render-layout.R) and FacetSpec in
  # alot-core/src/render/layout.rs mirror these (R6.3), with the helpers of
  # the facet_wrap() snapshots above. If these fail, update the mirror, then
  # the snapshots.
  gg_fn <- function(f) utils::getFromNamespace(f, "ggplot2")
  for (f in c("seam_table", "table_has_grob", "panel_cols", "panel_rows", "panel_guides_grob")) {
    expect_snapshot(print(body(gg_fn(f))))
  }
  for (m in c("attach_axes", "attach_strips", "format_strip_labels")) {
    expect_snapshot(print(body(environment(ggplot2::FacetGrid[[m]])$f)))
  }
  for (m in c("render_axis_h", "render_axis_v")) {
    expect_snapshot(print(body(environment(ggplot2::CoordCartesian[[m]])$f)))
  }
})

test_that("upstream complete themes and element grobs match what the full tier covers", {
  # full_rect() and full_line() (R/render-full.R) mirror element_grob() for
  # element_rect and element_line; test-render-themes.R covers the
  # complete themes' elements and options (R6.2). If these fail, update the
  # mirror and recheck the themes' elements, then the snapshots.
  expect_snapshot(print(body(utils::getS3method("element_grob", "ggplot2::element_rect", envir = asNamespace("ggplot2")))))
  expect_snapshot(print(body(utils::getS3method("element_grob", "ggplot2::element_line", envir = asNamespace("ggplot2")))))
  for (f in c("theme_grey", "theme_bw", "theme_linedraw", "theme_light", "theme_dark", "theme_minimal", "theme_classic", "theme_void", "theme_test")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "ggplot2"))))
  }
})

test_that("upstream coords match what the full tier mirrors", {
  # full_flip(), full_transform() and full_panel() (R/render-full.R) mirror
  # CoordFlip$transform(), CoordTransform$transform() and guide_grid();
  # layout_axis() (R/render-layout.R) gives NaN keys no room as grid does.
  # If these fail, recheck test-render-coords.R, then the snapshots.
  expect_snapshot(print(body(environment(ggplot2::CoordFlip$transform)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordFlip$setup_panel_params)$f)))
  expect_snapshot(print(body(environment(ggplot2::CoordTransform$transform)$f)))
  expect_snapshot(print(body(utils::getFromNamespace("transform_value", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("guide_grid", "ggplot2"))))
})

test_that("upstream sf layer, stat and coord steps match the versions alot mirrors", {
  # Mirrored by R/sf.R. The same-CRS skip in the CoordSf$setup_data mirror
  # relies on what sf's st_transform.sfc and st_sfc rebuild. If these fail,
  # update the mirrors to match, then update the snapshots.
  skip_if_not_installed("sf")
  body_of <- function(obj, name) body(environment(obj[[name]])$f)
  LayerSf <- utils::getFromNamespace("LayerSf", "ggplot2")
  for (m in c("setup_layer", "compute_geom_1", "compute_geom_2")) {
    expect_snapshot(print(body_of(LayerSf, m)))
  }
  expect_snapshot(print(body(utils::getFromNamespace("detect_sf_type", "ggplot2"))))
  expect_snapshot(print(utils::getFromNamespace("sf_types", "ggplot2")))
  expect_snapshot(print(body_of(ggplot2::StatSf, "compute_layer")))
  expect_snapshot(print(body_of(ggplot2::StatSf, "compute_panel")))
  for (m in c("setup_params", "determine_crs", "setup_data", "record_bbox", "setup_panel_params")) {
    expect_snapshot(print(body_of(ggplot2::CoordSf, m)))
  }
  expect_snapshot(print(body_of(ggplot2::Coord, "setup_params")))
  expect_snapshot(print(body_of(ggplot2::Layout, "setup_panel_params")))
  expect_snapshot(print(body(utils::getFromNamespace("st_transform.sfc", "sf"))))
  expect_snapshot(print(body(sf::st_sfc)))
})

test_that("upstream sf drawing matches what the sf polygon drawer mirrors", {
  # R/render-sf.R and alot-core/src/render/sf.rs mirror GeomSf$draw_panel()
  # and handle_na(), CoordSf$transform() -> sf_rescale01() and what
  # sf::st_as_grob() gives for POLYGON and MULTIPOLYGON features (one
  # even-odd path per polygon, gpar repeated per polygon). render_ir()
  # relies on view_scales_from_graticule()'s bare ViewScale for an empty
  # graticule. If these fail, update the mirrors to match, then update the
  # snapshots.
  skip_if_not_installed("sf")
  body_of <- function(obj, name) body(environment(obj[[name]])$f)
  expect_snapshot(print(body_of(ggplot2::GeomSf, "draw_panel")))
  expect_snapshot(print(body_of(ggplot2::GeomSf, "handle_na")))
  expect_snapshot(print(body_of(ggplot2::CoordSf, "transform")))
  expect_snapshot(print(body(utils::getFromNamespace("sf_rescale01", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("fill_alpha", "ggplot2"))))
  expect_snapshot(print(body(utils::getFromNamespace("view_scales_from_graticule", "ggplot2"))))
  for (f in c("st_as_grob.sfc", "st_as_grob.sfc_POLYGON", "st_as_grob.sfc_MULTIPOLYGON", "st_as_grob.POLYGON",
    "st_as_grob.MULTIPOLYGON", "st_cast_sfc_default", "scalar_grobs", "expand_gp", "split_gp")) {
    expect_snapshot(print(body(utils::getFromNamespace(f, "sf"))))
  }
})
