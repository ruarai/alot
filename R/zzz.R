.onLoad <- function(libname, pkgname) {
  register_kernel("scale_train", "ScaleContinuousPosition", kernel_train_continuous)
  register_kernel("scale_train", "ScaleDiscretePosition", kernel_train_discrete)
  register_kernel("scale_map", "ScaleContinuousPosition", kernel_map_continuous)
  register_kernel("scale_map", "ScaleDiscretePosition", kernel_map_discrete)
  # Every class whose transform is ggplot2's default_transform.
  for (class in c("ScaleContinuous", "ScaleContinuousPosition", "ScaleContinuousIdentity",
                  "ScaleBinned", "ScaleBinnedPosition")) {
    register_kernel("scale_transform", class, kernel_transform)
  }
}
