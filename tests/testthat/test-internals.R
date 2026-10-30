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
