# upstream build function matches the version alot mirrors

    Code
      print(body(utils::getFromNamespace("build_ggplot", "ggplot2")))
    Output
      {
          plot <- plot_clone(plot)
          if (length(plot@layers) == 0) {
              plot <- plot + geom_blank()
          }
          layers <- plot@layers
          data <- rep(list(NULL), length(layers))
          scales <- plot@scales
          data <- by_layer(function(l, d) l$layer_data(plot@data), 
              layers, data, "computing layer data")
          data <- by_layer(function(l, d) l$setup_layer(d, plot), layers, 
              data, "setting up layer")
          layout <- create_layout(plot@facet, plot@coordinates, plot@layout)
          data <- layout$setup(data, plot@data, plot@plot_env)
          data <- by_layer(function(l, d) l$compute_aesthetics(d, plot), 
              layers, data, "computing aesthetics")
          plot@labels <- setup_plot_labels(plot, layers, data)
          data <- .ignore_data(data)
          data <- lapply(data, scales$transform_df)
          scale_x <- function() scales$get_scales("x")
          scale_y <- function() scales$get_scales("y")
          layout$train_position(data, scale_x(), scale_y())
          data <- layout$map_position(data)
          data <- .expose_data(data)
          data <- by_layer(function(l, d) l$compute_statistic(d, layout), 
              layers, data, "computing stat")
          data <- by_layer(function(l, d) l$map_statistic(d, plot), 
              layers, data, "mapping stat to aesthetics")
          plot@scales$add_missing(c("x", "y"), plot@plot_env)
          data <- by_layer(function(l, d) l$compute_geom_1(d), layers, 
              data, "setting up geom")
          data <- by_layer(function(l, d) l$compute_position(d, layout), 
              layers, data, "computing position")
          data <- .ignore_data(data)
          layout$reset_scales()
          layout$train_position(data, scale_x(), scale_y())
          layout$setup_panel_params()
          data <- layout$map_position(data)
          layout$setup_panel_guides(plot@guides, plot@layers)
          plot@theme <- plot_theme(plot)
          npscales <- scales$non_position_scales()
          if (npscales$n() > 0) {
              npscales$set_palettes(plot@theme)
              lapply(data, npscales$train_df)
              plot@guides <- plot@guides$build(npscales, plot@layers, 
                  plot@labels, data, plot@theme)
              data <- lapply(data, npscales$map_df)
          }
          else {
              plot@guides <- plot@guides$get_custom()
          }
          data <- .expose_data(data)
          data <- by_layer(function(l, d) l$compute_geom_2(d, theme = plot@theme), 
              layers, data, "setting up geom aesthetics")
          data <- by_layer(function(l, d) l$finish_statistics(d), layers, 
              data, "finishing layer stat")
          data <- layout$finish_data(data)
          plot@labels$alt <- get_alt_text(plot)
          build <- class_ggplot_built(data = data, layout = layout, 
              plot = plot)
          class(build) <- union(c("ggplot2::ggplot_built", "ggplot_built"), 
              class(build))
          build
      }

# upstream grouped compute methods match the versions alot mirrors

    Code
      print(body(environment(ggplot2::Stat$compute_layer)$f))
    Output
      {
          check_required_aesthetics(self$required_aes, c(names(data), 
              names(params)), snake_class(self))
          required_aes <- intersect(names(data), unlist(strsplit(self$required_aes, 
              "|", fixed = TRUE)))
          data <- remove_missing(data, params$na.rm, c(required_aes, 
              self$non_missing_aes), snake_class(self), finite = TRUE)
          params <- params[intersect(names(params), self$parameters())]
          args <- c(list(data = quote(data), scales = quote(scales)), 
              params)
          dapply(data, "PANEL", function(data) {
              scales <- layout$get_scales(data$PANEL[1])
              try_fetch(inject(self$compute_panel(data = data, scales = scales, 
                  !!!params)), error = function(cnd) {
                  cli::cli_warn("Computation failed in {.fn {snake_class(self)}}.", 
                      parent = cnd)
                  data_frame0()
              })
          })
      }

---

    Code
      print(body(environment(ggplot2::Stat$compute_panel)$f))
    Output
      {
          if (empty(data)) 
              return(data_frame0())
          groups <- split(data, data$group)
          stats <- lapply(groups, function(group) {
              self$compute_group(data = group, scales = scales, ...)
          })
          non_constant_columns <- character(0)
          stats <- mapply(function(new, old) {
              if (empty(new)) 
                  return(data_frame0())
              old <- old[, !(names(old) %in% names(new)), drop = FALSE]
              non_constant <- vapply(old, vec_unique_count, integer(1)) > 
                  1L
              non_constant_columns <<- c(non_constant_columns, names(old)[non_constant])
              vec_cbind(new, old[rep(1, nrow(new)), , drop = FALSE])
          }, stats, groups, SIMPLIFY = FALSE)
          non_constant_columns <- unique0(non_constant_columns)
          dropped <- non_constant_columns[!non_constant_columns %in% 
              self$dropped_aes]
          if (length(dropped) > 0) {
              cli::cli_warn(c("The following aesthetics were dropped during statistical transformation: {.field {dropped}}.", 
                  i = "This can happen when ggplot fails to infer the correct grouping structure in the data.", 
                  i = "Did you forget to specify a {.code group} aesthetic or to convert a numerical variable into a factor?"))
          }
          data_new <- vec_rbind0(!!!stats)
          data_new[, !names(data_new) %in% non_constant_columns, drop = FALSE]
      }

---

    Code
      print(body(environment(ggplot2::Position$compute_layer)$f))
    Output
      {
          dapply(data, "PANEL", function(data) {
              if (empty(data)) 
                  return(data_frame0())
              scales <- layout$get_scales(data$PANEL[1])
              self$compute_panel(data = data, params = params, scales = scales)
          })
      }

---

    Code
      print(body(utils::getFromNamespace("dapply", "ggplot2")))
    Output
      {
          grouping_cols <- .subset(df, by)
          fallback_order <- unique0(c(by, names(df)))
          apply_fun <- function(x) {
              res <- fun(x, ...)
              if (is.null(res)) 
                  return(res)
              if (length(res) == 0) 
                  return(data_frame0())
              vars <- lapply(setNames(by, by), function(col) .subset2(x, 
                  col)[1])
              if (is.matrix(res)) 
                  res <- split_matrix(res)
              if (is.null(names(res))) 
                  names(res) <- paste0("V", seq_along(res))
              if (all(by %in% names(res))) 
                  return(data_frame0(!!!unclass(res)))
              res <- modify_list(unclass(vars), unclass(res))
              res <- res[intersect(c(fallback_order, names(res)), names(res))]
              data_frame0(!!!res)
          }
          has_single_group <- all(vapply(grouping_cols, function(x) identical(as.character(levels(x) %||% 
              attr(x, "n")), "1"), logical(1)))
          if (has_single_group) {
              return(apply_fun(df))
          }
          ids <- id(grouping_cols, drop = drop)
          group_rows <- split_with_index(seq_len(nrow(df)), ids)
          result <- lapply(seq_along(group_rows), function(i) {
              cur_data <- vec_slice(df, group_rows[[i]])
              apply_fun(cur_data)
          })
          vec_rbind0(!!!result)
      }

# upstream discrete position training matches what alot relies on

    Code
      print(body(environment(ggplot2::ScaleDiscretePosition$train)$f))
    Output
      {
          if (is_discrete(x)) {
              self$range$train(x, drop = self$drop, na.rm = !self$na.translate)
          }
          else {
              self$range_c$train(x)
          }
      }

---

    Code
      print(body(utils::getFromNamespace("discrete_range", "scales")))
    Output
      {
          new_is_factor <- is.factor(new)
          old_is_factor <- is.factor(old) || isTRUE(fct)
          new <- clevels(new, drop = drop, na.rm = na.rm)
          if (is.null(old)) {
              return(new)
          }
          if (old_is_factor && !is.factor(old)) {
              old <- factor(old, old)
          }
          if (!is.character(old)) {
              old <- clevels(old, na.rm = na.rm)
          }
          else {
              old <- sort(old, na.last = if (na.rm) 
                  NA
              else TRUE)
          }
          if (new_is_factor && !old_is_factor) {
              tmp <- old
              old <- new
              new <- tmp
              tmp <- old_is_factor
              old_is_factor <- new_is_factor
              new_is_factor <- tmp
          }
          new_levels <- setdiff(new, old)
          if (length(new_levels) == 0) {
              return(old)
          }
          range <- c(old, new_levels)
          if (old_is_factor) {
              return(range)
          }
          sort(range, na.last = if (na.rm) 
              NA
          else TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace("clevels", "scales")))
    Output
      {
          if (is.null(x)) {
              character()
          }
          else if (!is.null(levels(x))) {
              if (drop && !is.character(x)) 
                  x <- droplevels(x)
              values <- levels(x)
              if (na.rm) {
                  values <- values[!is.na(values)]
              }
              else if (any(is.na(x))) {
                  values <- c(values, NA)
              }
              values
          }
          else {
              sort(unique(x), na.last = if (na.rm) 
                  NA
              else TRUE)
          }
      }

---

    Code
      print(body(scales::train_continuous))
    Output
      {
          if (is.null(new)) {
              return(existing)
          }
          new <- try_fetch(suppressWarnings(range(new, na.rm = TRUE, 
              finite = TRUE)), error = function(cnd) new)
          if (is.factor(new) || !typeof(new) %in% c("integer", "double")) {
              example <- unique(new)
              example <- example[seq_len(pmin(length(example), 5))]
              cli::cli_abort(c("Discrete value supplied to a continuous scale.", 
                  i = "Example values: {.and {.val {example}}}."), 
                  call = call)
          }
          suppressWarnings(range(existing, as.numeric(new), na.rm = TRUE, 
              finite = TRUE))
      }

# upstream position mapping matches the versions alot mirrors

    Code
      print(body(environment(ggplot2::Layout$map_position)$f))
    Output
      {
          layout <- self$layout
          lapply(data, function(layer_data) {
              match_id <- NULL
              x_vars <- intersect(self$panel_scales_x[[1]]$aesthetics, 
                  names(layer_data))
              if (length(x_vars) > 0) {
                  match_id <- match(layer_data$PANEL, layout$PANEL)
                  names(x_vars) <- x_vars
                  SCALE_X <- layout$SCALE_X[match_id]
                  new_x <- scale_apply(layer_data, x_vars, "map", SCALE_X, 
                      self$panel_scales_x)
                  layer_data[, x_vars] <- new_x
              }
              y_vars <- intersect(self$panel_scales_y[[1]]$aesthetics, 
                  names(layer_data))
              if (length(y_vars) > 0) {
                  if (is.null(match_id)) {
                      match_id <- match(layer_data$PANEL, layout$PANEL)
                  }
                  names(y_vars) <- y_vars
                  SCALE_Y <- layout$SCALE_Y[match_id]
                  new_y <- scale_apply(layer_data, y_vars, "map", SCALE_Y, 
                      self$panel_scales_y)
                  layer_data[, y_vars] <- new_y
              }
              layer_data
          })
      }

---

    Code
      print(body(utils::getFromNamespace("scale_apply", "ggplot2")))
    Output
      {
          if (length(vars) == 0) 
              return()
          if (nrow(data) == 0) 
              return()
          if (anyNA(scale_id)) {
              cli::cli_abort("{.arg scale_id} must not contain any {.val NA}.")
          }
          scale_index <- split_with_index(seq_along(scale_id), scale_id, 
              length(scales))
          lapply(vars, function(var) {
              pieces <- lapply(seq_along(scales), function(i) {
                  scales[[i]][[method]](vec_slice(data[[var]], scale_index[[i]]))
              })
              pieces[lengths(pieces) == 0] <- NULL
              o <- order(unlist(scale_index))[seq_len(sum(lengths(pieces)))]
              vec_c(!!!pieces)[o]
          })
      }

---

    Code
      print(body(environment(ggplot2::ScaleContinuousPosition$map)$f))
    Output
      {
          scaled <- as.numeric(self$oob(x, limits))
          if (!anyNA(scaled)) {
              return(scaled)
          }
          vec_assign(scaled, is.na(scaled), self$na.value)
      }

---

    Code
      print(body(environment(ggplot2::ScaleDiscretePosition$map)$f))
    Output
      {
          if (inherits(x, "AsIs")) {
              return(x)
          }
          if (is_discrete(x)) {
              values <- self$palette(length(limits))
              if (!is.numeric(values)) {
                  cli::cli_abort("The {.arg palette} function must return a {.cls numeric} vector.", 
                      call = self$call)
              }
              if (length(values) < length(limits)) {
                  cli::cli_abort("The {.arg palette} function must return at least \\\n            {length(limits)} values.", 
                      call = self$call)
              }
              x <- values[match(as.character(x), limits)]
          }
          mapped_discrete(x)
      }

---

    Code
      print(body(utils::getFromNamespace("mapped_discrete", "ggplot2")))
    Output
      {
          if (is.null(x)) 
              return(NULL)
          new_mapped_discrete(vec_cast(x, double()))
      }

---

    Code
      print(body(scales::oob_censor))
    Output
      {
          force(range)
          finite <- if (only.finite) 
              is.finite(x)
          else TRUE
          x[finite & x < range[1]] <- NA_real_
          x[finite & x > range[2]] <- NA_real_
          x
      }

---

    Code
      print(body(scales::oob_censor_any))
    Output
      {
          oob_censor(x, range = range, only.finite = FALSE)
      }

---

    Code
      print(body(scales::oob_squish))
    Output
      {
          force(range)
          finite <- if (only.finite) 
              is.finite(x)
          else TRUE
          x[finite & x < range[1]] <- range[1]
          x[finite & x > range[2]] <- range[2]
          x
      }

---

    Code
      print(body(scales::oob_squish_any))
    Output
      {
          oob_squish(x, range, only.finite = FALSE)
      }

---

    Code
      print(body(scales::oob_squish_infinite))
    Output
      {
          force(range)
          x[x == -Inf] <- range[1]
          x[x == Inf] <- range[2]
          x
      }

---

    Code
      print(body(scales::oob_keep))
    Output
      {
          x
      }

# upstream scale transformation matches the versions alot mirrors

    Code
      print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$
        transform_df)$f))
    Output
      {
          if (empty(df)) {
              return(df)
          }
          idx_skip <- vapply(self$scales, function(x) {
              transformation <- x$get_transformation()
              has_default_transform(x) && (is.null(transformation) || 
                  identical(transformation$transform, identity))
          }, logical(1L))
          scales <- self$scales[!idx_skip]
          if (length(scales) == 0) {
              return(df)
          }
          transformed <- unlist(lapply(scales, function(scale) scale$transform_df(df = df)), 
              recursive = FALSE)
          df[names(transformed)] <- transformed
          df
      }

---

    Code
      print(body(environment(ggplot2::Scale$transform_df)$f))
    Output
      {
          if (empty(df)) {
              return()
          }
          aesthetics <- intersect(self$aesthetics, names(df))
          if (length(aesthetics) == 0) {
              return()
          }
          lapply(df[aesthetics], self$transform)
      }

---

    Code
      print(body(utils::getFromNamespace("default_transform", "ggplot2")))
    Output
      {
          transformation <- self$get_transformation()
          new_x <- transformation$transform(x)
          check_transformation(x, new_x, transformation$name, call = self$call)
          new_x
      }

---

    Code
      print(body(utils::getFromNamespace("has_default_transform", "ggplot2")))
    Output
      {
          transform_method <- environment(scale$transform)$f
          identical(default_transform, transform_method) || identical(identity, 
              transform_method)
      }

---

    Code
      print(body(utils::getFromNamespace("check_transformation", "ggplot2")))
    Output
      {
          if (!any(is_finite(x) != is_finite(transformed))) {
              return(invisible())
          }
          if (is.null(arg)) {
              end <- "."
          }
          else {
              end <- paste0(" in {.arg {arg}}.")
          }
          msg <- paste0("{.field {name}} transformation introduced infinite values", 
              end)
          cli::cli_warn(msg, call = call)
      }

---

    Code
      print(body(scales::transform_log))
    Output
      {
          force(base)
          new_transform(paste0("log-", format(base)), function(x) log(x, 
              base), function(x) base^x, d_transform = function(x) 1/x/log(base), 
              d_inverse = function(x) base^x * log(base), breaks = log_breaks(base = base), 
              domain = c(1e-100, Inf))
      }

---

    Code
      print(body(scales::transform_sqrt))
    Output
      {
          new_transform("sqrt", "sqrt", function(x) ifelse(x < 0, NA_real_, 
              x^2), d_transform = function(x) 0.5/sqrt(x), d_inverse = function(x) 2 * 
              x, domain = c(0, Inf))
      }

---

    Code
      print(body(scales::transform_reverse))
    Output
      {
          new_transform("reverse", function(x) -x, function(x) -x, 
              d_transform = function(x) rep(-1, length(x)), d_inverse = function(x) rep(-1, 
                  length(x)), minor_breaks = regular_minor_breaks(reverse = TRUE))
      }

# upstream non-position scale training and mapping match the versions alot mirrors

    Code
      print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$
      train_df)$f))
    Output
      {
          if (empty(df) || length(self$scales) == 0) {
              return()
          }
          lapply(self$scales, function(scale) scale$train_df(df = df))
      }

---

    Code
      print(body(environment(utils::getFromNamespace("ScalesList", "ggplot2")$map_df)$
        f))
    Output
      {
          if (empty(df) || length(self$scales) == 0) {
              return(df)
          }
          mapped <- unlist(lapply(self$scales, function(scale) scale$map_df(df = df)), 
              recursive = FALSE)
          df[names(mapped)] <- mapped
          df
      }

---

    Code
      print(body(environment(ggplot2::Scale$train_df)$f))
    Output
      {
          if (empty(df)) 
              return()
          aesthetics <- intersect(self$aesthetics, names(df))
          for (aesthetic in aesthetics) {
              self$train(df[[aesthetic]])
          }
          invisible()
      }

---

    Code
      print(body(environment(ggplot2::Scale$map_df)$f))
    Output
      {
          if (empty(df)) {
              return()
          }
          self$palette <- self$palette %||% fetch_ggproto(self, "fallback_palette")
          aesthetics <- intersect(self$aesthetics, names(df))
          names(aesthetics) <- aesthetics
          if (length(aesthetics) == 0) {
              return()
          }
          if (is.null(i)) {
              lapply(aesthetics, function(j) self$map(df[[j]]))
          }
          else {
              lapply(aesthetics, function(j) self$map(df[[j]][i]))
          }
      }

# upstream continuous colour training and mapping match the versions alot mirrors

    Code
      print(body(environment(ggplot2::ScaleContinuous$train)$f))
    Output
      {
          if (length(x) == 0) {
              return()
          }
          self$range$train(x, call = self$call)
      }

---

    Code
      print(body(environment(ggplot2::ScaleContinuous$map)$f))
    Output
      {
          x <- self$rescale(self$oob(x, range = limits), limits)
          uniq <- unique0(x)
          pal <- self$palette(uniq)
          scaled <- pal[match(x, uniq)]
          if (!anyNA(scaled)) {
              return(scaled)
          }
          vec_assign(scaled, is.na(scaled), self$na.value)
      }

---

    Code
      print(body(environment(ggplot2::ScaleContinuous$rescale)$f))
    Output
      {
          self$rescaler(x, from = range)
      }

---

    Code
      print(body(utils::getFromNamespace("mid_rescaler", "ggplot2")))
    Output
      {
          transform <- as.trans(transform)
          trans_mid <- transform$transform(mid)
          check_transformation(mid, trans_mid, transform$name, arg = arg, 
              call = call)
          function(x, to = c(0, 1), from = range(x, na.rm = TRUE)) {
              rescale_mid(x, to, from, trans_mid)
          }
      }

---

    Code
      print(body(scales::pal_gradient_n))
    Output
      {
          if (!identical(space, "Lab")) {
              lifecycle::deprecate_stop("0.3.0", "pal_gradient_n(space = 'only supports be \"Lab\"')")
          }
          ramp <- colour_ramp(colours)
          force(values)
          fun <- function(x) {
              if (length(x) == 0) {
                  return(character())
              }
              if (!is.null(values)) {
                  xs <- seq(0, 1, length.out = length(values))
                  f <- stats::approxfun(values, xs)
                  x <- f(x)
              }
              ramp(x)
          }
          new_continuous_palette(fun, "colour", na_safe = FALSE)
      }

---

    Code
      print(body(scales::colour_ramp))
    Output
      {
          if (length(colors) == 0) {
              cli::cli_abort("Must provide at least one colour to create a colour ramp")
          }
          if (length(colors) == 1) {
              return(structure(function(x) {
                  ifelse(is.na(x), na.color, colors)
              }, safe_palette_func = TRUE))
          }
          colors <- tolower(colors)
          lab_in <- farver::decode_colour(colour = colors, alpha = TRUE, 
              to = "lab", na_value = "transparent")
          x_in <- seq(0, 1, length.out = length(colors))
          l_interp <- stats::approxfun(x_in, lab_in[, 1])
          u_interp <- stats::approxfun(x_in, lab_in[, 2])
          v_interp <- stats::approxfun(x_in, lab_in[, 3])
          if (!alpha || all(lab_in[, 4] == 1)) {
              alpha_interp <- function(x) NULL
          }
          else {
              alpha_interp <- stats::approxfun(x_in, lab_in[, 4])
          }
          fun <- function(x) {
              lab_out <- cbind(l_interp(x), u_interp(x), v_interp(x))
              out <- farver::encode_colour(lab_out, alpha = alpha_interp(x), 
                  from = "lab")
              out[is.na(out)] <- na.color
              out
          }
          new_continuous_palette(fun, type = "colour", na_safe = !is.na(na.color))
      }

---

    Code
      print(body(utils::getFromNamespace("rescale.numeric", "scales")))
    Output
      {
          if (zero_range(from) || zero_range(to)) {
              return(ifelse(is.na(x), NA, mean(to)))
          }
          (x - from[1])/diff(from) * diff(to) + to[1]
      }

---

    Code
      print(body(utils::getFromNamespace("rescale_mid.numeric", "scales")))
    Output
      {
          if (zero_range(from) || zero_range(to)) {
              return(ifelse(is.na(x), NA, mean(to)))
          }
          extent <- 2 * max(abs(from - mid))
          (x - mid)/extent * diff(to) + mean(to)
      }

---

    Code
      print(body(scales::zero_range))
    Output
      {
          if (length(x) == 1) {
              return(TRUE)
          }
          if (length(x) != 2) 
              cli::cli_abort("{.arg x} must be length 1 or 2")
          if (anyNA(x)) {
              return(NA)
          }
          if (x[1] == x[2]) {
              return(TRUE)
          }
          if (any(is.infinite(x))) {
              return(FALSE)
          }
          x <- as.numeric(unclass(x))
          m <- min(abs(x))
          if (m == 0) {
              return(FALSE)
          }
          abs((x[1] - x[2])/m) < tol
      }

---

    Code
      print(body(stats::approxfun))
    Output
      {
          method <- pmatch(method, c("linear", "constant"))
          if (is.na(method)) 
              stop("invalid interpolation method")
          stopifnot(is.numeric(rule), (lenR <- length(rule)) >= 1L, 
              lenR <= 2L)
          if (lenR == 1) 
              rule <- rule[c(1, 1)]
          x <- regularize.values(x, y, ties, missing(ties), na.rm = na.rm)
          nx <- if (na.rm || !x$keptNA) 
              length(x$x)
          else sum(x$notNA)
          if (is.na(nx)) 
              stop("invalid length(x)")
          if (nx <= 1) {
              if (method == 1) 
                  stop("need at least two non-NA values to interpolate")
              if (nx == 0) 
                  stop("zero non-NA points")
          }
          y <- x$y
          if (missing(yleft)) 
              yleft <- if (rule[1L] == 1) 
                  NA
              else y[1L]
          if (missing(yright)) 
              yright <- if (rule[2L] == 1) 
                  NA
              else y[length(y)]
          stopifnot(length(yleft) == 1L, length(yright) == 1L, length(f) == 
              1L)
          rm(rule, ties, lenR, nx)
          x <- as.double(x$x)
          y <- as.double(y)
          .Call(C_ApproxTest, x, y, method, f, na.rm)
          function(v) .approxfun(x, y, v, method, yleft, yright, f, 
              na.rm)
      }

---

    Code
      print(body(farver::encode_colour))
    Output
      {
          if (from != "rgb") {
              white <- as_white_ref(white)
          }
          encode_c(colour, alpha, colourspace_match(from), white)
      }

