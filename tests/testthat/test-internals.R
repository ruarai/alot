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
