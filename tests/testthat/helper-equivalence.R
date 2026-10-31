# Evaluate `expr`, muffling its warnings and messages. Returns the value and
# the conditions as "<kind>: <text>" strings, in the order they were signalled.
capture_conditions <- function(expr) {
  conditions <- character()
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      conditions <<- c(conditions, paste0("warning: ", conditionMessage(w)))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      conditions <<- c(conditions, paste0("message: ", conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  list(value = value, conditions = conditions)
}

# Build `p` with both alot and ggplot2 under the same seed and check the
# results and the warnings and messages they signal are identical.
expect_build_equal <- function(p, seed = 1) {
  set.seed(seed)
  a <- capture_conditions(alot_build(p))
  set.seed(seed)
  b <- capture_conditions(ggplot2::ggplot_build(p))
  expect_identical(a$conditions, b$conditions)
  a <- a$value
  b <- b$value
  expect_s3_class(a, "ggplot_built")
  expect_equal(a@data, b@data, tolerance = 1e-8)
  expect_equal(a@layout$layout, b@layout$layout)
  expect_equal(a@layout$panel_params, b@layout$panel_params, tolerance = 1e-8)
  expect_equal(a@plot@labels, b@plot@labels)
  # Rendering must succeed, unless ggplot2's own build fails to render too
  # (e.g. free scales with a fixed aspect ratio); then the errors must match.
  gtable_error <- function(built) {
    tryCatch({
      suppressWarnings(ggplot2::ggplot_gtable(built))
      NULL
    }, error = conditionMessage)
  }
  expect_identical(gtable_error(a), gtable_error(b))
  invisible(a)
}
