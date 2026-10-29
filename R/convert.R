# Rebuilds layer data from the named column list a Rust kernel returns
# (built by alot-r/src/convert.rs). Columns that `template` has come first,
# in its order, then new ones in the order returned. Mirrors ggplot2's
# compute methods: data_frame0(), then merge_attrs() to restore the frame's
# attributes (ggplot2 R/utilities.R).
rebuild_frame <- function(cols, template) {
  nms <- names(cols)
  cols <- cols[c(intersect(names(template), nms), setdiff(nms, names(template)))]
  gg_merge_attrs(rlang::inject(gg_data_frame0(!!!cols)), template)
}
