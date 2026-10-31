.onLoad <- function(libname, pkgname) {
  register_kernel("scale_train", "ScaleContinuousPosition", kernel_train_continuous)
  register_kernel("scale_train", "ScaleDiscretePosition", kernel_train_discrete)
  register_kernel("scale_map", "ScaleContinuousPosition", kernel_map_continuous)
  register_kernel("scale_map", "ScaleDiscretePosition", kernel_map_discrete)
  register_kernel("np_train", "ScaleContinuous", kernel_np_train_continuous)
  register_kernel("np_map", "ScaleContinuous", kernel_np_map_continuous)
  register_kernel("np_train", "ScaleDiscrete", kernel_np_train_discrete)
  register_kernel("np_map", "ScaleDiscrete", kernel_np_map_discrete)
  register_kernel("facet_compute_layout", "FacetWrap", kernel_facet_wrap_layout)
  register_kernel("facet_compute_layout", "FacetGrid", kernel_facet_grid_layout)
  register_kernel("facet_map_data", "FacetWrap", kernel_facet_map_data)
  register_kernel("facet_map_data", "FacetGrid", kernel_facet_map_data)
  for (class in c("CoordCartesian", "CoordFlip", "CoordFixed")) {
    register_kernel("setup_panel_params", class, kernel_panel_params)
  }
  for (class in c("CoordCartesian", "CoordFixed")) {
    register_kernel("setup_panel_guides", class, kernel_panel_guides)
  }
  # Every class whose transform is ggplot2's default_transform.
  for (class in c("ScaleContinuous", "ScaleContinuousPosition", "ScaleContinuousIdentity",
                  "ScaleBinned", "ScaleBinnedPosition")) {
    register_kernel("scale_transform", class, kernel_transform)
  }
}
