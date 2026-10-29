# Unexported ggplot2 helpers used to mirror `ggplot2:::build_ggplot`.
# alot targets ggplot2 4.0.x; tests/testthat/test-internals.R snapshots the
# upstream build function so an upstream change fails loudly.

gg <- function(name) utils::getFromNamespace(name, "ggplot2")

gg_attach_plot_env   <- function(...) gg("attach_plot_env")(...)
gg_try_prop          <- function(...) gg("try_prop")(...)
gg_plot_clone        <- function(...) gg("plot_clone")(...)
gg_by_layer          <- function(...) gg("by_layer")(...)
gg_create_layout     <- function(...) gg("create_layout")(...)
gg_setup_plot_labels <- function(...) gg("setup_plot_labels")(...)
gg_ignore_data       <- function(...) gg(".ignore_data")(...)
gg_expose_data       <- function(...) gg(".expose_data")(...)
gg_plot_theme        <- function(...) gg("plot_theme")(...)
gg_get_alt_text      <- function(...) gg("get_alt_text")(...)
gg_class_ggplot_built <- function(...) gg("class_ggplot_built")(...)
gg_empty             <- function(...) gg("empty")(...)
gg_data_frame0       <- function(...) gg("data_frame0")(...)
gg_merge_attrs       <- function(...) gg("merge_attrs")(...)
