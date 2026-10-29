# Kernel registry and dispatch.
#
# Kernels are keyed by pipeline step and ggproto class name, e.g.
# register_kernel("stat", "StatBin", fn). A kernel is used only when the
# object's first class is exactly the registered class, so user subclasses
# that override methods always fall back to ggplot2. A kernel may return
# NULL to decline (e.g. unsupported params), which also falls back.

kernels <- new.env(parent = emptyenv())
trace_env <- new.env(parent = emptyenv())
trace_env$records <- NULL

register_kernel <- function(step, class, fn) {
  kernels[[paste0(step, ":", class)]] <- fn
  invisible(fn)
}

find_kernel <- function(step, obj) {
  cls <- class(obj)[1]
  kernels[[paste0(step, ":", cls)]]
}

record_trace <- function(step, class, path) {
  if (is.null(trace_env$records)) return(invisible())
  trace_env$records[[length(trace_env$records) + 1L]] <-
    list(step = step, class = class, path = path)
  invisible()
}

# Run `kernel` for `obj` at `step`, else `fallback()`.
dispatch <- function(step, obj, args, fallback) {
  cls <- class(obj)[1]
  kernel <- find_kernel(step, obj)
  if (!is.null(kernel)) {
    out <- do.call(kernel, args)
    if (!is.null(out)) {
      record_trace(step, cls, "rust")
      return(out)
    }
  }
  record_trace(step, cls, "ggplot2")
  fallback()
}

#' Report which components of a plot build ran in Rust
#'
#' @param plot A ggplot object.
#' @return A data frame with one row per dispatched component: the pipeline
#'   `step`, the ggproto `class`, and the `path` taken (`"rust"` or
#'   `"ggplot2"`).
#' @export
alot_coverage <- function(plot) {
  old <- trace_env$records
  trace_env$records <- list()
  on.exit(trace_env$records <- old)
  alot_build(plot)
  recs <- trace_env$records
  data.frame(
    step = vapply(recs, `[[`, "", "step"),
    class = vapply(recs, `[[`, "", "class"),
    path = vapply(recs, `[[`, "", "path")
  )
}
