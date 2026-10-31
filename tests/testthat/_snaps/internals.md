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

# upstream discrete non-position training and mapping match what alot relies on

    Code
      print(body(environment(ggplot2::ScaleDiscrete$train)$f))
    Output
      {
          if (length(x) == 0) {
              return()
          }
          self$range$train(x, drop = self$drop, na.rm = !self$na.translate, 
              call = self$call)
      }

---

    Code
      print(body(environment(ggplot2::ScaleDiscrete$map)$f))
    Output
      {
          limits <- vec_slice(limits, !is.na(limits))
          n <- vec_size(limits)
          if (n < 1) {
              return(vec_rep(self$na.value, vec_size(x)))
          }
          if (!is.null(self$n.breaks.cache) && self$n.breaks.cache == 
              n) {
              pal <- self$palette.cache
          }
          else {
              if (!is.null(self$n.breaks.cache)) {
                  cli::cli_warn("Cached palette does not match requested.", 
                      call = self$call)
              }
              pal <- self$palette(n)
              self$palette.cache <- pal
              self$n.breaks.cache <- n
          }
          na_value <- NA
          if (self$na.translate) {
              na_value <- self$na.value
              if (obj_is_list(pal) && !obj_is_list(na_value)) {
                  na_value <- list(na_value)
              }
          }
          pal_names <- vec_names(pal)
          if (!is_null(pal_names)) {
              if (is_null(dim(pal))) {
                  pal[is.na(match(pal_names, limits))] <- na_value
              }
              else {
                  vec_slice(pal, is.na(match(pal_names, limits))) <- na_value
              }
              pal <- vec_set_names(pal, NULL)
              limits <- pal_names
          }
          pal <- if (is.null(dim(pal))) 
              c(pal, na_value)
          else vec_c(pal, na_value)
          pal_match <- vec_slice(pal, match(as.character(x), limits, 
              nomatch = vec_size(pal)))
          if (!is.na(na_value)) {
              vec_slice(pal_match, vec_detect_missing(x)) <- na_value
          }
          pal_match
      }

---

    Code
      print(body(scales::train_discrete))
    Output
      {
          if (is.null(new)) {
              return(existing)
          }
          if (!is.discrete(new)) {
              example <- unique(new)
              example <- example[seq_len(pmin(length(example), 5))]
              cli::cli_abort(c("Continuous value supplied to a discrete scale.", 
                  i = "Example values: {.and {.val {example}}}."), 
                  call = call)
          }
          discrete_range(existing, new, drop = drop, na.rm = na.rm, 
              fct = fct)
      }

# upstream print method matches the version alot_print mirrors

    Code
      print(body(getS3method("print", "ggplot2::ggplot")))
    Output
      {
          set_last_plot(x)
          if (newpage) 
              grid.newpage()
          grDevices::recordGraphics(requireNamespace("ggplot2", quietly = TRUE), 
              list(), getNamespace("ggplot2"))
          data <- ggplot_build(x)
          gtable <- ggplot_gtable(data)
          if (is.null(vp)) {
              grid.draw(gtable)
          }
          else {
              if (is.character(vp)) 
                  seekViewport(vp)
              else pushViewport(vp)
              grid.draw(gtable)
              upViewport()
          }
          if (isTRUE(getOption("BrailleR.VI")) && rlang::is_installed("BrailleR")) {
              print(asNamespace("BrailleR")$VI(x))
          }
          invisible(x)
      }

# upstream layout setup and facet panel assignment match the versions alot mirrors

    Code
      print(body(environment(ggplot2::Layout$setup)$f))
    Output
      {
          data <- c(list(plot_data), data)
          self$facet_params <- self$facet$setup_params(data, self$facet$params)
          self$facet_params$plot_env <- plot_env
          data <- self$facet$setup_data(data, self$facet_params)
          self$coord_params <- self$coord$setup_params(data)
          data <- self$coord$setup_data(data, self$coord_params)
          self$layout <- self$facet$compute_layout(data, self$facet_params)
          self$layout <- self$coord$setup_layout(self$layout, self$coord_params)
          check_layout(self$layout)
          lapply(data[-1], self$facet$map_data, layout = self$layout, 
              params = self$facet_params)
      }

---

    Code
      print(body(utils::getFromNamespace("map_facet_data", "ggplot2")))
    Output
      {
          if (empty(data)) {
              return(vec_cbind(data %|W|% NULL, PANEL = integer(0)))
          }
          vars <- params$facets %||% c(params$rows, params$cols)
          if (length(vars) == 0) {
              data$PANEL <- layout$PANEL
              return(data)
          }
          grid_layout <- all(c("rows", "cols") %in% names(params))
          layer_layout <- attr(data, "layout")
          if (identical(layer_layout, "fixed")) {
              n <- vec_size(data)
              data <- vec_rep(data, vec_size(layout))
              data$PANEL <- vec_rep_each(layout$PANEL, n)
              return(data)
          }
          facet_vals <- eval_facets(vars, data, params$.possible_columns)
          include_margins <- !isFALSE(params$margins %||% FALSE) && 
              nrow(facet_vals) == nrow(data) && grid_layout
          if (include_margins) {
              facet_vals <- reshape_add_margins(vec_cbind(facet_vals, 
                  .index = seq_len(nrow(facet_vals))), list(intersect(names(params$rows), 
                  names(facet_vals)), intersect(names(params$cols), 
                  names(facet_vals))), params$margins %||% FALSE)
              data <- data[facet_vals$.index, , drop = FALSE]
              facet_vals$.index <- NULL
          }
          if (grid_layout) {
              if (identical(layer_layout, "fixed_rows")) {
                  facet_vals <- facet_vals[setdiff(names(facet_vals), 
                      names(params$cols))]
              }
              if (identical(layer_layout, "fixed_cols")) {
                  facet_vals <- facet_vals[setdiff(names(facet_vals), 
                      names(params$rows))]
              }
          }
          missing_facets <- setdiff(names(vars), names(facet_vals))
          if (length(missing_facets) > 0) {
              to_add <- unique0(layout[missing_facets])
              data_rep <- rep.int(seq_len(nrow(data)), nrow(to_add))
              facet_rep <- rep(seq_len(nrow(to_add)), each = nrow(data))
              data <- unrowname(data[data_rep, , drop = FALSE])
              facet_vals <- unrowname(vec_cbind(unrowname(facet_vals[data_rep, 
                  , drop = FALSE]), unrowname(to_add[facet_rep, , drop = FALSE])))
          }
          if (nrow(facet_vals) < 1) {
              data$PANEL <- NO_PANEL
              return(data)
          }
          facet_vals[] <- lapply(facet_vals, as_unordered_factor)
          facet_vals[] <- lapply(facet_vals, addNA, ifany = TRUE)
          layout[] <- lapply(layout, as_unordered_factor)
          keys <- join_keys(facet_vals, layout, by = names(vars))
          data$PANEL <- layout$PANEL[match(keys$x, keys$y)]
          if (is_integerish(layer_layout)) {
              data <- vec_slice(data, data$PANEL %in% layer_layout)
          }
          data
      }

---

    Code
      print(body(utils::getFromNamespace("join_keys", "ggplot2")))
    Output
      {
          joint <- vec_rbind0(x[by], y[by])
          keys <- id(joint, drop = TRUE)
          n_x <- nrow(x)
          n_y <- nrow(y)
          list(x = keys[seq_len(n_x)], y = keys[n_x + seq_len(n_y)], 
              n = attr(keys, "n"))
      }

---

    Code
      print(body(utils::getFromNamespace("id", "ggplot2")))
    Output
      {
          nrows <- NULL
          if (is.data.frame(.variables)) {
              nrows <- nrow(.variables)
              .variables <- unclass(.variables)
          }
          lengths <- lengths(.variables)
          .variables <- .variables[lengths != 0]
          if (length(.variables) == 0) {
              n <- nrows %||% 0L
              id <- seq_len(n)
              attr(id, "n") <- n
              return(id)
          }
          if (length(.variables) == 1) {
              return(id_var(.variables[[1]], drop = drop))
          }
          ids <- rev(lapply(.variables, id_var, drop = drop))
          p <- length(ids)
          ndistinct <- vapply(ids, attr, "n", FUN.VALUE = numeric(1), 
              USE.NAMES = FALSE)
          n <- prod(ndistinct)
          if (n > 2^31) {
              char_id <- inject(paste(!!!ids, sep = "\r"))
              res <- match(char_id, unique0(char_id))
          }
          else {
              combs <- c(1, cumprod(ndistinct[-p]))
              mat <- inject(cbind(!!!ids))
              res <- c((mat - 1L) %*% combs + 1L)
          }
          if (drop) {
              id_var(res, drop = TRUE)
          }
          else {
              res <- as.integer(res)
              attr(res, "n") <- n
              res
          }
      }

---

    Code
      print(body(utils::getFromNamespace("id_var", "ggplot2")))
    Output
      {
          if (length(x) == 0) {
              id <- integer()
              n <- 0L
          }
          else if (!is.null(attr(x, "n")) && !drop) {
              return(x)
          }
          else if (is.factor(x) && !drop) {
              x <- addNA(x, ifany = TRUE)
              id <- as.integer(x)
              n <- nlevels(x)
          }
          else {
              levels <- sort(unique0(x), na.last = TRUE)
              id <- match(x, levels)
              n <- max(id)
          }
          attr(id, "n") <- n
          id
      }

---

    Code
      print(body(utils::getFromNamespace("as_unordered_factor", "ggplot2")))
    Output
      {
          x <- as.factor(x)
          class(x) <- setdiff(class(x), "ordered")
          x
      }

# upstream facet layout computation matches the versions alot mirrors

    Code
      print(body(environment(ggplot2::FacetWrap$compute_layout)$f))
    Output
      {
          vars <- params$facets
          if (length(vars) == 0) {
              return(layout_null())
          }
          check_facet_vars(names(vars), name = snake_class(self))
          base <- combine_vars(data, params$plot_env, vars, drop = params$drop)
          id <- id(base, drop = TRUE)
          n <- attr(id, "n")
          dims <- wrap_dims(n, params$nrow, params$ncol)
          layout <- wrap_layout(id, dims, params$dir)
          panels <- vec_cbind(layout, base)
          panels <- panels[order(panels$PANEL), , drop = FALSE]
          rownames(panels) <- NULL
          panels$SCALE_X <- if (params$free$x) 
              seq_len(n)
          else 1L
          panels$SCALE_Y <- if (params$free$y) 
              seq_len(n)
          else 1L
          panels
      }

---

    Code
      print(body(environment(ggplot2::FacetGrid$compute_layout)$f))
    Output
      {
          rows <- params$rows
          cols <- params$cols
          check_facet_vars(names(rows), names(cols), name = snake_class(self))
          dups <- intersect(names(rows), names(cols))
          if (length(dups) > 0) {
              cli::cli_abort(c("Faceting variables can only appear in {.arg rows} or {.arg cols}, not both.", 
                  i = "Duplicated variables: {.val {dups}}"), call = call2(snake_class(self)))
          }
          base_rows <- combine_vars(data, params$plot_env, rows, drop = params$drop)
          if (!params$as.table) {
              rev_order <- function(x) factor(x, levels = rev(ulevels(x)))
              base_rows[] <- lapply(base_rows, rev_order)
          }
          base_cols <- combine_vars(data, params$plot_env, cols, drop = params$drop)
          base <- df.grid(base_rows, base_cols)
          if (nrow(base) == 0) {
              return(data_frame0(PANEL = factor(1L), ROW = 1L, COL = 1L, 
                  SCALE_X = 1L, SCALE_Y = 1L))
          }
          base <- reshape_add_margins(base, list(names(rows), names(cols)), 
              params$margins)
          base <- unique0(base)
          panel <- id(base, drop = TRUE)
          panel <- factor(panel, levels = seq_len(attr(panel, "n")))
          rows <- if (!length(names(rows))) 
              rep(1L, length(panel))
          else id(base[names(rows)], drop = TRUE)
          cols <- if (!length(names(cols))) 
              rep(1L, length(panel))
          else id(base[names(cols)], drop = TRUE)
          panels <- data_frame0(PANEL = panel, ROW = rows, COL = cols, 
              base)
          panels <- panels[order(panels$PANEL), , drop = FALSE]
          rownames(panels) <- NULL
          panels$SCALE_X <- if (params$free$x) 
              panels$COL
          else 1L
          panels$SCALE_Y <- if (params$free$y) 
              panels$ROW
          else 1L
          panels
      }

---

    Code
      print(body(utils::getFromNamespace("combine_vars", "ggplot2")))
    Output
      {
          possible_columns <- unique0(unlist(lapply(data, names)))
          if (length(vars) == 0) 
              return(data_frame0())
          values <- compact(lapply(data, eval_facets, facets = vars, 
              possible_columns = possible_columns))
          has_all <- unlist(lapply(values, length)) == length(vars)
          if (!any(has_all)) {
              missing <- lapply(values, function(x) setdiff(names(vars), 
                  names(x)))
              missing_vars <- paste0(c("Plot", paste0("Layer ", seq_len(length(data) - 
                  1))), " is missing {.var ", missing[seq_along(data)], 
                  "}")
              names(missing_vars) <- rep("x", length(data))
              cli::cli_abort(c("At least one layer must contain all faceting variables: {.var {names(vars)}}", 
                  missing_vars))
          }
          base <- unique0(vec_rbind0(!!!values[has_all]))
          if (!drop) {
              base <- unique_combs(base)
          }
          for (value in values[!has_all]) {
              if (empty(value)) 
                  next
              old <- base[setdiff(names(base), names(value))]
              new <- unique0(value[intersect(names(base), names(value))])
              if (drop) {
                  new <- unique_combs(new)
              }
              base <- unique0(vec_rbind0(base, df.grid(old, new)))
          }
          if (empty(base)) {
              cli::cli_abort("Faceting variables must have at least one value.")
          }
          base
      }

# upstream labeling::extended matches the version alot ports

    Code
      print(body(labeling::extended))
    Output
      {
          eps <- .Machine$double.eps * 100
          if (dmin > dmax) {
              temp <- dmin
              dmin <- dmax
              dmax <- temp
          }
          if (dmax - dmin < eps) {
              return(seq(from = dmin, to = dmax, length.out = m))
          }
          if ((dmax - dmin) > sqrt(.Machine$double.xmax)) {
              return(seq(from = dmin, to = dmax, length.out = m))
          }
          n <- length(Q)
          best <- list()
          best$score <- -2
          j <- 1
          while (j < Inf) {
              for (q in Q) {
                  sm <- .simplicity.max(q, Q, j)
                  if ((w[1] * sm + w[2] + w[3] + w[4]) < best$score) {
                      j <- Inf
                      break
                  }
                  k <- 2
                  while (k < Inf) {
                      dm <- .density.max(k, m)
                      if ((w[1] * sm + w[2] + w[3] * dm + w[4]) < best$score) 
                        break
                      delta <- (dmax - dmin)/(k + 1)/j/q
                      z <- ceiling(log(delta, base = 10))
                      while (z < Inf) {
                        step <- j * q * 10^z
                        cm <- .coverage.max(dmin, dmax, step * (k - 
                          1))
                        if ((w[1] * sm + w[2] * cm + w[3] * dm + w[4]) < 
                          best$score) 
                          break
                        min_start <- floor(dmax/(step)) * j - (k - 
                          1) * j
                        max_start <- ceiling(dmin/(step)) * j
                        if (min_start > max_start) {
                          z <- z + 1
                          next
                        }
                        for (start in min_start:max_start) {
                          lmin <- start * (step/j)
                          lmax <- lmin + step * (k - 1)
                          lstep <- step
                          s <- .simplicity(q, Q, j, lmin, lmax, lstep)
                          c <- .coverage(dmin, dmax, lmin, lmax)
                          g <- .density(k, m, dmin, dmax, lmin, lmax)
                          l <- .legibility(lmin, lmax, lstep)
                          score <- w[1] * s + w[2] * c + w[3] * g + 
                            w[4] * l
                          if (score > best$score && (!only.loose || 
                            (lmin <= dmin && lmax >= dmax))) {
                            best <- list(lmin = lmin, lmax = lmax, 
                              lstep = lstep, score = score)
                          }
                        }
                        z <- z + 1
                      }
                      k <- k + 1
                  }
              }
              j <- j + 1
          }
          seq(from = best$lmin, to = best$lmax, by = best$lstep)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          eps <- .Machine$double.eps * 100
          n <- length(Q)
          i <- match(q, Q)[1]
          v <- ifelse((lmin%%lstep < eps || lstep - (lmin%%lstep) < 
              eps) && lmin <= 0 && lmax >= 0, 1, 0)
          1 - (i - 1)/(n - 1) - j + v
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          n <- length(Q)
          i <- match(q, Q)[1]
          v <- 1
          1 - (i - 1)/(n - 1) - j + v
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          range <- dmax - dmin
          1 - 0.5 * ((dmax - lmax)^2 + (dmin - lmin)^2)/((0.1 * range)^2)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          range <- dmax - dmin
          if (span > range) {
              half <- (span - range)/2
              1 - 0.5 * (half^2 + half^2)/((0.1 * range)^2)
          }
          else {
              1
          }
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          r <- (k - 1)/(lmax - lmin)
          rt <- (m - 1)/(max(lmax, dmax) - min(dmin, lmin))
          2 - max(r/rt, rt/r)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          if (k >= m) 
              2 - (k - 1)/(m - 1)
          else 1
      }

---

    Code
      print(body(utils::getFromNamespace(f, "labeling")))
    Output
      {
          1
      }

---

    Code
      print(body(scales::extended_breaks))
    Output
      {
          n_default <- n
          function(x, n = n_default) {
              x <- x[is.finite(x)]
              if (length(x) == 0) {
                  return(numeric())
              }
              rng <- range(x)
              labeling::extended(rng[1], rng[2], n, ...)
          }
      }

# upstream panel guides setup matches the version alot mirrors

    Code
      print(body_of(ggplot2::Layout, "setup_panel_guides"))
    Output
      {
          index <- vec_unique_loc(self$layout$COORD)
          order <- vec_match(self$layout$COORD, self$layout$COORD[index])
          self$panel_params <- lapply(self$panel_params[index], self$coord$setup_panel_guides, 
              guides, self$coord_params)
          self$panel_params <- lapply(self$panel_params, self$coord$train_panel_guides, 
              layers, self$coord_params)[order]
          invisible()
      }

---

    Code
      print(body_of(ggplot2::Coord, "setup_panel_guides"))
    Output
      {
          aesthetics <- c("x", "y", "x.sec", "y.sec")
          names(aesthetics) <- aesthetics
          is_sec <- grepl("sec$", aesthetics)
          scales <- panel_params[aesthetics]
          guides <- guides$setup(scales, aesthetics, default = params$guide_default %||% 
              guide_axis(), missing = params$guide_missing %||% guide_none())
          guide_params <- guides$get_params(aesthetics)
          scale_position <- lapply(scales, `[[`, "position")
          guide_position <- lapply(guide_params, `[[`, "position")
          guide_position[!is_sec] <- Map(function(guide, scale) guide %|W|% 
              scale, guide = guide_position[!is_sec], scale = scale_position[!is_sec])
          opposite <- c(top = "bottom", bottom = "top", left = "right", 
              right = "left")
          guide_position[is_sec] <- Map(function(sec, prim) sec %|W|% 
              unname(opposite[prim]), sec = guide_position[is_sec], 
              prim = guide_position[!is_sec])
          guide_params <- Map(function(params, pos) {
              params[["position"]] <- pos
              params
          }, params = guide_params, pos = guide_position)
          guides$update_params(guide_params)
          panel_params$guides <- guides
          panel_params
      }

---

    Code
      print(body_of(ggplot2::Coord, "train_panel_guides"))
    Output
      {
          aesthetics <- c("x", "y", "x.sec", "y.sec")
          aesthetics <- intersect(aesthetics, names(panel_params$guides$aesthetics))
          names(aesthetics) <- aesthetics
          guides <- panel_params$guides$get_guide(aesthetics)
          empty <- vapply(guides, inherits, logical(1), "GuideNone")
          guide_params <- panel_params$guides$get_params(aesthetics)
          aesthetics <- aesthetics[!empty]
          guide_params[!empty] <- Map(function(guide, guide_param, 
              scale) {
              guide_param <- guide$train(guide_param, scale)
              guide_param <- guide$transform(guide_param, self, panel_params)
              guide_param <- guide$get_layer_key(guide_param, layers)
              guide_param
          }, guide = guides[!empty], guide_param = guide_params[!empty], 
              scale = panel_params[aesthetics])
          panel_params$guides$update_params(guide_params)
          panel_params
      }

---

    Code
      print(body_of(ggplot2::CoordCartesian, "transform"))
    Output
      {
          reverse <- panel_params$reverse %||% "none"
          x <- panel_params$x[[switch(reverse, xy = , x = "reverse", 
              "rescale")]]
          y <- panel_params$y[[switch(reverse, xy = , y = "reverse", 
              "rescale")]]
          data <- transform_position(data, x, y)
          transform_position(data, squish_infinite, squish_infinite)
      }

---

    Code
      print(body_of(ggplot2::Guide, "train"))
    Output
      {
          params$aesthetic <- aesthetic %||% scale$aesthetics[1]
          params$key <- inject(self$extract_key(scale, !!!params))
          if (is.null(params$key)) {
              return(NULL)
          }
          params$decor <- inject(self$extract_decor(scale, !!!params))
          params <- self$extract_params(scale, params, ...)
          params$hash <- hash(lapply(unname(self$hashables), eval_tidy, 
              data = params))
          params
      }

---

    Code
      print(body_of(ggplot2::Guide, "extract_key"))
    Output
      {
          breaks <- scale$get_breaks()
          if (length(breaks) == 0) {
              return(NULL)
          }
          mapped <- scale$map(breaks)
          labels <- scale$get_labels(breaks)
          key <- data_frame(`:=`(!!aesthetic, mapped))
          key$.value <- breaks
          key$.label <- labels
          if (is.numeric(breaks)) {
              range <- scale$continuous_range %||% scale$get_limits()
              key <- key[is.finite(oob_censor_any(breaks, range)), 
                  , drop = FALSE]
          }
          else {
              key
          }
      }

---

    Code
      print(body_of(ggplot2::GuideAxis, "extract_key"))
    Output
      {
          major <- Guide$extract_key(scale, aesthetic, ...)
          if (is.null(major) && is.null(scale$scale$get_breaks())) {
              major <- data_frame0()
          }
          if (!minor.ticks) {
              return(major)
          }
          minor_breaks <- scale$get_breaks_minor()
          minor_breaks <- setdiff(minor_breaks, major$.value)
          minor_breaks <- minor_breaks[is.finite(minor_breaks)]
          if (length(minor_breaks) < 1) {
              return(major)
          }
          minor <- data_frame0(`:=`(!!aesthetic, scale$map(minor_breaks)))
          minor$.value <- minor_breaks
          minor$.type <- "minor"
          if (nrow(major) > 0) {
              major$.type <- "major"
              if (!vec_is(minor$.value, major$.value)) {
                  minor$.value <- NULL
              }
              vec_rbind(major, minor)
          }
          else {
              minor
          }
      }

---

    Code
      print(body_of(ggplot2::GuideAxis, "extract_decor"))
    Output
      {
          value <- c(-Inf, Inf)
          has_key <- !(is.null(key) || nrow(key) < 1)
          if (cap %in% c("both", "upper") && has_key) {
              value[2] <- max(key[[aesthetic]])
          }
          if (cap %in% c("both", "lower") && has_key) {
              value[1] <- min(key[[aesthetic]])
          }
          opposite <- setdiff(c("x", "y"), aesthetic)
          data_frame(`:=`(!!aesthetic, value))
      }

---

    Code
      print(body_of(ggplot2::GuideAxis, "extract_params"))
    Output
      {
          params$name <- paste0(params$name, "_", params$aesthetic)
          params
      }

---

    Code
      print(body_of(ggplot2::GuideAxis, "transform"))
    Output
      {
          key <- params$key
          position <- params$position
          check <- FALSE
          aesthetic <- names(key)[!grepl("^\\.", names(key))]
          ortho <- setdiff(c("x", "y"), params$aesthetic)
          override <- switch(position %||% "", bottom = , left = -Inf, 
              Inf)
          if (!(panel_params$reverse %||% "none") %in% c("xy", ortho)) {
              override <- -override
          }
          if (!(is.null(position) || nrow(key) == 0)) {
              check <- TRUE
              if (!all(c("x", "y") %in% aesthetic)) {
                  key[[ortho]] <- override
              }
              key <- coord$transform(key, panel_params)
              params$key <- key
          }
          if (!is.null(params$decor)) {
              if (!ortho %in% names(params$decor)) {
                  params$decor[[ortho]] <- override
              }
              params$decor <- coord_munch(coord, params$decor, panel_params)
              if (!coord$is_linear()) {
                  params$decor$x <- switch(position, left = 1, right = 0, 
                      params$decor$x)
                  params$decor$y <- switch(position, top = 0, bottom = 1, 
                      params$decor$y)
              }
          }
          if (!check) {
              return(params)
          }
          breaks_are_unique <- !duplicated(key$.value)
          if (empty(key) || sum(breaks_are_unique) == 1) {
              return(params)
          }
          if (position %in% c("top", "bottom")) {
              position_aes <- "x"
          }
          else if (position %in% c("left", "right")) {
              position_aes <- "y"
          }
          else {
              return(params)
          }
          if (length(unique(key[[position_aes]][breaks_are_unique])) == 
              1) {
              cli::cli_warn(c("Position guide is perpendicular to the intended axis.", 
                  i = "Did you mean to specify a different guide {.arg position}?"))
          }
          return(params)
      }

---

    Code
      print(body_of(ggplot2::Facet, "setup_panel_params"))
    Output
      {
          panel_params
      }

---

    Code
      print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m))
    Output
      {
          self$breaks
      }

---

    Code
      print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m))
    Output
      {
          self$scale$get_labels(breaks)
      }

---

    Code
      print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m))
    Output
      {
          if (self$is_discrete()) {
              self$scale$map(x, self$limits)
          }
          else {
              x
          }
      }

---

    Code
      print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m))
    Output
      {
          self$scale_is_discrete
      }

---

    Code
      print(body_of(utils::getFromNamespace("ViewScale", "ggplot2"), m))
    Output
      {
          self$scale$rescale(x, self$limits, self$continuous_range)
      }

# upstream panel params setup matches the version alot mirrors

    Code
      print(body(environment(ggplot2::Layout$setup_panel_params)$f))
    Output
      {
          self$coord$modify_scales(self$panel_scales_x, self$panel_scales_y)
          index <- vec_unique_loc(self$layout$COORD)
          order <- vec_match(self$layout$COORD, self$layout$COORD[index])
          scales_x <- self$panel_scales_x[self$layout$SCALE_X[index]]
          scales_y <- self$panel_scales_y[self$layout$SCALE_Y[index]]
          panel_params <- Map(self$coord$setup_panel_params, scales_x, 
              scales_y, MoreArgs = list(params = self$coord_params))[order]
          self$panel_params <- self$facet$setup_panel_params(panel_params, 
              self$coord)
          invisible()
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian$setup_panel_params)$f))
    Output
      {
          c(view_scales_from_scale(scale_x, self$limits$x, params$expand[c(4, 
              2)]), view_scales_from_scale(scale_y, self$limits$y, 
              params$expand[c(3, 1)]), reverse = self$reverse %||% 
              "none")
      }

---

    Code
      print(body(environment(ggplot2::CoordFlip$setup_panel_params)$f))
    Output
      {
          params$expand <- params$expand[c(2, 1, 4, 3)]
          parent <- ggproto_parent(CoordCartesian, self)
          panel_params <- parent$setup_panel_params(scale_x, scale_y, 
              params)
          flip_axis_labels(panel_params)
      }

---

    Code
      print(body(environment(ggplot2::ScaleContinuous$get_breaks)$f))
    Output
      {
          if (self$is_empty()) {
              return(numeric())
          }
          transformation <- self$get_transformation()
          breaks <- self$breaks %|W|% transformation$breaks
          if (is.null(breaks)) {
              return(NULL)
          }
          domain <- suppressWarnings(transformation$transform(transformation$domain))
          domain <- sort(domain)
          if (length(domain) == 2 && !zero_range(domain)) {
              limits <- oob_squish(limits, domain)
          }
          if (zero_range(as.numeric(limits))) {
              return(limits[1])
          }
          if (is.function(breaks)) {
              limits <- transformation$inverse(limits)
              if (!is.null(self$n.breaks) && support_nbreaks(breaks)) {
                  breaks <- breaks(limits, n = self$n.breaks)
              }
              else {
                  breaks <- breaks(limits)
                  if (!is.null(self$n.breaks)) {
                      cli::cli_warn("Ignoring {.arg n.breaks}. Use a {.cls transform} object or \\\n            {.arg breaks} function that supports setting number of breaks", 
                        call = self$call)
                  }
              }
          }
          transformation$transform(breaks)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          expansion <- default_expansion(scale, expand = expand)
          limits <- scale$get_limits()
          continuous_range <- expand_limits_scale(scale, expansion, 
              limits, coord_limits = coord_limits)
          aesthetic <- scale$aesthetics[1]
          view_scales <- list(view_scale_primary(scale, limits, continuous_range), 
              sec = view_scale_secondary(scale, limits, continuous_range), 
              range = continuous_range)
          names(view_scales) <- c(aesthetic, paste0(aesthetic, ".", 
              names(view_scales)[-1]))
          view_scales
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          continuous_scale_sorted <- sort(continuous_range)
          if (!scale$is_discrete()) {
              breaks <- scale$get_breaks(continuous_scale_sorted)
              breaks <- censor(breaks, continuous_scale_sorted, only.finite = FALSE)
          }
          else {
              breaks <- scale$get_breaks(limits)
          }
          minor_breaks <- scale$get_breaks_minor(b = breaks, limits = continuous_scale_sorted)
          minor_breaks <- censor(minor_breaks, continuous_range, only.finite = FALSE)
          ggproto(NULL, ViewScale, scale = scale, guide = scale$guide, 
              position = scale$position, aesthetics = scale$aesthetics, 
              name = scale$name, scale_is_discrete = scale$is_discrete(), 
              limits = limits, continuous_range = continuous_range, 
              breaks = breaks, minor_breaks = minor_breaks)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          if (is.null(scale$secondary.axis) || is_waiver(scale$secondary.axis) || 
              scale$secondary.axis$empty()) {
              primary_scale <- view_scale_primary(scale, limits, continuous_range)
              scale_flip_position(primary_scale)
              primary_scale$guide <- guide_none()
              primary_scale
          }
          else {
              scale$secondary.axis$init(scale)
              break_info <- scale$secondary.axis$break_info(continuous_range, 
                  scale)
              names(break_info) <- gsub("sec\\.", "", names(break_info))
              position <- switch(scale$position, top = "bottom", bottom = "top", 
                  left = "right", right = "left", scale$position)
              ggproto(NULL, ViewScale, scale = scale, guide = scale$secondary.axis$guide, 
                  position = position, break_info = break_info, aesthetics = scale$aesthetics, 
                  name = scale$sec_name(), make_title = function(self, 
                      ...) self$scale$make_sec_title(...), continuous_range = sort(continuous_range), 
                  dimension = function(self) self$break_info$range, 
                  get_limits = function(self) self$break_info$range, 
                  get_breaks = function(self) self$break_info$major_source, 
                  get_breaks_minor = function(self) self$break_info$minor_source, 
                  break_positions = function(self) self$break_info$major, 
                  break_positions_minor = function(self) self$break_info$minor, 
                  get_labels = function(self, breaks = self$get_breaks()) self$break_info$labels, 
                  rescale = function(x) rescale(x, from = break_info$range, 
                      to = c(0, 1)))
          }
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          old_names <- names(x)
          new_names <- old_names
          new_names <- gsub("^x", "z", new_names)
          new_names <- gsub("^y", "x", new_names)
          new_names <- gsub("^z", "y", new_names)
          setNames(x, new_names)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          scale$position <- opposite_position(scale$position)
          invisible()
      }

---

    Code
      print(body(ggplot2::ggproto))
    Output
      {
          e <- new.env(parent = emptyenv())
          members <- list2(...)
          if (length(members) != sum(nzchar(names(members)))) {
              cli::cli_abort("All members of a {.cls ggproto} object must be named.")
          }
          if (length(members) > 0) {
              list2env(members, envir = e)
          }
          `_inherit` <- substitute(`_inherit`)
          env <- parent.frame()
          find_super <- function() {
              eval(`_inherit`, env, NULL)
          }
          super <- find_super()
          if (!is.null(super)) {
              check_object(super, is_ggproto, "a {.cls ggproto} object", 
                  arg = "_inherit")
              e$super <- find_super
              class(e) <- c(`_class`, class(super))
          }
          else {
              class(e) <- c(`_class`, "ggproto", "gg")
          }
          e
      }

# upstream point drawing matches what the hybrid tier mirrors

    Code
      print(body(environment(ggplot2::GeomPoint$draw_panel)$f))
    Output
      {
          data$shape <- translate_shape_string(data$shape)
          coords <- coord$transform(data, panel_params)
          ggname("geom_point", pointsGrob(coords$x, coords$y, pch = coords$shape, 
              gp = gg_par(col = alpha(coords$colour, coords$alpha), 
                  fill = fill_alpha(coords$fill, coords$alpha), pointsize = coords$size, 
                  stroke = coords$stroke)))
      }

---

    Code
      print(body(environment(utils::getFromNamespace("Layer", "ggplot2")$draw_geom)$f))
    Output
      {
          if (empty(data)) {
              n <- nrow(layout$layout)
              return(rep(list(zeroGrob()), n))
          }
          data <- self$geom$handle_na(data, self$computed_geom_params)
          self$geom$draw_layer(data, self$computed_geom_params, layout, 
              layout$coord)
      }

---

    Code
      print(body(environment(ggplot2::Geom$handle_na)$f))
    Output
      {
          remove_missing(data, params$na.rm, c(self$required_aes, self$non_missing_aes), 
              snake_class(self))
      }

---

    Code
      print(body(environment(ggplot2::Geom$draw_layer)$f))
    Output
      {
          if (empty(data)) {
              n <- if (is.factor(data$PANEL)) 
                  nlevels(data$PANEL)
              else 1L
              return(rep(list(zeroGrob()), n))
          }
          params <- params[intersect(names(params), self$parameters())]
          if (nlevels(as.factor(data$PANEL)) > 1L) {
              data_panels <- split(data, data$PANEL)
          }
          else {
              data_panels <- list(data)
          }
          lapply(data_panels, function(data) {
              if (empty(data)) 
                  return(zeroGrob())
              panel_params <- layout$panel_params[[data$PANEL[1]]]
              inject(self$draw_panel(data, panel_params, coord, !!!params))
          })
      }

---

    Code
      print(body(utils::getFromNamespace("gg_par", "ggplot2")))
    Output
      {
          args <- list2(...)
          args <- args[lengths(args) > 0]
          if (!is.null(args$lwd)) {
              args$lwd <- args$lwd * .pt
          }
          if (!is.null(stroke)) {
              args$lwd <- stroke * .stroke/2
          }
          if (!is.null(pointsize)) {
              stroke <- stroke %||% 0
              stroke[is.na(stroke)] <- 0
              args$fontsize <- pointsize * .pt + stroke * .stroke/2
          }
          if (!is.null(args$lty)) {
              if (is.logical(args$lty)) {
                  args$lty <- as.integer(args$lty)
              }
              if (anyNA(args$lty)) {
                  args$lty[is.na(args$lty)] <- if (is.character(args$lty)) 
                      "blank"
                  else 0
              }
          }
          inject(gpar(!!!args))
      }

---

    Code
      print(body(utils::getFromNamespace("translate_shape_string", "ggplot2")))
    Output
      {
          if (!is.character(shape_string)) {
              return(shape_string)
          }
          if (nchar(shape_string[1]) <= 1) {
              return(shape_string)
          }
          pch_table <- c(`square open` = 0, `circle open` = 1, `triangle open` = 2, 
              plus = 3, cross = 4, `diamond open` = 5, `triangle down open` = 6, 
              `square cross` = 7, asterisk = 8, `diamond plus` = 9, 
              `circle plus` = 10, star = 11, `square plus` = 12, `circle cross` = 13, 
              `square triangle` = 14, `triangle square` = 14, square = 15, 
              `circle small` = 16, triangle = 17, diamond = 18, circle = 19, 
              bullet = 20, `circle filled` = 21, `square filled` = 22, 
              `diamond filled` = 23, `triangle filled` = 24, `triangle down filled` = 25)
          shape_match <- charmatch(shape_string, names(pch_table))
          invalid_strings <- is.na(shape_match)
          nonunique_strings <- shape_match == 0
          if (any(invalid_strings)) {
              bad_string <- unique0(shape_string[invalid_strings])
              cli::cli_abort("Shape aesthetic contains invalid value{?s}: {.val {bad_string}}.")
          }
          if (any(nonunique_strings)) {
              bad_string <- unique0(shape_string[nonunique_strings])
              cli::cli_abort(c("Shape names must be given unambiguously.", 
                  i = "Fix {.val {bad_string}}."))
          }
          unname(pch_table[shape_match])
      }

---

    Code
      print(body(utils::getFromNamespace("remove_missing", "ggplot2")))
    Output
      {
          check_bool(na.rm)
          missing <- detect_missing(df, vars, finite)
          if (any(missing)) {
              df <- df[!missing, , drop = FALSE]
              if (!na.rm) {
                  if (name != "") 
                      name <- paste(" ({.fn ", name, "})", sep = "")
                  msg <- paste0("Removed {sum(missing)} row{?s} containing ", 
                      if (finite) 
                        "non-finite"
                      else "missing values or values", " outside the scale range", 
                      name, ".")
                  cli::cli_warn(msg)
              }
          }
          df
      }

# upstream rect drawing matches what the hybrid tier mirrors

    Code
      print(body(environment(ggplot2::GeomRect$draw_panel)$f))
    Output
      {
          data <- fix_linewidth(data, snake_class(self))
          if (!coord$is_linear()) {
              aesthetics <- setdiff(names(data), c("x", "y", "xmin", 
                  "xmax", "ymin", "ymax"))
              index <- rep(seq_len(nrow(data)), each = 4)
              new <- data[index, aesthetics, drop = FALSE]
              new$x <- vec_interleave(data$xmin, data$xmax, data$xmax, 
                  data$xmin)
              new$y <- vec_interleave(data$ymax, data$ymax, data$ymin, 
                  data$ymin)
              new$group <- index
              ggname("geom_rect", GeomPolygon$draw_panel(new, panel_params, 
                  coord, lineend = lineend, linejoin = linejoin))
          }
          else {
              coords <- coord$transform(data, panel_params)
              ggname("geom_rect", rectGrob(coords$xmin, coords$ymax, 
                  width = coords$xmax - coords$xmin, height = coords$ymax - 
                      coords$ymin, default.units = "native", just = c("left", 
                      "top"), gp = gg_par(col = coords$colour, fill = fill_alpha(coords$fill, 
                      coords$alpha), lwd = coords$linewidth, lty = coords$linetype, 
                      linejoin = linejoin, lineend = lineend)))
          }
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
      print(body(environment(ggplot2::ScaleDiscretePosition$rescale)$f))
    Output
      {
          rescale(self$map(x, limits = limits), from = range)
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

# upstream path drawing matches what the hybrid tier mirrors

    Code
      print(body(environment(ggplot2::GeomPath$draw_panel)$f))
    Output
      {
          data <- fix_linewidth(data, snake_class(self))
          if (!anyDuplicated(data$group)) {
              cli::cli_inform(c("{.fn {snake_class(self)}}: Each group consists of only one observation.", 
                  i = "Do you need to adjust the {.field group} aesthetic?"))
          }
          data <- data[order(data$group), , drop = FALSE]
          munched <- coord_munch(coord, data, panel_params)
          rows <- vec_ave(seq_len(nrow(munched)), munched$group, length)
          munched <- munched[rows >= 2, ]
          if (nrow(munched) < 2) 
              return(zeroGrob())
          attr <- dapply(munched, "group", function(df) {
              linetype <- unique0(df$linetype)
              data_frame0(solid = length(linetype) == 1 && (identical(linetype, 
                  "solid") || linetype == 1), constant = nrow(unique0(df[, 
                  names(df) %in% c("alpha", "colour", "linewidth", 
                      "linetype")])) == 1, .size = 1)
          })
          solid_lines <- all(attr$solid)
          constant <- all(attr$constant)
          if (!solid_lines && !constant) {
              cli::cli_abort("{.fn {snake_class(self)}} can't have varying {.field colour}, {.field linewidth}, and/or {.field alpha} along the line when {.field linetype} isn't solid.")
          }
          n <- nrow(munched)
          group_diff <- munched$group[-1] != munched$group[-n]
          start <- c(TRUE, group_diff)
          end <- c(group_diff, TRUE)
          munched$fill <- arrow.fill %||% munched$colour
          if (!constant) {
              arrow <- repair_segment_arrow(arrow, munched$group)
              segmentsGrob(munched$x[!end], munched$y[!end], munched$x[!start], 
                  munched$y[!start], default.units = "native", arrow = arrow, 
                  gp = gg_par(col = alpha(munched$colour, munched$alpha)[!end], 
                      fill = alpha(munched$fill, munched$alpha)[!end], 
                      lwd = munched$linewidth[!end], lty = munched$linetype[!end], 
                      lineend = lineend, linejoin = linejoin, linemitre = linemitre))
          }
          else {
              id <- match(munched$group, unique0(munched$group))
              polylineGrob(munched$x, munched$y, id = id, default.units = "native", 
                  arrow = arrow, gp = gg_par(col = alpha(munched$colour, 
                      munched$alpha)[start], fill = alpha(munched$fill, 
                      munched$alpha)[start], lwd = munched$linewidth[start], 
                      lty = munched$linetype[start], lineend = lineend, 
                      linejoin = linejoin, linemitre = linemitre))
          }
      }

---

    Code
      print(body(environment(ggplot2::GeomPath$handle_na)$f))
    Output
      {
          aesthetics <- c(self$required_aes, self$non_missing_aes)
          complete <- stats::complete.cases(data[names(data) %in% aesthetics])
          kept <- vec_ave(complete, interaction(data$group, data$PANEL, 
              drop = TRUE), keep_mid_true)
          data <- data[kept, ]
          if (!all(kept) && !params$na.rm) {
              cli::cli_warn(paste0("Removed {sum(!kept)} row{?s} containing missing values or values ", 
                  "outside the scale range ({.fn {snake_class(self)}})."))
          }
          data
      }

---

    Code
      print(body(environment(ggplot2::GeomPolygon$draw_panel)$f))
    Output
      {
          data <- fix_linewidth(data, snake_class(self))
          n <- nrow(data)
          if (n == 1) 
              return(zeroGrob())
          munched <- coord_munch(coord, data, panel_params, is_closed = TRUE)
          if (is.null(munched$subgroup)) {
              munched <- munched[order(munched$group), ]
              first_idx <- !duplicated(munched$group)
              first_rows <- munched[first_idx, ]
              ggname("geom_polygon", polygonGrob(munched$x, munched$y, 
                  default.units = "native", id = munched$group, gp = gg_par(col = first_rows$colour, 
                      fill = fill_alpha(first_rows$fill, first_rows$alpha), 
                      lwd = first_rows$linewidth, lty = first_rows$linetype, 
                      lineend = lineend, linejoin = linejoin, linemitre = linemitre)))
          }
          else {
              munched <- munched[order(munched$group, munched$subgroup), 
                  ]
              id <- match(munched$subgroup, unique0(munched$subgroup))
              first_idx <- !duplicated(munched$group)
              first_rows <- munched[first_idx, ]
              ggname("geom_polygon", pathGrob(munched$x, munched$y, 
                  default.units = "native", id = id, pathId = munched$group, 
                  rule = rule, gp = gg_par(col = first_rows$colour, 
                      fill = fill_alpha(first_rows$fill, first_rows$alpha), 
                      lwd = first_rows$linewidth, lty = first_rows$linetype, 
                      lineend = lineend, linejoin = linejoin, linemitre = linemitre)))
          }
      }

# upstream theme and label resolution match what the render IR mirrors

    Code
      print(body(ggplot2::calc_element))
    Output
      {
          if (verbose) 
              cli::cli_inform(paste0(element, " --> "))
          el_out <- theme[[element]]
          if (is_theme_element(el_out, "blank")) {
              if (isTRUE(skip_blank)) {
                  el_out <- NULL
              }
              else {
                  if (verbose) 
                      cli::cli_inform("{.fn element_blank} (no inheritance)")
                  return(el_out)
              }
          }
          element_tree <- get_element_tree()
          if (!is.null(el_out)) {
              class <- element_tree[[element]]$class
              if (inherits(class, "S7_class")) {
                  old_s3_inherit <- inherits(el_out, class@name)
                  if (!S7::S7_inherits(el_out, class) && !old_s3_inherit) {
                      cli::cli_abort("Theme element {.var {element}} must have class {.cls {class@name}}.", 
                        call = call)
                  }
              }
              else {
                  if (!inherits(el_out, class)) {
                      cli::cli_abort("Theme element {.var {element}} must have class {.cls {ggplot_global$element_tree[[element]]$class}}.", 
                        call = call)
                  }
              }
          }
          pnames <- element_tree[[element]]$inherit
          if (is.null(pnames)) {
              if (verbose) 
                  cli::cli_inform("nothing (top level)")
              if (is_theme_element(el_out)) {
                  nullprops <- lengths(S7::props(el_out)) == 0
              }
              else {
                  nullprops <- vapply(el_out, is.null, logical(1))
              }
              if (!any(nullprops)) {
                  return(el_out)
              }
              el_out <- combine_elements(el_out, ggplot_global$theme_default[[element]])
              if (is_theme_element(el_out)) {
                  nullprops <- lengths(S7::props(el_out)) == 0
              }
              else {
                  nullprops <- vapply(el_out, is.null, logical(1))
              }
              if (is_theme_element(el_out, "geom")) {
                  nullprops[c("colour", "fill")] <- FALSE
              }
              if (!any(nullprops)) {
                  return(el_out)
              }
              cli::cli_abort("Theme element {.var {element}} has {.code NULL} property without default: {.field {names(nullprops)[nullprops]}}.", 
                  call = call)
          }
          if (verbose) 
              cli::cli_inform("{pnames}")
          skip_blank <- skip_blank || (!is.null(el_out) && !isTRUE(try_prop(el_out, 
              "inherit.blank")))
          parents <- lapply(pnames, calc_element, theme, verbose = verbose, 
              skip_blank = skip_blank, call = call)
          Reduce(combine_elements, parents, el_out)
      }

---

    Code
      print(body(utils::getFromNamespace("combine_elements", "ggplot2")))
    Output
      {
          if (is.null(e2) || is_theme_element(e1, "blank")) {
              return(e1)
          }
          if (is.null(e1)) {
              return(e2)
          }
          if (is_rel(e1)) {
              if (is_rel(e2)) {
                  return(rel(unclass(e1) * unclass(e2)))
              }
              if (is.numeric(e2) || is.unit(e2)) {
                  return(unclass(e1) * e2)
              }
              return(e1)
          }
          if (is_margin(e1) && is_margin(e2)) {
              if (anyNA(e2)) {
                  e2[is.na(e2)] <- unit(0, "pt")
              }
              if (anyNA(e1)) {
                  e1[is.na(e1)] <- e2[is.na(e1)]
              }
          }
          is_old_element <- !S7::S7_inherits(e1) && inherits(e1, "element")
          if (is_old_element && (is_theme_element(e2) || inherits(e2, 
              "element"))) {
              return(combine_s3_elements(e1, e2))
          }
          if (!is_theme_element(e1) && !is_theme_element(e2)) {
              return(e1)
          }
          if (is_theme_element(e2, "blank")) {
              if (isTRUE(try_prop(e1, "inherit.blank"))) {
                  return(e2)
              }
              else {
                  return(e1)
              }
          }
          parent_props <- if (S7::S7_inherits(e2)) 
              S7::props(e2)
          else unclass(e2)
          n <- S7::prop_names(e1)[lengths(S7::props(e1)) == 0]
          S7::props(e1)[n] <- parent_props[n]
          if (is_rel(try_prop(e1, "size"))) {
              e1@size <- parent_props$size * unclass(e1@size)
          }
          if (is_rel(try_prop(e1, "linewidth"))) {
              e1@linewidth <- parent_props$linewidth * unclass(e1@linewidth)
          }
          if (is_theme_element(e1, "text")) {
              e1@margin <- combine_elements(e1@margin, parent_props$margin)
          }
          is_subclass <- !any(inherits(e2, class(e1), which = TRUE) == 
              0)
          is_subclass <- is_subclass && length(setdiff(class(e2), class(e1))) > 
              0
          if (is_subclass) {
              new <- defaults(S7::props(e1), S7::props(e2))
              S7::props(e2)[names(new)] <- new
              return(e2)
          }
          e1
      }

---

    Code
      print(body(environment(ggplot2::Layout$render)$f))
    Output
      {
          panels <- self$facet$draw_panel_content(panels, self$layout, 
              self$panel_scales_x, self$panel_scales_y, self$panel_params, 
              self$coord, data, theme, self$facet_params)
          plot_table <- self$facet$draw_panels(panels, self$layout, 
              self$panel_scales_x, self$panel_scales_y, self$panel_params, 
              self$coord, data, theme, self$facet_params)
          plot_table <- self$facet$set_panel_size(plot_table, theme)
          labels <- self$coord$labels(list(x = self$resolve_label(self$panel_scales_x[[1]], 
              labels), y = self$resolve_label(self$panel_scales_y[[1]], 
              labels)), self$panel_params[[1]])
          labels <- self$render_labels(labels, theme)
          self$facet$draw_labels(plot_table, self$layout, self$panel_scales_x, 
              self$panel_scales_y, self$panel_params, self$coord, data, 
              theme, labels, self$params)
      }

# upstream table assembly matches what the Rust layout mirrors

    Code
      print(body(utils::getS3method("ggplot_gtable", "ggplot2::ggplot_built", envir = asNamespace(
        "ggplot2"))))
    Output
      {
          plot <- data@plot
          layout <- data@layout
          data <- data@data
          theme <- plot@theme
          geom_grobs <- by_layer(function(l, d) l$draw_geom(d, layout), 
              plot@layers, data, "converting geom to grob")
          plot_table <- layout$render(geom_grobs, data, theme, plot@labels)
          legend_box <- plot@guides$assemble(theme)
          plot_table <- table_add_legends(plot_table, legend_box, theme)
          title <- element_render(theme, "plot.title", plot@labels$title, 
              margin_y = TRUE, margin_x = TRUE)
          title_height <- grobHeight(title)
          subtitle <- element_render(theme, "plot.subtitle", plot@labels$subtitle, 
              margin_y = TRUE, margin_x = TRUE)
          subtitle_height <- grobHeight(subtitle)
          caption <- element_render(theme, "plot.caption", plot@labels$caption, 
              margin_y = TRUE, margin_x = TRUE)
          caption_height <- grobHeight(caption)
          title_pos <- arg_match0(theme$plot.title.position %||% "panel", 
              c("panel", "plot"), arg_nm = "plot.title.position", error_call = expr(theme()))
          caption_pos <- arg_match0(theme$plot.caption.position %||% 
              "panel", values = c("panel", "plot"), arg_nm = "plot.caption.position", 
              error_call = expr(theme()))
          pans <- plot_table$layout[grepl("^panel", plot_table$layout$name), 
              , drop = FALSE]
          if (title_pos == "panel") {
              title_l <- min(pans$l)
              title_r <- max(pans$r)
          }
          else {
              title_l <- 1
              title_r <- ncol(plot_table)
          }
          if (caption_pos == "panel") {
              caption_l <- min(pans$l)
              caption_r <- max(pans$r)
          }
          else {
              caption_l <- 1
              caption_r <- ncol(plot_table)
          }
          plot_table <- gtable_add_rows(plot_table, subtitle_height, 
              pos = 0)
          plot_table <- gtable_add_grob(plot_table, subtitle, name = "subtitle", 
              t = 1, b = 1, l = title_l, r = title_r, clip = "off")
          plot_table <- gtable_add_rows(plot_table, title_height, pos = 0)
          plot_table <- gtable_add_grob(plot_table, title, name = "title", 
              t = 1, b = 1, l = title_l, r = title_r, clip = "off")
          plot_table <- gtable_add_rows(plot_table, caption_height, 
              pos = -1)
          plot_table <- gtable_add_grob(plot_table, caption, name = "caption", 
              t = -1, b = -1, l = caption_l, r = caption_r, clip = "off")
          plot_table <- table_add_tag(plot_table, plot@labels$tag, 
              theme)
          plot_margin <- calc_element("plot.margin", theme) %||% margin()
          plot_table <- gtable_add_padding(plot_table, plot_margin)
          if (is_theme_element(theme$plot.background)) {
              plot_table <- gtable_add_grob(plot_table, element_render(theme, 
                  "plot.background"), t = 1, l = 1, b = -1, r = -1, 
                  name = "background", z = -Inf)
              plot_table$layout <- plot_table$layout[c(nrow(plot_table$layout), 
                  1:(nrow(plot_table$layout) - 1)), ]
              plot_table$grobs <- plot_table$grobs[c(nrow(plot_table$layout), 
                  1:(nrow(plot_table$layout) - 1))]
          }
          attr(plot_table, "alt-label") <- plot@labels$alt
          plot_table
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          table <- gtable_add_padding(table, unit(0, "pt"))
          if (length(label) < 1) {
              return(table)
          }
          element <- calc_element("plot.tag", theme)
          if (is_theme_element(element, "blank")) {
              return(table)
          }
          position <- calc_element("plot.tag.position", theme) %||% 
              "topleft"
          location <- calc_element("plot.tag.location", theme) %||% 
              (if (is.numeric(position)) 
                  "plot"
              else "margin")
          if (is.numeric(position)) {
              if (location == "margin") {
                  cli::cli_abort(paste0("A {.cls numeric} {.arg plot.tag.position} cannot be used with ", 
                      "`{.val margin}` as {.arg plot.tag.location}."), 
                      call = expr(theme()))
              }
              check_length(position, 2L, call = expr(theme()), arg = I("A {.cls numeric} {.arg plot.tag.position}"))
              top <- left <- right <- bottom <- FALSE
          }
          else {
              position <- arg_match0(position[1], c("topleft", "top", 
                  "topright", "left", "right", "bottomleft", "bottom", 
                  "bottomright"), arg_nm = "plot.tag.position", error_call = expr(theme()))
              top <- position %in% c("topleft", "top", "topright")
              left <- position %in% c("topleft", "left", "bottomleft")
              right <- position %in% c("topright", "right", "bottomright")
              bottom <- position %in% c("bottomleft", "bottom", "bottomright")
          }
          tag <- element_grob(element, label = label, margin_y = TRUE, 
              margin_x = TRUE)
          height <- grobHeight(tag)
          width <- grobWidth(tag)
          if (location %in% c("plot", "panel")) {
              if (!is.numeric(position)) {
                  hjust <- try_prop(element, "hjust", default = 0.5)
                  if (right || left) {
                      x <- (1 - hjust) * width
                      if (right) {
                        x <- unit(1, "npc") - x
                      }
                  }
                  else {
                      x <- unit(hjust, "npc")
                  }
                  if (top || bottom) {
                      vjust <- try_prop(element, "vjust", default = 0.5)
                      y <- (1 - vjust) * height
                      if (top) {
                        y <- unit(1, "npc") - y
                      }
                  }
                  else {
                      y <- unit(vjust, "npc")
                  }
              }
              else {
                  x <- unit(position[1], "npc")
                  y <- unit(position[2], "npc")
              }
              tag <- element_grob(element, x = x, y = y, label = label, 
                  margin_y = TRUE, margin_x = TRUE)
              if (location == "plot") {
                  table <- gtable_add_grob(table, tag, name = "tag", 
                      clip = "off", t = 1, b = nrow(table), l = 1, 
                      r = ncol(table))
                  return(table)
              }
          }
          if (location == "panel") {
              place <- find_panel(table)
          }
          else {
              n_col <- ncol(table)
              n_row <- nrow(table)
              if (top) 
                  table$heights <- unit.c(height, table$heights[-1])
              if (left) 
                  table$widths <- unit.c(width, table$widths[-1])
              if (right) 
                  table$widths <- unit.c(table$widths[-n_col], width)
              if (bottom) 
                  table$heights <- unit.c(table$heights[-n_row], height)
              place <- data_frame0(t = 1L, r = n_col, b = n_row, l = 1L)
          }
          if (top) 
              place$b <- place$t
          if (left) 
              place$r <- place$l
          if (right) 
              place$l <- place$r
          if (bottom) 
              place$t <- place$b
          gtable_add_grob(table, tag, name = "tag", clip = "off", t = place$t, 
              l = place$l, b = place$b, r = place$r)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (is_zero(legends)) {
              legends <- rep(list(zeroGrob()), 5)
              names(legends) <- c(.trbl, "inside")
          }
          widths <- heights <- set_names(rep(list(unit(0, "cm")), length(legends)), 
              names(legends))
          empty <- vapply(legends, is_zero, logical(1))
          widths[!empty] <- lapply(legends[!empty], gtable_width)
          heights[!empty] <- lapply(legends[!empty], gtable_height)
          spacing <- calc_element("legend.box.spacing", theme) %||% 
              unit(0.2, "cm")
          zero <- unit(0, "pt")
          spacing <- lapply(empty, function(is_empty) if (is_empty) 
              zero
          else spacing)
          location <- switch(theme$legend.location %||% "panel", plot = plot_extent, 
              find_panel)
          place <- location(table)
          table <- gtable_add_cols(table, spacing$right, pos = -1)
          table <- gtable_add_cols(table, widths$right, pos = -1)
          table <- gtable_add_grob(table, legends$right, clip = "off", 
              t = place$t, b = place$b, l = -1, r = -1, name = "guide-box-right")
          table <- gtable_add_cols(table, spacing$left, pos = 0)
          table <- gtable_add_cols(table, widths$left, pos = 0)
          table <- gtable_add_grob(table, legends$left, clip = "off", 
              t = place$t, b = place$b, l = 1, r = 1, name = "guide-box-left")
          place <- location(table)
          table <- gtable_add_rows(table, spacing$bottom, pos = -1)
          table <- gtable_add_rows(table, heights$bottom, pos = -1)
          table <- gtable_add_grob(table, legends$bottom, clip = "off", 
              t = -1, b = -1, l = place$l, r = place$r, name = "guide-box-bottom")
          table <- gtable_add_rows(table, spacing$top, pos = 0)
          table <- gtable_add_rows(table, heights$top, pos = 0)
          table <- gtable_add_grob(table, legends$top, clip = "off", 
              t = 1, b = 1, l = place$l, r = place$r, name = "guide-box-top")
          place <- find_panel(table)
          table <- gtable_add_grob(table, legends$inside, clip = "off", 
              t = place$t, b = place$b, l = place$l, r = place$r, name = "guide-box-inside")
          table
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          layout <- table$layout
          data_frame0(t = min(layout[["t"]]), r = max(layout[["r"]]), 
              b = max(layout[["b"]]), l = min(layout[["l"]]), .size = 1L)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          layout <- table$layout
          panels <- layout[grepl("^panel", layout$name), , drop = FALSE]
          data_frame0(t = min(.subset2(panels, "t")), r = max(.subset2(panels, 
              "r")), b = max(.subset2(panels, "b")), l = min(.subset2(panels, 
              "l")), .size = 1)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (is.null(label)) {
              return(zeroGrob())
          }
          just <- rotate_just(angle, hjust, vjust)
          n <- max(length(x), length(y), 1)
          x <- x %||% unit(rep(just$hjust, n), "npc")
          y <- y %||% unit(rep(just$vjust, n), "npc")
          if (!is.unit(x)) {
              x <- unit(x, "npc")
          }
          if (!is.unit(y)) {
              y <- unit(y, "npc")
          }
          grob <- textGrob(label, x, y, hjust = hjust, vjust = vjust, 
              rot = angle, gp = gp, check.overlap = check.overlap)
          descent <- font_descent(gp$fontfamily, gp$fontface, gp$fontsize, 
              gp$cex)
          rad <- (angle[1]%%360)/180 * pi
          x_descent <- abs(sin(rad)) * descent
          y_descent <- abs(cos(rad)) * descent
          width <- unit(1, "grobwidth", grob) + x_descent
          height <- unit(1, "grobheight", grob) + y_descent
          if (is.null(margin)) {
              margin <- margin(0, 0, 0, 0)
          }
          margin_x <- isTRUE(margin_x)
          margin_y <- isTRUE(margin_y)
          new_x <- NULL
          new_y <- NULL
          new_width <- NULL
          new_height <- NULL
          if (margin_x) {
              new_width <- unit.c(margin[4], width, margin[2])
              new_x <- x - margin[2] * just$hjust + margin[4] * (1 - 
                  just$hjust)
          }
          if (margin_y) {
              new_height <- unit.c(margin[1], height, margin[3])
              new_y <- y - margin[1] * just$vjust + margin[3] * (1 - 
                  just$vjust)
          }
          if (xor(margin_x, margin_y)) {
              new_width <- new_width %||% unit(1, "null")
              new_height <- new_height %||% unit(1, "null")
          }
          new_width <- new_width %||% width
          new_height <- new_height %||% height
          x <- new_x %||% x
          y <- new_y %||% y
          grob$x <- x
          grob$y <- y
          if (isTRUE(debug)) {
              children <- gList(rectGrob(x = x, y = y, width = width, 
                  height = height, hjust = just$hjust, vjust = just$vjust, 
                  gp = gg_par(fill = "cornsilk", col = NA)), pointsGrob(x, 
                  y, pch = 20, gp = gg_par(col = "gold")), grob)
          }
          else {
              children <- gList(grob)
          }
          gTree(children = children, widths = new_width, heights = new_height, 
              cl = "titleGrob")
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          sum(x$widths)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          sum(x$heights)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (S7::S7_inherits(element)) {
              element <- S7::props(element)
          }
          if (!is.null(element)) {
              angle <- element$angle
              hjust <- element$hjust
              vjust <- element$vjust
          }
          angle <- (angle %||% 0)%%360
          if (is.character(hjust)) {
              hjust <- match(hjust, c("left", "right")) - 1
              hjust[is.na(hjust)] <- 0.5
          }
          if (is.character(vjust)) {
              vjust <- match(vjust, c("bottom", "top")) - 1
              vjust[is.na(vjust)] <- 0.5
          }
          size <- vec_size_common(angle, hjust, vjust)
          angle <- vec_recycle(angle, size)
          hjust <- vec_recycle(hjust, size)
          vjust <- vec_recycle(vjust, size)
          case <- findInterval(angle, c(0, 90, 180, 270, 360))
          hnew <- hjust
          vnew <- vjust
          is_case <- which(case == 2)
          hnew[is_case] <- 1 - vjust[is_case]
          vnew[is_case] <- hjust[is_case]
          is_case <- which(case == 3)
          hnew[is_case] <- 1 - hjust[is_case]
          vnew[is_case] <- 1 - vjust[is_case]
          is_case <- which(case == 4)
          hnew[is_case] <- vjust[is_case]
          vnew[is_case] <- 1 - hjust[is_case]
          list(hjust = hnew, vjust = vnew)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          cur_dev <- names(grDevices::dev.cur())
          if (cur_dev == "null device") {
              cache <- FALSE
          }
          else {
              cache <- TRUE
          }
          key <- paste0(cur_dev, ":", family, ":", face, ":", size, 
              ":", cex)
          key <- key[1]
          descent <- descent_cache[[key]]
          if (is.null(descent)) {
              descent <- convertHeight(grobDescent(textGrob(label = "gjpqyQ", 
                  gp = gg_par(fontsize = size, cex = cex, fontfamily = family, 
                      fontface = face))), "inches")
              if (cache) {
                  descent_cache[[key]] <- descent
              }
          }
          descent
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          position_dim <- if (is_vertical) 
              "y"
          else "x"
          label_margin_name <- if (is_vertical) 
              "margin_x"
          else "margin_y"
          n_breaks <- length(break_positions)
          break_positions <- unit(break_positions, "native")
          if (check.overlap) {
              priority <- axis_label_priority(n_breaks)
              break_labels <- break_labels[priority]
              break_positions <- break_positions[priority]
          }
          labels_grob <- exec(element_grob, label_element, `:=`(!!position_dim, 
              break_positions), `:=`(!!label_margin_name, TRUE), label = break_labels, 
              check.overlap = check.overlap)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (!is_theme_element(element, "text") || is.null(position) || 
              is.null(angle %|W|% NULL)) {
              return(element)
          }
          arg_match0(position, .trbl)
          check_number_decimal(angle)
          radian <- deg2rad(angle)
          digits <- 3
          cosine <- sign(round(cos(radian), digits))/2 + 0.5
          sine <- sign(round(sin(radian), digits))/2 + 0.5
          hjust <- switch(position, left = cosine, right = 1 - cosine, 
              top = 1 - sine, sine)
          vjust <- switch(position, left = 1 - sine, right = sine, 
              top = 1 - cosine, cosine)
          element@angle <- angle %||% try_prop(element, "angle")
          element@hjust <- hjust %||% try_prop(element, "hjust")
          element@vjust <- vjust %||% try_prop(element, "vjust")
          element
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (!is_guides(guides)) {
              return(zeroGrob())
          }
          pair <- guides$get_position(position)
          pair$params$draw_label <- labels %||% NULL
          pair$guide$draw(theme, params = pair$params)
      }

---

    Code
      print(body(environment(ggplot2::FacetNull$draw_panels)$f))
    Output
      {
          range <- ranges[[1]]
          aspect_ratio <- theme$aspect.ratio %||% coord$aspect(range)
          if (is.null(aspect_ratio)) {
              aspect_ratio <- 1
              respect <- FALSE
          }
          else {
              respect <- TRUE
          }
          axis_h <- coord$render_axis_h(range, theme)
          axis_v <- coord$render_axis_v(range, theme)
          all <- matrix(list(zeroGrob(), axis_h$top, zeroGrob(), axis_v$left, 
              panels[[1]], axis_v$right, zeroGrob(), axis_h$bottom, 
              zeroGrob()), ncol = 3, byrow = TRUE)
          z_matrix <- matrix(c(5, 6, 4, 7, 1, 8, 3, 9, 2), ncol = 3, 
              byrow = TRUE)
          grob_widths <- unit.c(grobWidth(axis_v$left), unit(1, "null"), 
              grobWidth(axis_v$right))
          grob_heights <- unit.c(grobHeight(axis_h$top), unit(abs(aspect_ratio), 
              "null"), grobHeight(axis_h$bottom))
          grob_names <- c("spacer", "axis-l", "spacer", "axis-t", "panel", 
              "axis-b", "spacer", "axis-r", "spacer")
          layout <- gtable_matrix("layout", all, widths = grob_widths, 
              heights = grob_heights, respect = respect, clip = "off", 
              z = z_matrix)
          layout$layout$name <- grob_names
          layout
      }

---

    Code
      print(body(environment(ggplot2::Facet$draw_labels)$f))
    Output
      {
          panel_dim <- find_panel(panels)
          xlab_height_top <- grobHeight(labels$x[[1]])
          panels <- gtable_add_rows(panels, xlab_height_top, pos = 0)
          panels <- gtable_add_grob(panels, labels$x[[1]], name = "xlab-t", 
              l = panel_dim$l, r = panel_dim$r, t = 1, clip = "off")
          xlab_height_bottom <- grobHeight(labels$x[[2]])
          panels <- gtable_add_rows(panels, xlab_height_bottom, pos = -1)
          panels <- gtable_add_grob(panels, labels$x[[2]], name = "xlab-b", 
              l = panel_dim$l, r = panel_dim$r, t = -1, clip = "off")
          panel_dim <- find_panel(panels)
          ylab_width_left <- grobWidth(labels$y[[1]])
          panels <- gtable_add_cols(panels, ylab_width_left, pos = 0)
          panels <- gtable_add_grob(panels, labels$y[[1]], name = "ylab-l", 
              l = 1, b = panel_dim$b, t = panel_dim$t, clip = "off")
          ylab_width_right <- grobWidth(labels$y[[2]])
          panels <- gtable_add_cols(panels, ylab_width_right, pos = -1)
          panels <- gtable_add_grob(panels, labels$y[[2]], name = "ylab-r", 
              l = -1, b = panel_dim$b, t = panel_dim$t, clip = "off")
          panels
      }

---

    Code
      print(body(environment(ggplot2::Facet$set_panel_size)$f))
    Output
      {
          new_widths <- calc_element("panel.widths", theme)
          new_heights <- calc_element("panel.heights", theme)
          if (is.null(new_widths) && is.null(new_heights)) {
              return(table)
          }
          rows <- panel_rows(table)
          cols <- panel_cols(table)
          if (isTRUE(table$respect) && xor(is.null(new_widths), is.null(new_heights)) && 
              nrow(rows) == 1 && nrow(cols) == 1) {
              old_width <- table$widths[cols$l]
              old_height <- table$heights[rows$t]
              if (identical(unitType(old_width), "null") && identical(unitType(old_height), 
                  "null")) {
                  ratio <- as.numeric(old_height)/as.numeric(old_width)
                  new_widths <- (new_widths %||% (new_heights/ratio))[1]
                  new_heights <- (new_heights %||% (new_widths * ratio))[1]
              }
          }
          if (length(new_widths) == 1L && nrow(cols) > 1L) {
              extra <- setdiff(seq(min(cols$l), max(cols$r)), union(cols$l, 
                  cols$r))
              extra <- unit(sum(width_cm(table$widths[extra])), "cm")
              relative <- as.numeric(table$widths[cols$l])
              new_widths <- (new_widths - extra) * (relative/sum(relative))
          }
          if (!is.null(new_widths)) {
              table$widths[cols$l] <- rep(new_widths, length.out = nrow(cols))
          }
          if (length(new_heights) == 1L && nrow(rows) > 1L) {
              extra <- setdiff(seq(min(rows$t), max(rows$t)), union(rows$t, 
                  rows$b))
              extra <- unit(sum(height_cm(table$heights[extra])), "cm")
              relative <- as.numeric(table$heights[rows$t])
              new_heights <- (new_heights - extra) * (relative/sum(relative))
          }
          if (!is.null(new_heights)) {
              table$heights[rows$t] <- rep(new_heights, length.out = nrow(rows))
          }
          table
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$measure_grobs)$f))
    Output
      {
          measure <- params$measure_text
          major_cm <- convertUnit(elements$major_length, "cm", valueOnly = TRUE)
          range <- range(0, major_cm)
          if (params$minor.ticks && !is_theme_element(elements$minor, 
              "blank")) {
              minor_cm <- convertUnit(elements$minor_length, "cm", 
                  valueOnly = TRUE)
              range <- range(range, minor_cm)
          }
          length <- unit(range[2], "cm")
          spacer <- max(unit(0, "pt"), unit(-1 * diff(range), "cm"))
          labels <- unit(measure(grobs$labels), "cm")
          title <- unit(measure(grobs$title), "cm")
          sizes <- unit.c(length, spacer, labels, title)
          if (params$lab_first) {
              sizes <- rev(sizes)
          }
          sizes
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$override_elements)$f))
    Output
      {
          elements$text <- label_angle_heuristic(elements$text, params$position, 
              params$angle)
          if (is_theme_element(elements$ticks, "blank")) {
              elements$major_length <- unit(0, "cm")
          }
          if (is_theme_element(elements$minor, "blank") || isFALSE(params$minor.ticks)) {
              elements$minor_length <- unit(0, "cm")
          }
          return(elements)
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$build_labels)$f))
    Output
      {
          if (".type" %in% names(key)) {
              key <- vec_slice(key, key$.type == "major")
          }
          labels <- validate_labels(key$.label)
          n_labels <- length(labels)
          if (n_labels < 1) {
              return(list(zeroGrob()))
          }
          pos <- key[[params$aes]]
          dodge_pos <- rep(seq_len(params$n.dodge %||% 1), length.out = n_labels)
          dodge_indices <- unname(split(seq_len(n_labels), dodge_pos))
          lapply(dodge_indices, function(indices) {
              draw_axis_labels(break_positions = pos[indices], break_labels = labels[indices], 
                  label_element = elements$text, is_vertical = params$vertical, 
                  check.overlap = params$check.overlap %||% FALSE)
          })
      }

---

    Code
      print(body(environment(ggplot2::Guide$draw)$f))
    Output
      {
          params <- replace_null(params, position = position, direction = direction)
          params <- self$setup_params(params)
          key <- params$key
          elems <- self$setup_elements(params, self$elements, theme)
          elems <- self$override_elements(params, elems, theme)
          if (prod(dim(key)) == 0) {
              out <- self$draw_early_exit(params, elems)
              return(out)
          }
          grobs <- list(title = self$build_title(params$title, elems, 
              params), ticks = self$build_ticks(key, elems, params))
          if (params$draw_label %||% TRUE) {
              grobs$labels <- self$build_labels(key, elems, params)
          }
          else {
              grobs$labels <- list(zeroGrob())
          }
          grobs$decor <- self$build_decor(params$decor, grobs, elems, 
              params)
          sizes <- self$measure_grobs(grobs, params, elems)
          layout <- self$arrange_layout(key, sizes, params, elems)
          self$assemble_drawing(grobs, layout, sizes, params, elems)
      }

---

    Code
      print(body(environment(ggplot2::Layout$render_labels)$f))
    Output
      {
          label_grobs <- lapply(names(labels), function(label) {
              lapply(c(1, 2), function(i) {
                  modify <- if (i == 1) {
                      switch(label, x = ".top", y = ".left")
                  }
                  else {
                      switch(label, x = ".bottom", y = ".right")
                  }
                  if (is.null(labels[[label]][[i]]) || is_waiver(labels[[label]][[i]])) 
                      return(zeroGrob())
                  element_render(theme = theme, element = paste0("axis.title.", 
                      label, modify), label = labels[[label]][[i]], 
                      margin_x = label == "y", margin_y = label == 
                        "x")
              })
          })
          names(label_grobs) <- names(labels)
          label_grobs
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian$labels)$f))
    Output
      {
          labels
      }

---

    Code
      print(body(gtable::gtable_add_padding))
    Output
      {
          padding <- rep(padding, length.out = 4)
          x <- gtable_add_rows(x, pos = 0, heights = padding[1])
          x <- gtable_add_cols(x, pos = -1, widths = padding[2])
          x <- gtable_add_rows(x, pos = -1, heights = padding[3])
          x <- gtable_add_cols(x, pos = 0, widths = padding[4])
          x
      }

