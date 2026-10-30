# Facet kernels for FacetWrap and FacetGrid (T5.1): panel layout and panel
# assignment.

# Mirrors FacetWrap$compute_layout (ggplot2 R/facet-wrap.R), with
# combine_vars() mirrored by facet_combine_vars().
kernel_facet_wrap_layout <- function(facet, data, params) {
  if (!identical(environment(facet$compute_layout)$f, environment(ggplot2::FacetWrap$compute_layout)$f)) {
    return(NULL)
  }
  vars <- params$facets
  if (length(vars) == 0) {
    return(NULL)
  }

  gg_check_facet_vars(names(vars), name = gg_snake_class(facet))

  base <- facet_combine_vars(data, params$plot_env, vars, drop = params$drop)
  if (is.null(base)) {
    return(NULL)
  }

  id <- gg_id(base, drop = TRUE)
  n <- attr(id, "n")

  dims <- gg_wrap_dims(n, params$nrow, params$ncol)
  layout <- gg_wrap_layout(id, dims, params$dir)

  panels <- vctrs::vec_cbind(layout, base)
  panels <- panels[order(panels$PANEL), , drop = FALSE]
  rownames(panels) <- NULL

  # Add scale identification
  panels$SCALE_X <- if (params$free$x) seq_len(n) else 1L
  panels$SCALE_Y <- if (params$free$y) seq_len(n) else 1L

  panels
}

# Mirrors FacetGrid$compute_layout (ggplot2 R/facet-grid-.R), with
# combine_vars() mirrored by facet_combine_vars().
kernel_facet_grid_layout <- function(facet, data, params) {
  if (!identical(environment(facet$compute_layout)$f, environment(ggplot2::FacetGrid$compute_layout)$f)) {
    return(NULL)
  }
  rows <- params$rows
  cols <- params$cols

  gg_check_facet_vars(names(rows), names(cols), name = gg_snake_class(facet))

  dups <- intersect(names(rows), names(cols))
  if (length(dups) > 0) {
    # Let upstream raise the error.
    return(NULL)
  }

  base_rows <- facet_combine_vars(data, params$plot_env, rows, drop = params$drop)
  if (is.null(base_rows)) {
    return(NULL)
  }
  if (!params$as.table) {
    rev_order <- function(x) factor(x, levels = rev(gg_ulevels(x)))
    base_rows[] <- lapply(base_rows, rev_order)
  }
  base_cols <- facet_combine_vars(data, params$plot_env, cols, drop = params$drop)
  if (is.null(base_cols)) {
    return(NULL)
  }
  base <- gg_df_grid(base_rows, base_cols)

  if (nrow(base) == 0) {
    return(gg_data_frame0(
      PANEL = factor(1L),
      ROW = 1L,
      COL = 1L,
      SCALE_X = 1L,
      SCALE_Y = 1L
    ))
  }

  # Add margins
  base <- gg_reshape_add_margins(base, list(names(rows), names(cols)), params$margins)
  base <- gg_unique0(base)

  # Create panel info dataset
  panel <- gg_id(base, drop = TRUE)
  panel <- factor(panel, levels = seq_len(attr(panel, "n")))

  rows <- if (!length(names(rows))) rep(1L, length(panel)) else gg_id(base[names(rows)], drop = TRUE)
  cols <- if (!length(names(cols))) rep(1L, length(panel)) else gg_id(base[names(cols)], drop = TRUE)

  panels <- gg_data_frame0(PANEL = panel, ROW = rows, COL = cols, base)
  panels <- panels[order(panels$PANEL), , drop = FALSE]
  rownames(panels) <- NULL

  panels$SCALE_X <- if (params$free$x) panels$COL else 1L
  panels$SCALE_Y <- if (params$free$y) panels$ROW else 1L

  panels
}

# Mirrors combine_vars (ggplot2 R/facet-.R). Rust first cuts each layer's
# facet values down to the first row of each distinct combination, under an
# equality at least as strict as vctrs' (see alot_core::facet::distinct);
# unique0() over those rows, in order, keeps the same rows as over all of
# them. Returns NULL (decline) if a layer has a column type Rust can't key.
facet_combine_vars <- function(data, env = emptyenv(), vars = NULL, drop = TRUE) {
  possible_columns <- gg_unique0(unlist(lapply(data, names)))
  if (length(vars) == 0) return(gg_data_frame0())

  # For each layer, compute the facet values
  values <- gg_compact(lapply(data, gg_eval_facets, facets = vars, possible_columns = possible_columns))
  for (i in seq_along(values)) {
    rows <- rs_facet_distinct_rows(values[[i]], nrow(values[[i]]))
    if (is.null(rows)) {
      return(NULL)
    }
    values[[i]] <- vctrs::vec_slice(values[[i]], rows)
  }

  # Form the base data.frame which contains all combinations of faceting
  # variables that appear in the data
  has_all <- unlist(lapply(values, length)) == length(vars)
  if (!any(has_all)) {
    # Let upstream raise the error.
    return(NULL)
  }

  base <- gg_unique0(gg_vec_rbind0(!!!values[has_all]))
  if (!drop) {
    base <- gg_unique_combs(base)
  }

  # Systematically add on missing combinations
  for (value in values[!has_all]) {
    if (gg_empty(value)) next;

    old <- base[setdiff(names(base), names(value))]
    new <- gg_unique0(value[intersect(names(base), names(value))])
    if (drop) {
      new <- gg_unique_combs(new)
    }
    base <- gg_unique0(gg_vec_rbind0(base, gg_df_grid(old, new)))
  }

  if (gg_empty(base)) {
    # Let upstream raise the error.
    return(NULL)
  }

  base
}

# Mirrors map_facet_data (ggplot2 R/facet-.R), the map_data method of
# FacetWrap and FacetGrid. R evaluates the facet expressions, turns them into
# factors and duplicates rows for missing facet variables as upstream does;
# Rust replaces join_keys() + match() to find each row's panel. Declines
# where no join happens (empty data, no facet variables, fixed layers, no
# facet values) and for margins.
kernel_facet_map_data <- function(facet, data, layout, params) {
  if (!identical(environment(facet$map_data)$f, gg("map_facet_data"))) {
    return(NULL)
  }
  if (gg_empty(data)) {
    return(NULL)
  }

  vars <- params$facets %||% c(params$rows, params$cols)
  if (length(vars) == 0) {
    return(NULL)
  }

  grid_layout <- all(c("rows", "cols") %in% names(params))
  layer_layout <- attr(data, "layout")
  if (identical(layer_layout, "fixed")) {
    return(NULL)
  }

  # Compute faceting values
  facet_vals <- gg_eval_facets(vars, data, params$.possible_columns)

  include_margins <- !isFALSE(params$margins %||% FALSE) &&
    nrow(facet_vals) == nrow(data) && grid_layout
  if (include_margins) {
    return(NULL)
  }

  # If we need to fix rows or columns, we make the corresponding faceting
  # variables missing on purpose
  if (grid_layout) {
    if (identical(layer_layout, "fixed_rows")) {
      facet_vals <- facet_vals[setdiff(names(facet_vals), names(params$cols))]
    }
    if (identical(layer_layout, "fixed_cols")) {
      facet_vals <- facet_vals[setdiff(names(facet_vals), names(params$rows))]
    }
  }

  # If any faceting variables are missing, add them in by
  # duplicating the data
  missing_facets <- setdiff(names(vars), names(facet_vals))
  if (length(missing_facets) > 0) {

    to_add <- gg_unique0(layout[missing_facets])

    data_rep  <- rep.int(seq_len(nrow(data)), nrow(to_add))
    facet_rep <- rep(seq_len(nrow(to_add)), each = nrow(data))

    data <- gg_unrowname(data[data_rep, , drop = FALSE])
    facet_vals <- gg_unrowname(vctrs::vec_cbind(
      gg_unrowname(facet_vals[data_rep, , drop = FALSE]),
      gg_unrowname(to_add[facet_rep, , drop = FALSE])
    ))
  }

  if (nrow(facet_vals) < 1) {
    return(NULL)
  }

  # Upstream turns each variable into a factor with addNA() and joins on
  # labels (as match() does, so NA matches NA). Rust joins on the codes of
  # the data factor instead, with NA codes in the NA level (an extra one if
  # there is none), as addNA() would code them; layout values are matched to
  # the same levels. Non-factor columns go through factor() as upstream.
  by <- names(vars)
  if (!all(by %in% names(layout))) {
    return(NULL)
  }
  facet_vals <- lapply(facet_vals[by], function(x) {
    if (is.factor(x)) x else gg_as_unordered_factor(x)
  })
  lvs <- lapply(facet_vals, levels)
  na <- vapply(lvs, function(lv) match(NA_character_, lv, nomatch = length(lv) + 1L), integer(1))
  cards <- pmax(lengths(lvs), na)
  layout_codes <- lapply(seq_along(by), function(i) {
    l <- gg_as_unordered_factor(layout[[by[i]]])
    level_codes <- match(levels(l), lvs[[i]])
    level_codes[is.na(levels(l))] <- na[i]
    codes <- level_codes[as.integer(l)]
    codes[is.na(l)] <- na[i]
    codes
  })
  panel <- gg_as_unordered_factor(layout$PANEL)
  codes <- rs_facet_panels(unname(facet_vals), unname(na), unname(cards), layout_codes, as.integer(panel))
  if (is.null(codes)) {
    return(NULL)
  }
  # As panel[codes] would: `[.factor` keeps contrasts, levels and class.
  attr(codes, "contrasts") <- attr(panel, "contrasts")
  attr(codes, "levels") <- attr(panel, "levels")
  class(codes) <- oldClass(panel)

  # Add PANEL variable
  data$PANEL <- codes

  # Filter panels when layer_layout is an integer
  if (rlang::is_integerish(layer_layout)) {
    data <- vctrs::vec_slice(data, data$PANEL %in% layer_layout)
  }

  data
}
