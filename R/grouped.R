# Grouped-kernel driver, R side. A Rust kernel runs once per PANEL x group
# in one call (alot-core/src/group.rs, alot-r/src/grouped.rs); these helpers
# mirror the R code around compute_group() / compute_panel(): Stat$compute_layer
# and Stat$compute_panel (ggplot2 R/stat-.R), Position$compute_layer
# (ggplot2 R/position-.R), and dapply() (ggplot2 R/compat-plyr.R).

# Column classes whose vctrs equality is that of their storage, which is what
# the driver compares. Anything else declines.
grouped_classes <- c("factor", "ordered", "Date", "POSIXct", "POSIXt", "mapped_discrete", "AsIs")

grouped_supported <- function(data) {
  plain <- function(x) {
    typeof(x) %in% c("double", "integer", "logical", "character") &&
      is.null(dim(x)) &&
      all(setdiff(class(x), c(typeof(x), "numeric")) %in% grouped_classes)
  }
  is.factor(data$PANEL) && is.integer(data$group) &&
    all(vapply(data, plain, logical(1)))
}

# Mirrors Stat$compute_layer and Stat$compute_panel (ggplot2 R/stat-.R) for a
# stat whose compute_group() is a Rust kernel. `run(data, params)` calls the
# kernel's entry point, which returns grouped::run_stat()'s list or NULL to
# decline. Returns NULL to decline before any condition is signalled, so the
# fallback's warnings are not doubled. The "Computation failed" handler is
# not mirrored: a kernel error is a bug, not a user-facing failure.
stat_compute_grouped <- function(stat, data, params, run) {
  gg_check_required_aesthetics(
    stat$required_aes,
    c(names(data), names(params)),
    gg_snake_class(stat)
  )
  required_aes <- intersect(
    names(data),
    unlist(strsplit(stat$required_aes, "|", fixed = TRUE))
  )
  # remove_missing() warns; hold the warnings until the kernel has accepted.
  warnings <- list()
  data <- withCallingHandlers(
    ggplot2::remove_missing(data, params$na.rm,
      c(required_aes, stat$non_missing_aes),
      gg_snake_class(stat),
      finite = TRUE
    ),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      tryInvokeRestart("muffleWarning")
    }
  )
  params <- params[intersect(names(params), stat$parameters())]

  # Empty input warns in dapply() for some layouts; leave it to ggplot2.
  if (nrow(data) == 0 || !grouped_supported(data)) return(NULL)
  out <- run(data, params)
  if (is.null(out)) return(NULL)
  for (w in warnings) warning(w)
  grouped_stat_frame(out, data, stat$dropped_aes)
}

# Assembles run_stat()'s output as compute_panel() and dapply() do: per
# panel, the kernel columns then the constant input columns; columns not
# constant within a group are dropped from that panel, with compute_panel's
# warning; panels are then row-bound.
grouped_stat_frame <- function(out, data, dropped_aes) {
  n_panels <- length(out$panel_rows)
  if (n_panels == 0) return(gg_data_frame0())
  non_constant <- matrix(out$non_constant, nrow = n_panels, byrow = TRUE,
                         dimnames = list(NULL, names(data)))
  old <- setdiff(names(data), names(out$new))
  keep <- vector("list", n_panels)
  for (p in seq_len(n_panels)) {
    dropped <- old[non_constant[p, old]]
    keep[[p]] <- setdiff(old, dropped)
    dropped <- dropped[!dropped %in% dropped_aes]
    if (length(dropped) > 0) {
      cli::cli_warn(c(
        "The following aesthetics were dropped during statistical transformation: {.field {dropped}}.",
        "i" = "This can happen when ggplot fails to infer the correct grouping structure in the data.",
        "i" = "Did you forget to specify a {.code group} aesthetic or to convert a numerical variable into a factor?"
      ))
    }
  }

  # compute_panel() carries old[rep(1, n), ]: `[` per column, which keeps
  # classes but drops other attributes of bare vectors.
  carried <- old[old %in% unlist(keep)]
  cols <- lapply(unclass(data)[carried], function(x) x[out$carry])
  frame <- rlang::inject(gg_data_frame0(!!!out$new, !!!cols))

  if (length(unique(keep)) > 1) {
    # Panels differ in the columns they keep: bind them as dapply() does,
    # which orders columns by first appearance and fills the gaps with NA.
    ends <- cumsum(out$panel_rows)
    pieces <- lapply(seq_len(n_panels), function(p) {
      rows <- seq.int(ends[p] - out$panel_rows[p] + 1L, length.out = out$panel_rows[p])
      vctrs::vec_slice(frame[c(names(out$new), keep[[p]])], rows)
    })
    return(rlang::inject(vctrs::vec_rbind(!!!pieces)))
  }
  # compute_panel() binds its groups and dapply() its panels, unless there
  # is a single PANEL level.
  many <- any(out$panel_groups > 1) || (!single_panel_level(data) && n_panels > 1)
  grouped_rbind(frame, if (many) out$panel_rows[1] else NULL)
}

# dapply()'s shortcut: one PANEL level means no split and no row-binding.
single_panel_level <- function(data) {
  identical(as.character(levels(data$PANEL)), "1")
}

# vec_rbind() keeps bare vectors' attributes when it binds a single frame
# but drops them (and some classes) when it binds several, whatever their
# number. Splitting `frame` in two after row `split` gives the same result
# as binding the original pieces, without slicing every one of them.
grouped_rbind <- function(frame, split = NULL) {
  if (is.null(split)) return(vctrs::vec_rbind(frame))
  rows <- seq_len(split)
  vctrs::vec_rbind(vctrs::vec_slice(frame, rows), vctrs::vec_slice(frame, -rows))
}

# Mirrors Position$compute_layer (ggplot2 R/position-.R): dapply() over
# PANEL around a compute_panel() that modifies columns in place and keeps
# every row. `run(data)` calls the kernel's entry point, which returns
# grouped::run_position()'s list or NULL to decline. Kernel columns replace
# the input's in place; new ones are appended.
position_compute_grouped <- function(data, run) {
  if (nrow(data) == 0 || !is.factor(data$PANEL)) return(NULL)
  out <- run(data)
  if (is.null(out)) return(NULL)
  res <- unclass(vctrs::vec_slice(data, out$rows))
  res[names(out$new)] <- out$new
  res <- rlang::inject(gg_data_frame0(!!!res))
  if (single_panel_level(data)) return(res)
  many <- length(out$panel_rows) > 1
  grouped_rbind(res, if (many) out$panel_rows[1] else NULL)
}
