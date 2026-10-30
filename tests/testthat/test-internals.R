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
