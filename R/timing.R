# Per-step build timing for the benchmark suites (inst/bench/step-profile.R).
#
# build_plot() wraps each step of ggplot2:::build_ggplot in timed(). Timing
# is off unless step_times() is collecting, so the cost otherwise is one
# NULL check per step. With options(alot.kernels = FALSE) every dispatch
# falls back, so the same timers measure ggplot2's own methods for each step.

timing_env <- new.env(parent = emptyenv())
timing_env$times <- NULL

timed <- function(step, expr) {
  if (is.null(timing_env$times)) {
    return(expr)
  }
  start <- Sys.time()
  out <- expr
  elapsed <- as.double(Sys.time() - start, units = "secs")
  timing_env$times[[step]] <- (timing_env$times[[step]] %||% 0) + elapsed
  out
}

# Build `plot` with alot and return the seconds spent in each step, in
# pipeline order. Steps that run twice (train_position, map_position, ...)
# are timed separately as `_1` / `_2`.
step_times <- function(plot, kernels = TRUE) {
  old_times <- timing_env$times
  old_opt <- options(alot.kernels = kernels)
  on.exit({
    timing_env$times <- old_times
    options(old_opt)
  })
  timing_env$times <- list()
  alot_build(plot)
  times <- timing_env$times
  data.frame(step = names(times), seconds = unlist(times, use.names = FALSE))
}
