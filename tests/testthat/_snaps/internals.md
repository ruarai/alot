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

# upstream step and text drawing match what the full tier mirrors

    Code
      print(body(environment(ggplot2::GeomStep$draw_panel)$f))
    Output
      {
          data <- flip_data(data, flipped_aes)
          if (isTRUE(flipped_aes)) {
              direction <- switch(direction, hv = "vh", vh = "hv", 
                  direction)
          }
          data <- dapply(data, "group", stairstep, direction = direction)
          data <- flip_data(data, flipped_aes)
          GeomPath$draw_panel(data, panel_params, coord, lineend = lineend, 
              linejoin = linejoin, linemitre = linemitre, arrow = arrow, 
              arrow.fill = arrow.fill)
      }

---

    Code
      print(body(utils::getFromNamespace("stairstep", "ggplot2")))
    Output
      {
          direction <- arg_match0(direction, c("hv", "vh", "mid"))
          data <- as.data.frame(data)[order(data$x), ]
          n <- nrow(data)
          if (n <= 1) {
              return(data[0, , drop = FALSE])
          }
          if (direction == "vh") {
              xs <- rep(1:n, each = 2)[-2 * n]
              ys <- c(1, rep(2:n, each = 2))
          }
          else if (direction == "hv") {
              ys <- rep(1:n, each = 2)[-2 * n]
              xs <- c(1, rep(2:n, each = 2))
          }
          else if (direction == "mid") {
              xs <- rep(1:(n - 1), each = 2)
              ys <- rep(1:n, each = 2)
          }
          if (direction == "mid") {
              gaps <- data$x[-1] - data$x[-n]
              mid_x <- data$x[-n] + gaps/2
              x <- c(data$x[1], mid_x[xs], data$x[n])
              y <- c(data$y[ys])
              data_attr <- data[c(1, xs, n), setdiff(names(data), c("x", 
                  "y"))]
          }
          else {
              x <- data$x[xs]
              y <- data$y[ys]
              data_attr <- data[xs, setdiff(names(data), c("x", "y"))]
          }
          data_frame0(x = x, y = y, data_attr)
      }

---

    Code
      print(body(environment(ggplot2::GeomText$draw_panel)$f))
    Output
      {
          lab <- data$label
          if (parse) {
              lab <- parse_safe(as.character(lab))
          }
          lab <- validate_labels(lab)
          data <- coord$transform(data, panel_params)
          data$vjust <- compute_just(data$vjust, data$y, data$x, data$angle)
          data$hjust <- compute_just(data$hjust, data$x, data$y, data$angle)
          size.unit <- resolve_text_unit(size.unit)
          textGrob(lab, data$x, data$y, default.units = "native", hjust = data$hjust, 
              vjust = data$vjust, rot = data$angle, gp = gg_par(col = alpha(data$colour, 
                  data$alpha), fontsize = data$size * size.unit, fontfamily = data$family, 
                  fontface = data$fontface, lineheight = data$lineheight), 
              check.overlap = check_overlap)
      }

---

    Code
      print(body(utils::getFromNamespace("compute_just", "ggplot2")))
    Output
      {
          if (!is.character(just)) {
              return(just)
          }
          if (any(grepl("outward|inward", just))) {
              angle <- angle%%360
              angle <- ifelse(angle > 180, angle - 360, angle)
              angle <- ifelse(angle < -180, angle + 360, angle)
              rotated_forward <- grepl("outward|inward", just) & (angle > 
                  45 & angle < 135)
              rotated_backwards <- grepl("outward|inward", just) & 
                  (angle < -45 & angle > -135)
              ab <- ifelse(rotated_forward | rotated_backwards, b, 
                  a)
              just_swap <- rotated_backwards | abs(angle) > 135
              inward <- (just == "inward" & !just_swap | just == "outward" & 
                  just_swap)
              just[inward] <- c("left", "middle", "right")[just_dir(ab[inward])]
              outward <- (just == "outward" & !just_swap) | (just == 
                  "inward" & just_swap)
              just[outward] <- c("right", "middle", "left")[just_dir(ab[outward])]
          }
          unname(c(left = 0, center = 0.5, right = 1, bottom = 0, middle = 0.5, 
              top = 1)[just])
      }

---

    Code
      print(body(utils::getFromNamespace("resolve_text_unit", "ggplot2")))
    Output
      {
          unit <- arg_match0(unit, c("mm", "pt", "cm", "in", "pc"))
          switch(unit, mm = .pt, cm = .pt * 10, `in` = 72.27, pc = 12, 
              1)
      }

---

    Code
      print(body(utils::getFromNamespace("validate_labels", "ggplot2")))
    Output
      {
          if (!obj_is_list(labels)) {
              return(labels)
          }
          labels[lengths(labels) == 0L] <- ""
          if (any(vapply(labels, is.language, logical(1)))) {
              inject(expression(!!!labels))
          }
          else {
              unlist(labels)
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

# upstream panel and axis drawing match what the Rust drawers mirror

    Code
      print(body(gg_fn(f)))
    Output
      {
          x_major <- panel_params$x$mapped_breaks()
          x_minor <- setdiff(panel_params$x$mapped_breaks_minor(), 
              x_major)
          y_major <- panel_params$y$mapped_breaks()
          y_minor <- setdiff(panel_params$y$mapped_breaks_minor(), 
              y_major)
          transform <- if (isTRUE(square)) {
              if (inherits(coord, "CoordFlip")) {
                  function(x) coord$transform(flip_axis_labels(x), 
                      panel_params)
              }
              else {
                  function(x) coord$transform(x, panel_params)
              }
          }
          else {
              function(x) coord_munch(coord, x, panel_params)
          }
          grill <- Map(f = breaks_as_grid, var = list(y_minor, x_minor, 
              y_major, x_major), type = c("minor.y", "minor.x", "major.y", 
              "major.x"), MoreArgs = list(theme = theme, transform = transform))
          grill <- compact(grill)
          background <- element_render(theme, "panel.background")
          if (!isTRUE(square) && !is_zero(background)) {
              gp <- background$gp
              background <- data_frame0(x = c(1, 1, -1, -1), y = c(1, 
                  -1, -1, 1)) * Inf
              background <- coord_munch(coord, background, panel_params, 
                  is_closed = TRUE)
              background <- polygonGrob(x = background$x, y = background$y, 
                  gp = gp)
          }
          ggname("grill", inject(grobTree(background, !!!grill)))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          n <- length(var)
          if (n < 1) {
              return(NULL)
          }
          df <- data_frame0(var = rep(var, each = 2), alt = rep(c(-Inf, 
              Inf), n), group = rep(seq_along(var), each = 2))
          colnames(df)[1:2] <- switch(type, major.y = , minor.y = c("y", 
              "x"), c("x", "y"))
          df <- transform(df)
          element_render(theme, paste0("panel.grid.", type), x = df$x, 
              y = df$y, id.lengths = vec_unrep(df$group)$times)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (n <= 0) {
              return(numeric(0))
          }
          c(1, n, axis_label_priority_between(1, n))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          n <- y - x + 1
          if (n <= 2) {
              return(numeric(0))
          }
          mid <- x - 1 + (n + 1)%/%2
          c(mid, axis_label_priority_between(x, mid), axis_label_priority_between(mid, 
              y))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          el <- calc_element(element, theme)
          if (is.null(el)) {
              cli::cli_inform("Theme element {.var {element}} is missing")
              return(zeroGrob())
          }
          grob <- element_grob(el, ...)
          ggname(paste(element, name, sep = "."), grob)
      }

---

    Code
      print(body(environment(ggplot2::Coord$draw_panel)$f))
    Output
      {
          fg <- self$render_fg(params, theme)
          bg <- self$render_bg(params, theme)
          if (isTRUE(theme$panel.ontop)) {
              panel <- list2(!!!panel, bg, fg)
          }
          else {
              panel <- list2(bg, !!!panel, fg)
          }
          gTree(children = inject(gList(!!!panel)), vp = viewport(clip = self$clip))
      }

---

    Code
      print(body(environment(ggplot2::Coord$render_fg)$f))
    Output
      {
          element_render(theme, "panel.border", fill = NA)
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian$render_bg)$f))
    Output
      {
          guide_grid(theme, panel_params, self)
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian$transform)$f))
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
      print(body(environment(ggplot2::Guide$build_ticks)$f))
    Output
      {
          force(length)
          if (!is_theme_element(elements)) {
              elements <- elements$ticks
          }
          if (!is_theme_element(elements, "line")) {
              return(zeroGrob())
          }
          if (!is.list(key)) {
              breaks <- key
          }
          else {
              breaks <- key[[params$aes]]
          }
          n_breaks <- length(breaks)
          if (n_breaks < 1) {
              return(zeroGrob())
          }
          tick_len <- rep(length %||% unit(0.2, "npc"), length.out = n_breaks)
          mark <- unit(rep(breaks, each = 2), "npc")
          pos <- unname(c(top = 1, bottom = 0, left = 0, right = 1)[position])
          dir <- -2 * pos + 1
          pos <- unit(rep(pos, 2 * n_breaks), "npc")
          dir <- rep(vec_interleave(dir, 0), n_breaks) * rep(tick_len, 
              each = 2)
          tick <- pos + dir
          flip_element_grob(elements, x = tick, y = mark, id.lengths = rep(2, 
              n_breaks), flip = position %in% c("top", "bottom"))
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$build_ticks)$f))
    Output
      {
          major <- Guide$build_ticks(vec_slice(key, (key$.type %||% 
              "major") == "major"), elements$ticks, params, position, 
              elements$major_length)
          if (!params$minor.ticks) {
              return(major)
          }
          minor <- Guide$build_ticks(vec_slice(key, (key$.type %||% 
              "major") == "minor"), elements$minor, params, position, 
              elements$minor_length)
          grobTree(major, minor, name = "ticks")
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$build_decor)$f))
    Output
      {
          if (empty(decor)) {
              return(zeroGrob())
          }
          element_grob(elements$line, x = unit(decor$x, "npc"), y = unit(decor$y, 
              "npc"))
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$assemble_drawing)$f))
    Output
      {
          axis_line <- grobs$decor
          z <- if (params$position == "left") 
              c(2, 1, 3)
          else 1:3
          z <- rep(z, c(1, length(grobs$labels), 1))
          grobs <- c(list(grobs$ticks), grobs$labels, list(grobs$title))
          gt <- exec(gtable, `:=`(!!params$orth_sizes, sizes), `:=`(!!params$para_sizes, 
              unit(1, "npc")), name = "axis")
          gt <- gtable_add_grob(gt, grobs, t = layout$t, b = layout$b, 
              l = layout$l, r = layout$r, clip = "off", z = z)
          vp <- exec(viewport, `:=`(!!params$orth_aes, unit(params$orth_side, 
              "npc")), `:=`(!!params$orth_size, max(params$measure_gtable(gt), 
              unit(1, "npc"))), just = params$opposite)
          if (params$position %in% c("left", "right")) {
              where <- layout$l[-c(1, length(layout$l))]
              just <- rotate_just(element = elements$text)$hjust %||% 
                  0.5
              gt <- gtable_add_cols(gt, unit(just, "null"), pos = min(where) - 
                  1)
              gt <- gtable_add_cols(gt, unit(1 - just, "null"), pos = max(where) + 
                  1)
          }
          if (params$position %in% c("top", "bottom")) {
              where <- layout$t[-c(1, length(layout$t))]
              just <- rotate_just(element = elements$text)$vjust %||% 
                  0.5
              gt <- gtable_add_rows(gt, unit(1 - just, "null"), pos = min(where) - 
                  1)
              gt <- gtable_add_rows(gt, unit(just, "null"), pos = max(where) + 
                  1)
          }
          absoluteGrob(gList(axis_line, gt), width = gtable_width(gt), 
              height = gtable_height(gt), vp = vp)
      }

---

    Code
      print(body(environment(ggplot2::GuideAxis$draw_early_exit)$f))
    Output
      {
          line <- self$build_decor(decor = params$decor, elements = elements, 
              params = params)
          absoluteGrob(gList(line), width = grobWidth(line), height = grobHeight(line))
      }

# upstream guide assembly matches what the legend drawers mirror

    Code
      print(body(gg_fn(f)))
    Output
      {
          data$shape <- translate_shape_string(data$shape %||% 19)
          pointsGrob(0.5, 0.5, pch = data$shape, gp = gg_par(col = alpha(data$colour %||% 
              "black", data$alpha), fill = fill_alpha(data$fill %||% 
              "black", data$alpha), pointsize = data$size %||% 1.5, 
              stroke = data$stroke %||% 0.5))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (is.null(keys)) {
              ans <- list(widths = NULL, heights = NULL)
              return(ans)
          }
          padding_zeroes <- rep(0, prod(dim) - n)
          widths <- c(get_key_size(keys, "width", n), padding_zeroes)
          heights <- c(get_key_size(keys, "height", n), padding_zeroes)
          widths <- matrix(widths, nrow = dim[1], ncol = dim[2], byrow = byrow)
          heights <- matrix(heights, nrow = dim[1], ncol = dim[2], 
              byrow = byrow)
          list(widths = pmax(default_width, apply(widths, 2, max)), 
              heights = pmax(default_height, apply(heights, 1, max)))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          size <- lapply(keys, attr, which = which)
          size[lengths(size) != 1] <- 0
          size <- matrix(unlist(size), ncol = n)
          apply(size, 2, max)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (!is.null(attr(key, "width")) && !is.null(attr(key, "height"))) {
              return(key)
          }
          if (!is.null(size) || !is.null(linewidth)) {
              size <- size %||% 0
              linewidth <- linewidth %||% 0
              size <- if (is.na(size)[1]) 
                  0
              else size[1]
              linewidth <- if (is.na(linewidth)[1]) 
                  0
              else linewidth[1]
              size <- (size + linewidth)/10
          }
          else {
              size <- NULL
          }
          attr(key, "width") <- attr(key, "width", TRUE) %||% size %||% 
              default[1]
          attr(key, "height") <- attr(key, "height", TRUE) %||% size %||% 
              default[2]
          key
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          margin <- margin %||% margin()
          margin <- switch(position, top = replace(margin, 3, margin[3] + 
              gap), bottom = replace(margin, 1, margin[1] + gap), left = replace(margin, 
              2, margin[2] + gap), right = replace(margin, 4, margin[4] + 
              gap))
          class(margin) <- c("ggplot2::margin", class(margin), "S7_object")
          margin
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (!is_discrete(key$.value)) {
              return(TRUE)
          }
          if (is_named(show)) {
              aes <- intersect(aes, names(show))
              show <- show[aes]
          }
          else {
              show <- show[rep(1L, length(aes))]
          }
          if (isTRUE(any(show)) || length(show) == 0) {
              return(TRUE)
          }
          if (isTRUE(!any(show))) {
              return(FALSE)
          }
          aes <- aes[is.na(show)]
          match <- which(names(data) %in% aes)
          if (length(match) == 0) {
              return(TRUE)
          }
          keep <- rep(FALSE, nrow(key))
          for (column in match) {
              keep <- keep | key$.value %in% data[[column]]
          }
          is_na <- which(is.na(key$.value) & !keep)
          if (length(is_na) > 0) {
              na_keep <- FALSE
              for (column in match) {
                  na_keep <- na_keep || !all(data[[column]] %in% key$.value)
              }
              keep[is_na] <- na_keep
          }
          keep
      }

---

    Code
      print(body(environment(guides[[m]])$f))
    Output
      {
          if (length(self$guides) < 1) {
              return(zeroGrob())
          }
          default_position <- theme$legend.position %||% "right"
          if (length(default_position) == 2) {
              default_position <- "inside"
          }
          if (!default_position %in% c(.trbl, "inside")) {
              return(zeroGrob())
          }
          positions <- vapply(params, function(p) p$position[1] %||% 
              default_position, character(1), USE.NAMES = FALSE)
          grobs <- self$draw(theme, positions, theme$legend.direction)
          keep <- !vapply(grobs, is_zero, logical(1), USE.NAMES = FALSE)
          grobs <- grobs[keep]
          if (length(grobs) < 1) {
              return(zeroGrob())
          }
          default_inside_just <- calc_element("legend.justification.inside", 
              theme)
          default_inside_position <- calc_element("legend.position.inside", 
              theme)
          groups <- data_frame0(positions = positions, justs = list(NULL), 
              coords = list(NULL))
          for (i in which(positions == "inside")) {
              just <- params[[i]]$theme[["legend.justification.inside"]]
              just <- valid.just(just %||% default_inside_just)
              coord <- params[[i]]$theme[["legend.position.inside"]]
              coord <- coord %||% default_inside_position %||% just
              groups$justs[[i]] <- just
              groups$coords[[i]] <- coord
          }
          groups <- vec_group_loc(vec_slice(groups, keep))
          grobs <- vec_chop(grobs, indices = groups$loc)
          names(grobs) <- groups$key$positions
          theme$legend.spacing <- theme$legend.spacing %||% unit(0.5, 
              "lines")
          theme$legend.spacing.y <- calc_element("legend.spacing.y", 
              theme)
          theme$legend.spacing.x <- calc_element("legend.spacing.x", 
              theme)
          for (i in vec_seq_along(groups)) {
              adjust <- NULL
              position <- groups$key$positions[i]
              if (position == "inside") {
                  adjust <- theme(legend.position.inside = groups$key$coords[[i]], 
                      legend.justification.inside = groups$key$justs[[i]])
              }
              adjust <- add_theme(theme, adjust, "internal theme settings")
              grobs[[i]] <- self$package_box(grobs[[i]], position, 
                  adjust)
          }
          is_inside <- names(grobs) == "inside"
          if (sum(is_inside) > 1) {
              inside <- gtable(unit(1, "npc"), unit(1, "npc"))
              inside <- gtable_add_grob(inside, grobs[is_inside], t = 1, 
                  l = 1, clip = "off", name = paste0("guide-box-inside-", 
                      seq_len(sum(is_inside))))
              grobs <- grobs[!is_inside]
              grobs$inside <- inside
          }
          grobs[setdiff(c(.trbl, "inside"), names(grobs))] <- list(zeroGrob())
          grobs
      }

---

    Code
      print(body(environment(guides[[m]])$f))
    Output
      {
          directions <- rep(direction %||% "vertical", length(positions))
          if (is.null(direction)) {
              directions[positions %in% c("top", "bottom")] <- "horizontal"
          }
          grobs <- vector("list", length(guides))
          for (i in seq_along(grobs)) {
              grobs[[i]] <- guides[[i]]$draw(theme = theme, position = positions[i], 
                  direction = directions[i], params = params[[i]])
          }
          grobs
      }

---

    Code
      print(body(environment(guides[[m]])$f))
    Output
      {
          if (is_zero(grobs) || length(grobs) == 0) {
              return(zeroGrob())
          }
          direction <- switch(position, top = , bottom = "horizontal", 
              "vertical")
          theme$legend.box <- theme$legend.box %||% direction
          theme$legend.box.just <- theme$legend.box.just %||% switch(direction, 
              vertical = c("left", "top"), horizontal = c("center", 
                  "top"))
          widths <- lapply(grobs, `[[`, "widths")
          heights <- lapply(grobs, `[[`, "heights")
          stretch_x <- any(unlist(lapply(widths, unitType)) == "null")
          stretch_y <- any(unlist(lapply(heights, unitType)) == "null")
          global_just <- paste0("legend.justification.", position)
          global_just <- valid.just(calc_element(global_just, theme))
          if (position == "inside") {
              inside_position <- theme$legend.position.inside %||% 
                  global_just
              global_xjust <- inside_position[1]
              global_yjust <- inside_position[2]
              global_margin <- margin()
          }
          else {
              global_xjust <- global_just[1]
              global_yjust <- global_just[2]
              global_margin <- margin(t = 1 - global_yjust, b = global_yjust, 
                  r = 1 - global_xjust, l = global_xjust, unit = "null")
          }
          box_just <- valid.just(theme$legend.box.just)
          box_xjust <- box_just[1]
          box_yjust <- box_just[2]
          margin <- calc_element("legend.box.margin", theme) %||% margin()
          if (identical(theme$legend.box, "horizontal")) {
              for (i in seq_along(grobs)) {
                  grobs[[i]] <- editGrob(grobs[[i]], vp = viewport(x = box_xjust, 
                      y = box_yjust, just = box_just, height = heightDetails(grobs[[i]])))
              }
              spacing <- theme$legend.spacing.x
              stretch_spacing <- any(unitType(spacing) == "null")
              if (!stretch_spacing) {
                  spacing <- convertWidth(spacing, "cm")
              }
              total_height <- max(inject(unit.c(!!!lapply(heights, 
                  sum))))
              if (stretch_x || stretch_spacing) {
                  widths <- redistribute_null_units(widths, spacing, 
                      margin, "width")
                  vp_width <- unit(1, "npc")
              }
              else {
                  widths <- inject(unit.c(!!!lapply(widths, sum)))
                  vp_width <- sum(widths, spacing * (length(grobs) - 
                      1L))
              }
              vp <- viewport(x = global_xjust, y = global_yjust, just = global_just, 
                  height = total_height, width = vp_width)
              guides <- gtable_row(name = "guides", grobs = grobs, 
                  widths = widths, height = total_height, vp = vp)
              guides <- gtable_add_col_space(guides, spacing)
          }
          else {
              for (i in seq_along(grobs)) {
                  grobs[[i]] <- editGrob(grobs[[i]], vp = viewport(x = box_xjust, 
                      y = box_yjust, just = box_just, width = widthDetails(grobs[[i]])))
              }
              spacing <- theme$legend.spacing.y
              stretch_spacing <- any(unitType(spacing) == "null")
              if (!stretch_spacing) {
                  spacing <- convertWidth(spacing, "cm")
              }
              total_width <- max(inject(unit.c(!!!lapply(widths, sum))))
              if (stretch_y || stretch_spacing) {
                  heights <- redistribute_null_units(heights, spacing, 
                      margin, "height")
                  vp_height <- unit(1, "npc")
              }
              else {
                  heights <- inject(unit.c(!!!lapply(heights, sum)))
                  vp_height <- sum(heights, spacing * (length(grobs) - 
                      1L))
              }
              vp <- viewport(x = global_xjust, y = global_yjust, just = global_just, 
                  height = vp_height, width = total_width)
              guides <- gtable_col(name = "guides", grobs = grobs, 
                  width = total_width, heights = heights, vp = vp)
              guides <- gtable_add_row_space(guides, spacing)
          }
          guides <- gtable_add_padding(guides, margin)
          background <- element_grob(theme$legend.box.background %||% 
              element_blank())
          guides <- gtable_add_grob(guides, background, t = 1, l = 1, 
              b = -1, r = -1, z = -Inf, clip = "off", name = "legend.box.background")
          if (stretch_x || stretch_spacing) {
              global_margin[c(2, 4)] <- unit(0, "cm")
          }
          if (stretch_y || stretch_spacing) {
              global_margin[c(1, 3)] <- unit(0, "cm")
          }
          guides <- gtable_add_padding(guides, global_margin)
          guides$name <- "guide-box"
          guides
      }

---

    Code
      print(body(environment(ggplot2::Guide$add_title)$f))
    Output
      {
          if (is_zero(title)) {
              return(gtable)
          }
          title_width_cm <- width_cm(title)
          title_height_cm <- height_cm(title)
          gtable <- switch(position, top = gtable_add_rows(gtable, 
              unit(title_height_cm, "cm"), pos = 0), right = gtable_add_cols(gtable, 
              unit(title_width_cm, "cm"), pos = -1), bottom = gtable_add_rows(gtable, 
              unit(title_height_cm, "cm"), pos = -1), left = gtable_add_cols(gtable, 
              unit(title_width_cm, "cm"), pos = 0))
          args <- switch(position, top = list(t = 1, l = 1, r = -1, 
              b = 1), right = list(t = 1, l = -1, r = -1, b = -1), 
              bottom = list(t = -1, l = 1, r = -1, b = -1), left = list(t = 1, 
                  l = 1, r = 1, b = -1), )
          gtable <- inject(gtable_add_grob(x = gtable, grobs = title, 
              !!!args, z = -Inf, name = "title", clip = "off"))
          if (position %in% c("top", "bottom")) {
              if (any(unitType(gtable$widths) == "null")) {
                  return(gtable)
              }
              table_width <- sum(width_cm(gtable$widths))
              extra_width <- max(0, title_width_cm - table_width)
              if (extra_width == 0) {
                  return(gtable)
              }
              extra_width <- unit((c(1, -1) * just$hjust + c(0, 1)) * 
                  extra_width, "cm")
              gtable <- gtable_add_cols(gtable, extra_width[1], pos = 0)
              gtable <- gtable_add_cols(gtable, extra_width[2], pos = -1)
          }
          else {
              if (any(unitType(gtable$heights) == "null")) {
                  return(gtable)
              }
              table_height <- sum(height_cm(gtable$heights))
              extra_height <- max(0, title_height_cm - table_height)
              if (extra_height == 0) {
                  return(gtable)
              }
              extra_height <- unit((c(-1, 1) * just$vjust + c(1, 0)) * 
                  extra_height, "cm")
              gtable <- gtable_add_rows(gtable, extra_height[1], pos = 0)
              gtable <- gtable_add_rows(gtable, extra_height[2], pos = -1)
          }
          gtable
      }

---

    Code
      print(body(environment(ggplot2::Guide$setup_elements)$f))
    Output
      {
          theme <- add_theme(theme, params$theme)
          is_char <- vapply(elements, is.character, logical(1))
          elements[is_char] <- lapply(elements[is_char], calc_element, 
              theme = theme)
          elements
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          params$direction <- arg_match0(params$direction, c("horizontal", 
              "vertical"), arg_nm = "direction")
          params$n_breaks <- n_breaks <- nrow(params$key)
          if (!is.null(params$nrow) && !is.null(params$ncol) && params$nrow * 
              params$ncol < n_breaks) {
              cli::cli_abort(paste0("{.arg nrow} * {.arg ncol} needs to be larger than the number of ", 
                  "breaks ({n_breaks})."))
          }
          if (is.null(params$nrow) && is.null(params$ncol)) {
              if (params$direction == "horizontal") {
                  params$nrow <- ceiling(n_breaks/5)
              }
              else {
                  params$ncol <- ceiling(n_breaks/20)
              }
          }
          params$nrow <- params$nrow %||% ceiling(n_breaks/params$ncol)
          params$ncol <- params$ncol %||% ceiling(n_breaks/params$nrow)
          params
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          theme <- add_theme(theme, params$theme)
          params$theme <- NULL
          text_position <- theme$legend.text.position %||% "right"
          title_position <- theme$legend.title.position %||% switch(params$direction, 
              vertical = "top", horizontal = "left")
          theme$legend.text.position <- arg_match0(text_position, .trbl, 
              arg_nm = "legend.text.position")
          theme$legend.title.position <- arg_match0(title_position, 
              .trbl, arg_nm = "legend.title.position")
          theme$legend.key.spacing <- calc_element("legend.key.spacing", 
              theme)
          gap <- theme$legend.key.spacing
          if (params$direction == "vertical") {
              theme$legend.key.spacing.y <- theme$legend.key.spacing.y %||% 
                  unit(0, "pt")
          }
          margin <- try_prop(calc_element("text", theme), "margin")
          title <- theme(text = element_text(hjust = 0, vjust = 0.5, 
              margin = position_margin(title_position, margin, gap)))
          elements$title <- calc_element("legend.title", add_theme(theme, 
              title))
          margin <- position_margin(text_position, margin, gap)
          text <- theme(text = switch(text_position, top = element_text(hjust = 0.5, 
              vjust = 0, margin = margin), bottom = element_text(hjust = 0.5, 
              vjust = 1, margin = margin), left = element_text(hjust = 1, 
              vjust = 0.5, margin = margin), right = element_text(hjust = 0, 
              vjust = 0.5, margin = margin)))
          elements$text <- calc_element("legend.text", add_theme(theme, 
              text))
          Guide$setup_elements(params, elements, theme)
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          if (any(c("key_width", "key_height") %in% names(elements))) {
              elements$stretch_x <- unitType(elements$key_width) == 
                  "null"
              elements$stretch_y <- unitType(elements$key_height) == 
                  "null"
              elements$width_cm <- width_cm(elements$key_width)
              elements$height_cm <- height_cm(elements$key_height)
          }
          if (any(c("spacing_x", "spacing_y") %in% names(elements))) {
              elements$spacing_x <- width_cm(elements$spacing_x)
              elements$spacing_y <- height_cm(elements$spacing_y)
          }
          elements$padding <- convertUnit(elements$margin %||% margin(), 
              "cm", valueOnly = TRUE)
          if (!is.null(elements$background)) {
              elements$background <- ggname("legend.background", element_grob(elements$background))
          }
          if (!is.null(elements$key)) {
              elements$key <- ggname("legend.key", element_grob(elements$key))
          }
          if (!is.null(elements$key_just)) {
              elements$key_just <- valid.just(elements$key_just)
          }
          elements$text <- label_angle_heuristic(elements$text, elements$text_position, 
              params$angle)
          elements
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          key_size <- c(elements$width_cm, elements$height_cm)
          just <- elements$key_just
          idx <- seq_len(params$n_breaks)
          key_glyphs <- lapply(idx, function(i) {
              glyph <- lapply(decor, function(dec) {
                  data <- vec_slice(dec$data, i)
                  if (!(data$.draw %||% TRUE)) {
                      return(zeroGrob())
                  }
                  key <- dec$draw_key(data, dec$params, key_size * 
                      10)
                  set_key_size(key, data$linewidth, data$size, key_size)
              })
              width <- vapply(glyph, get_attr, which = "width", default = 0, 
                  numeric(1))
              width <- max(width, 0, key_size[1], na.rm = TRUE)
              height <- vapply(glyph, get_attr, which = "height", default = 0, 
                  numeric(1))
              height <- max(height, 0, key_size[2], na.rm = TRUE)
              vp <- NULL
              if (!is.null(just)) {
                  vp <- viewport(x = just[1], y = just[2], just = just, 
                      width = unit(width, "cm"), height = unit(height, 
                        "cm"))
              }
              grob <- gTree(children = inject(gList(elements$key, !!!glyph)), 
                  vp = vp)
              attr(grob, "width") <- width
              attr(grob, "height") <- height
              grob
          })
          key_glyphs
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          n_labels <- length(key$.label)
          if (n_labels < 1) {
              out <- rep(list(zeroGrob()), nrow(key))
              return(out)
          }
          lapply(key$.label, function(lab) {
              ggname("guide.label", element_grob(elements$text, label = lab, 
                  margin_x = TRUE, margin_y = TRUE))
          })
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          byrow <- elements$byrow %||% FALSE
          n_breaks <- params$n_breaks %||% 1L
          dim <- c(params$nrow %||% 1L, params$ncol %||% 1L)
          sizes <- params$sizes %||% measure_legend_keys(grobs$decor, 
              n = n_breaks, dim = dim, byrow = byrow, default_width = elements$width_cm, 
              default_height = elements$height_cm)
          widths <- sizes$widths
          heights <- sizes$heights
          zeroes <- rep(0, prod(dim) - n_breaks)
          label_widths <- apply(matrix(c(width_cm(grobs$labels), zeroes), 
              nrow = dim[1], ncol = dim[2], byrow = byrow), 2, max)
          label_heights <- apply(matrix(c(height_cm(grobs$labels), 
              zeroes), nrow = dim[1], ncol = dim[2], byrow = byrow), 
              1, max)
          hgap <- elements$spacing_x %||% 0
          widths <- switch(elements$text_position, left = list(label_widths, 
              widths, hgap), right = list(widths, label_widths, hgap), 
              list(pmax(label_widths, widths), hgap))
          widths <- head(vec_interleave(!!!widths), -1)
          vgap <- elements$spacing_y %||% 0
          heights <- switch(elements$text_position, top = list(label_heights, 
              heights, vgap), bottom = list(heights, label_heights, 
              vgap), list(pmax(label_heights, heights), vgap))
          heights <- head(vec_interleave(!!!heights), -1)
          list(widths = widths, heights = heights)
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          break_seq <- seq_len(params$n_breaks %||% 1L)
          dim <- c(params$nrow %||% 1L, params$ncol %||% 1L)
          if (elements$byrow %||% FALSE) {
              row <- ceiling(break_seq/dim[2L])
              col <- (break_seq - 1L)%%dim[2L] + 1L
          }
          else {
              row <- (break_seq - 1L)%%dim[1L] + 1L
              col <- ceiling(break_seq/dim[1L])
          }
          key_row <- row * 2 - 1
          key_col <- col * 2 - 1
          position <- elements$text_position
          key_row <- key_row + switch(position, top = row, bottom = row - 
              1, 0)
          lab_row <- key_row + switch(position, top = -1, bottom = 1, 
              0)
          key_col <- key_col + switch(position, left = col, right = col - 
              1, 0)
          lab_col <- key_col + switch(position, left = -1, right = 1, 
              0)
          data_frame0(key_row = key_row, key_col = key_col, label_row = lab_row, 
              label_col = lab_col)
      }

---

    Code
      print(body(environment(ggplot2::GuideLegend[[m]])$f))
    Output
      {
          widths <- unit(sizes$widths, "cm")
          if (isTRUE(elements$stretch_x)) {
              widths[unique0(layout$key_col)] <- elements$key_width
          }
          heights <- unit(sizes$heights, "cm")
          if (isTRUE(elements$stretch_y)) {
              heights[unique0(layout$key_row)] <- elements$key_height
          }
          gt <- gtable(widths = widths, heights = heights)
          if (!is_zero(grobs$decor)) {
              n_key_layers <- params$n_key_layers %||% 1L
              key_cols <- rep(layout$key_col, each = n_key_layers)
              key_rows <- rep(layout$key_row, each = n_key_layers)
              gt <- gtable_add_grob(gt, grobs$decor, name = names(grobs$decor) %||% 
                  paste("key", key_rows, key_cols, c("bg", seq_len(n_key_layers - 
                      1)), sep = "-"), clip = "off", t = key_rows, 
                  r = key_cols, b = key_rows, l = key_cols)
          }
          if (!is_zero(grobs$labels)) {
              gt <- gtable_add_grob(gt, grobs$labels, name = names(labels) %||% 
                  paste("label", layout$label_row, layout$label_col, 
                      sep = "-"), clip = "off", t = layout$label_row, 
                  r = layout$label_col, b = layout$label_row, l = layout$label_col)
          }
          gt <- self$add_title(gt, grobs$title, elements$title_position, 
              rotate_just(element = elements$title))
          gt <- gtable_add_padding(gt, unit(elements$padding, "cm"))
          if (!is_zero(elements$background)) {
              gt <- gtable_add_grob(gt, elements$background, name = "background", 
                  clip = "off", t = 1, r = -1, b = -1, l = 1, z = -Inf)
          }
          gt
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          params$direction <- arg_match0(params$direction, c("horizontal", 
              "vertical"), arg_nm = "direction")
          params
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          if (params$direction == "horizontal") {
              theme$legend.key.width <- (theme$legend.key.width %||% 
                  rel(1)) * 5
              valid_position <- c("bottom", "top")
          }
          else {
              theme$legend.key.height <- (theme$legend.key.height %||% 
                  rel(1)) * 5
              valid_position <- c("right", "left")
          }
          theme <- replace_null(theme, legend.text.position = valid_position[1], 
              legend.ticks = params$default_ticks, legend.frame = params$default_frame)
          elements <- GuideLegend$setup_elements(params, elements, 
              theme)
          if (!elements$text_position %in% valid_position) {
              cli::cli_abort(paste0("When {.arg direction} is {.val {params$direction}}, ", 
                  "{.arg legend.text.position} must be one of ", "{.or {.val {valid_position}}}, not {.val {elements$text_position}}."))
          }
          elements
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          n_labels <- length(key$.label)
          if (n_labels < 1) {
              return(list(labels = zeroGrob()))
          }
          list(labels = flip_element_grob(elements$text, label = validate_labels(key$.label), 
              x = unit(key$.value, "npc"), margin_x = FALSE, margin_y = TRUE, 
              flip = params$direction == "vertical"))
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          pos <- key$.value
          if (!params$draw_lim[1]) 
              pos <- pos[-1]
          if (!params$draw_lim[2]) 
              pos <- pos[-length(pos)]
          position <- switch(params$direction, horizontal = c("bottom", 
              "top"), vertical = c("right", "left"))
          ticks_length <- rep(elements$ticks_length, length.out = 2)
          grobTree(Guide$build_ticks(pos, elements, params, position[1], 
              ticks_length[1]), Guide$build_ticks(pos, elements, params, 
              position[2], ticks_length[2]))
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          if (params$display == "raster") {
              image <- switch(params$direction, horizontal = t(decor$colour), 
                  vertical = rev(decor$colour))
              grob <- rasterGrob(image = image, width = 1, height = 1, 
                  default.units = "npc", gp = gpar(col = NA), interpolate = TRUE)
          }
          else if (params$display == "rectangles") {
              if (params$direction == "horizontal") {
                  width <- 1/nrow(decor)
                  height <- 1
                  x <- (seq_len(nrow(decor)) - 1) * width
                  y <- 0
              }
              else {
                  width <- 1
                  height <- 1/nrow(decor)
                  y <- (seq_len(nrow(decor)) - 1) * height
                  x <- 0
              }
              grob <- rectGrob(x = x, y = y, vjust = 0, hjust = 0, 
                  width = width, height = height, default.units = "npc", 
                  gp = gg_par(col = NA, fill = decor$colour))
          }
          else if (params$display == "gradient") {
              check_device("gradients", call = expr(guide_colourbar()))
              value <- if (isTRUE(params$reverse)) {
                  rescale(decor$value, to = c(1, 0))
              }
              else {
                  rescale(decor$value, to = c(0, 1))
              }
              position <- switch(params$direction, horizontal = list(y1 = unit(0.5, 
                  "npc"), y2 = unit(0.5, "npc")), vertical = list(x1 = unit(0.5, 
                  "npc"), x2 = unit(0.5, "npc")))
              gradient <- inject(linearGradient(decor$colour, value, 
                  !!!position))
              grob <- rectGrob(gp = gg_par(fill = gradient, col = NA))
          }
          frame <- element_grob(elements$frame, fill = NA)
          list(bar = grob, frame = frame, ticks = grobs$ticks)
      }

---

    Code
      print(body(environment(ggplot2::GuideColourbar[[m]])$f))
    Output
      {
          params$sizes <- list(widths = elements$width_cm, heights = elements$height_cm)
          GuideLegend$measure_grobs(grobs, params, elements)
      }

# upstream facet_wrap() assembly matches what the Rust layout mirrors

    Code
      print(body(gg_fn(f)))
    Output
      {
          panel_col <- panel_cols(table)$l
          panel_row <- panel_rows(table)$t
          for (i in rev(seq_along(panel_row))) {
              row_ind <- panel_row[i] + row_shift
              table <- gtable_add_rows(table, row_height[i], pos = row_ind)
              if (!missing(table2)) {
                  table <- gtable_add_grob(table, table2[i, ], t = row_ind + 
                      1, l = panel_col, clip = clip, name = paste0(name, 
                      "-", seq_along(panel_col), "-", i), z = z)
              }
          }
          table
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          panel_col <- panel_cols(table)$l
          panel_row <- panel_rows(table)$t
          for (i in rev(seq_along(panel_col))) {
              col_ind <- panel_col[i] + col_shift
              table <- gtable_add_cols(table, col_width[i], pos = col_ind)
              if (!missing(table2)) {
                  table <- gtable_add_grob(table, table2[, i], t = panel_row, 
                      l = col_ind + 1, clip = clip, name = paste0(name, 
                        "-", seq_along(panel_row), "-", i), z = z)
              }
          }
          table
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          empty <- which(empty %||% matrix(logical(), 0, 0), arr.ind = TRUE)
          sides <- match(names(axes), .trbl)
          margin <- c(1L, 2L, 1L, 2L)[sides]
          shift <- c(1L, -1L, -1L, 1L)[sides]
          sizes <- Map(measure_axes, axis = axes, margin = margin, 
              shift = shift, MoreArgs = list(empty_idx = empty))
          names <- paste0("axis-", substr(names(axes), 1, 1))
          shift <- c(-1L, 0L, 0L, -1L)[sides]
          weave <- list(weave_tables_row, weave_tables_col)[c(1, 2, 
              1, 2)][sides]
          for (i in seq_along(axes)) {
              panels <- weave[[i]](panels, axes[[i]], shift[i], sizes[[i]], 
                  names[i], z = z)
          }
          panels
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          dim <- dim(axis)
          measure <- switch(margin, height_cm, width_cm)
          cm <- matrix(measure(axis), dim[1], dim[2])
          if (nrow(empty_idx) > 0 && shift != 0) {
              set_zero <- empty_idx
              set_zero[, margin] <- set_zero[, margin] + shift
              keep <- set_zero[, margin] <= dim[margin] & set_zero[, 
                  margin] > 0
              set_zero <- set_zero[keep, , drop = FALSE]
          }
          else {
              set_zero <- matrix(integer(), nrow = 0, ncol = 2)
          }
          cm[set_zero] <- 0
          unit(apply(cm, margin, max), "cm")
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          (col - 1) * nrow + row
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          labeller <- match.fun(labeller)
          if (empty(label_df)) {
              return(if (horizontal) {
                  list(top = NULL, bottom = NULL)
              } else {
                  list(left = NULL, right = NULL)
              })
          }
          labels <- data_frame0(!!!labeller(label_df))
          ncol <- ncol(labels)
          nrow <- nrow(labels)
          labels_vec <- unlist(labels, use.names = FALSE)
          clip <- calc_element("strip.clip", theme)[[1]]
          clip <- pmatch(clip, c("on", "off", "inherit"), nomatch = 3)
          clip <- c("on", "off", "inherit")[clip]
          if (horizontal) {
              grobs_top <- lapply(labels_vec, element_render, theme = theme, 
                  element = "strip.text.x.top", margin_x = TRUE, margin_y = TRUE)
              grobs_top <- assemble_strips(matrix(grobs_top, ncol = ncol, 
                  nrow = nrow), theme, horizontal, clip = clip)
              grobs_bottom <- lapply(labels_vec, element_render, theme = theme, 
                  element = "strip.text.x.bottom", margin_x = TRUE, 
                  margin_y = TRUE)
              grobs_bottom <- assemble_strips(matrix(grobs_bottom, 
                  ncol = ncol, nrow = nrow), theme, horizontal, clip = clip)
              list(top = grobs_top, bottom = grobs_bottom)
          }
          else {
              grobs_left <- lapply(labels_vec, element_render, theme = theme, 
                  element = "strip.text.y.left", margin_x = TRUE, margin_y = TRUE)
              grobs_left <- assemble_strips(matrix(grobs_left, ncol = ncol, 
                  nrow = nrow), theme, horizontal, clip = clip)
              grobs_right <- lapply(unlist(labels[, rev(seq_len(ncol(labels))), 
                  drop = FALSE], use.names = FALSE), element_render, 
                  theme = theme, element = "strip.text.y.right", margin_x = TRUE, 
                  margin_y = TRUE)
              grobs_right <- assemble_strips(matrix(grobs_right, ncol = ncol, 
                  nrow = nrow), theme, horizontal, clip = clip)
              list(left = grobs_left, right = grobs_right)
          }
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (length(grobs) == 0 || is_zero(grobs[[1]])) {
              grobs <- grobs[seq_len(NROW(grobs))]
              return(grobs)
          }
          if (horizontal) {
              height <- max_height(grobs)
              width <- unit(1, "null")
          }
          else {
              height <- unit(1, "null")
              width <- max_width(grobs)
          }
          background <- if (horizontal) 
              "strip.background.x"
          else "strip.background.y"
          background <- element_render(theme, background)
          grobs[] <- lapply(grobs, function(x) {
              ggname("strip", gTree(children = gList(background, x)))
          })
          apply(grobs, 1, function(x) {
              if (horizontal) {
                  mat <- matrix(x, ncol = 1)
              }
              else {
                  mat <- matrix(x, nrow = 1)
              }
              gtable_matrix("strip", mat, rep(width, ncol(mat)), rep(height, 
                  nrow(mat)), clip = clip)
          })
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          axes <- list()
          if (!is.null(x)) {
              axes$x <- lapply(x, coord$render_axis_h, theme)
          }
          if (!is.null(y)) {
              axes$y <- lapply(y, coord$render_axis_v, theme)
          }
          if (transpose) {
              axes <- list(x = list(top = lapply(axes$x, `[[`, "top"), 
                  bottom = lapply(axes$x, `[[`, "bottom")), y = list(left = lapply(axes$y, 
                  `[[`, "left"), right = lapply(axes$y, `[[`, "right")))
          }
          axes
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (labels$x && labels$y) {
              return(ranges)
          }
          draw <- matrix(TRUE, length(ranges), 4, dimnames = list(NULL, 
              c("top", "bottom", "left", "right")))
          if (!labels$x) {
              xmax <- vec_ave(layout$ROW, layout$COL, max)
              xmin <- vec_ave(layout$ROW, layout$COL, min)
              draw[which(layout$ROW != xmax), "bottom"] <- FALSE
              draw[which(layout$ROW != xmin), "top"] <- FALSE
          }
          if (!labels$y) {
              ymax <- vec_ave(layout$COL, layout$ROW, max)
              ymin <- vec_ave(layout$COL, layout$ROW, min)
              draw[which(layout$COL != ymax), "right"] <- FALSE
              draw[which(layout$COL != ymin), "left"] <- FALSE
          }
          for (i in seq_along(ranges)) {
              ranges[[i]]$draw_labels <- as.list(draw[i, ])
          }
          ranges
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          height <- max(unlist(lapply(grobs, height_cm)))
          if (!value_only) 
              height <- unit(height, "cm")
          height
      }

---

    Code
      print(body(environment(ggplot2::Facet[[m]])$f))
    Output
      {
          free <- params$free %||% list(x = FALSE, y = FALSE)
          space <- params$space_free %||% list(x = FALSE, y = FALSE)
          aspect_ratio <- theme$aspect.ratio
          if (!is.null(aspect_ratio) && (space$x || space$y)) {
              cli::cli_abort("Free scales cannot be mixed with a fixed aspect ratio.")
          }
          if (!coord$is_free()) {
              if (space$x && space$y) {
                  aspect_ratio <- aspect_ratio %||% coord$ratio
              }
              else if (free$x || free$y) {
                  msg <- paste0("{.fn {snake_class(self)}} can't use free scales with ", 
                      "{.fn {snake_class(coord)}}")
                  if (!is.null(coord$ratio)) {
                      msg <- paste0(msg, " with a fixed {.arg ratio} argument")
                  }
                  cli::cli_abort(paste0(msg, "."))
              }
          }
          table <- self$init_gtable(panels, layout, theme, ranges, 
              params, aspect_ratio = aspect_ratio %||% coord$aspect(ranges[[1]]))
          table <- self$attach_axes(table, layout, ranges, coord, theme, 
              params)
          self$attach_strips(table, layout, params, theme)
      }

---

    Code
      print(body(environment(ggplot2::Facet[[m]])$f))
    Output
      {
          dim <- c(max(layout$ROW), max(layout$COL))
          table <- matrix(list(zeroGrob()), dim[1], dim[2])
          table[cbind(layout$ROW, layout$COL)] <- panels
          widths <- unit(rep(1, dim[2]), "null")
          heights <- unit(rep(1 * abs(aspect_ratio %||% 1), dim[1]), 
              "null")
          space <- params$space_free %||% list(x = FALSE, y = FALSE)
          if (space$x) {
              idx <- layout$PANEL[layout$ROW == 1]
              widths <- vapply(idx, function(i) diff(ranges[[i]]$x.range), 
                  numeric(1))
              widths <- unit(widths, "null")
          }
          if (space$y) {
              idx <- layout$PANEL[layout$COL == 1]
              heights <- vapply(idx, function(i) diff(ranges[[i]]$y.range), 
                  numeric(1))
              heights <- unit(heights * abs(aspect_ratio %||% 1), "null")
          }
          table <- gtable_matrix("layout", table, widths = widths, 
              heights = heights, respect = !is.null(aspect_ratio), 
              clip = "off", z = matrix(1, dim[1], dim[2]))
          table$layout$name <- paste("panel", rep(seq_len(dim[2]), 
              each = dim[1]), rep(seq_len(dim[1]), dim[2]), sep = "-")
          spacing <- lapply(c(x = "panel.spacing.x", y = "panel.spacing.y"), 
              calc_element, theme = theme)
          table <- gtable_add_col_space(table, spacing$x)
          table <- gtable_add_row_space(table, spacing$y)
          table
      }

---

    Code
      print(body(environment(ggplot2::FacetWrap[[m]])$f))
    Output
      {
          if (inherits(coord, "CoordFlip")) {
              layout[c("SCALE_X", "SCALE_Y")] <- layout[c("SCALE_Y", 
                  "SCALE_X")]
          }
          panel_order <- order(layout$ROW, layout$COL)
          layout <- layout[panel_order, ]
          panels <- panels[panel_order]
          ggproto_parent(Facet, self)$draw_panels(panels = panels, 
              layout = layout, ranges = ranges, coord = coord, theme = theme, 
              params = params)
      }

---

    Code
      print(body(environment(ggplot2::FacetWrap[[m]])$f))
    Output
      {
          draw_axes <- params$draw_axes %||% list(x = FALSE, y = FALSE)
          axis_labels <- params$axis_labels %||% list(x = TRUE, y = TRUE)
          free <- params$free %||% list(x = FALSE, y = FALSE)
          ranges <- censor_labels(ranges, layout, axis_labels)
          original <- render_axes(ranges, ranges, coord, theme, transpose = TRUE)
          x_order <- if (axis_labels$x) 
              layout$SCALE_X
          else seq_len(nrow(layout))
          y_order <- if (axis_labels$y) 
              layout$SCALE_Y
          else seq_len(nrow(layout))
          original$x <- lapply(original$x, `[`, i = x_order)
          original$y <- lapply(original$y, `[`, i = y_order)
          dim <- c(max(layout$ROW), max(layout$COL))
          index <- convertInd(layout$ROW, layout$COL, dim[1])
          empty <- matrix(list(zeroGrob()), dim[1], dim[2])
          top <- bottom <- left <- right <- empty
          top[index] <- original$x$top
          bottom[index] <- original$x$bottom
          left[index] <- original$y$left
          right[index] <- original$y$right
          if (!(free$x || draw_axes$x)) {
              top[-1, ] <- list(zeroGrob())
              bottom[-dim[1], ] <- list(zeroGrob())
          }
          if (!(free$y || draw_axes$y)) {
              left[, -1] <- list(zeroGrob())
              right[, -dim[2]] <- list(zeroGrob())
          }
          empty <- matrix(TRUE, dim[1], dim[2])
          empty[index] <- FALSE
          if (!any(empty)) {
              axes <- list(top = top, bottom = bottom, left = left, 
                  right = right)
              return(weave_axes(table, axes, empty))
          }
          matched <- vec_match(data_frame0(ROW = as.vector(row(empty)), 
              COL = as.vector(col(empty))), layout[, c("ROW", "COL")])
          empty_bottom <- which(apply(empty, 2, function(x) c(diff(x) == 
              1, FALSE)))
          empty_top <- which(apply(empty, 2, function(x) c(FALSE, diff(x) == 
              -1)))
          empty_right <- which(t(apply(empty, 1, function(x) c(diff(x) == 
              1, FALSE))))
          empty_left <- which(t(apply(empty, 1, function(x) c(FALSE, 
              diff(x) == -1))))
          inside <- (theme$strip.placement %||% "inside") == "inside"
          strip <- params$strip.position %||% "top"
          clash <- c(top = FALSE, bottom = FALSE, left = FALSE, right = FALSE)
          if (length(empty_bottom) > 0) {
              x_axes <- original$x$bottom[matched[empty_bottom]]
              clash["bottom"] <- strip == "bottom" && !inside && !free$x && 
                  !all(vapply(x_axes, is_zero, logical(1)))
              if (!clash["bottom"]) {
                  bottom[empty_bottom] <- x_axes
              }
          }
          if (length(empty_top) > 0) {
              x_axes <- original$x$top[matched[empty_top]]
              clash["top"] <- strip == "top" && !inside && !free$x && 
                  !all(vapply(x_axes, is_zero, logical(1)))
              if (!clash["top"]) {
                  top[empty_top] <- x_axes
              }
          }
          if (length(empty_right) > 0) {
              y_axes <- original$y$right[matched[empty_right]]
              clash["right"] <- strip == "right" && !inside && !free$y && 
                  !all(vapply(y_axes, is_zero, logical(1)))
              if (!clash["right"]) {
                  right[empty_right] <- y_axes
              }
          }
          if (length(empty_left) > 0) {
              y_axes <- original$y$left[matched[empty_left]]
              clash["left"] <- strip == "left" && !inside && !free$y && 
                  !all(vapply(y_axes, is_zero, logical(1)))
              if (!clash["left"]) {
                  left[empty_left] <- y_axes
              }
          }
          if (any(clash)) {
              cli::cli_warn("Suppressing axis rendering when \\\n        {.code strip.position =\"{strip}\"} and \\\n        {.code strip.placement = \"outside\".}")
          }
          axes <- list(top = top, bottom = bottom, left = left, right = right)
          weave_axes(table, axes, empty)
      }

---

    Code
      print(body(environment(ggplot2::FacetWrap[[m]])$f))
    Output
      {
          strips <- self$format_strip_labels(layout, params)
          strips <- render_strips(strips$facets, strips$facets, theme = theme)
          padding <- convertUnit(calc_element("strip.switch.pad.wrap", 
              theme), "cm")
          position <- params$strip.position %||% "top"
          pos <- substr(position, 1, 1)
          prefix <- paste0("strip-", pos)
          dim <- c(max(layout$ROW), max(layout$COL))
          index <- convertInd(layout$ROW, layout$COL, dim[1])
          mat <- matrix(list(zeroGrob()), dim[1], dim[2])
          mat[index] <- unlist(unname(strips), recursive = FALSE)[[position]]
          if (position %in% c("top", "bottom")) {
              inside <- "strip.placement.x"
              size <- apply(mat, 1, max_height, value_only = TRUE)
              weave <- weave_tables_row
          }
          else {
              inside <- "strip.placement.y"
              size <- apply(mat, 2, max_width, value_only = TRUE)
              weave <- weave_tables_col
          }
          inside <- (calc_element(inside, theme) %||% "inside") == 
              "inside"
          shift <- switch(position, top = , left = c(-1, -2), c(0, 
              1))
          shift <- if (inside) 
              shift[1]
          else shift[2]
          size <- unit(size, "cm")
          table <- weave(table, mat, shift, size, name = prefix, z = 2, 
              clip = "off")
          if (!inside) {
              axes <- grepl(paste0("axis-", pos), table$layout$name)
              has_axes <- !vapply(table$grobs[axes], is_zero, logical(1))
              has_axes <- split(has_axes, table$layout[[pos]][axes])
              has_axes <- vapply(has_axes, sum, numeric(1)) > 0
              padding <- rep(padding, length(has_axes))
              padding[!has_axes] <- unit(0, "cm")
              table <- weave(table, , shift, padding)
          }
          table
      }

---

    Code
      print(body(environment(ggplot2::FacetWrap[[m]])$f))
    Output
      {
          if (length(params$facets) == 0) {
              labels <- data_frame0(`(all)` = "(all)", .size = 1)
          }
          else {
              labels <- layout[intersect(names(params$facets), names(layout))]
          }
          if (empty(labels)) {
              return(NULL)
          }
          attr(labels, "facet") <- "wrap"
          attr(labels, "type") <- switch(params$strip.position, left = , 
              right = "rows", "cols")
          labeller <- match.fun(params$labeller)
          list(facets = data_frame0(!!!labeller(labels)))
      }

# upstream facet_grid() assembly matches what the Rust layout mirrors

    Code
      print(body(gg_fn(f)))
    Output
      {
          if (is.null(grobs)) {
              return(table)
          }
          panel_col <- panel_cols(table)
          panel_row <- panel_rows(table)
          row <- switch(side, bottom = max(panel_row$b) + shift - 1L, 
              top = min(panel_row$t) - shift, panel_row$t)
          col <- switch(side, right = max(panel_col$r) + shift - 1L, 
              left = min(panel_col$l) - shift, panel_col$l)
          if (!is.null(spacing)) {
              table <- switch(side, bottom = , top = gtable_add_rows(table, 
                  spacing, row), left = , right = gtable_add_cols(table, 
                  spacing, col))
              row <- row + as.numeric(side == "bottom")
              col <- col + as.numeric(side == "right")
          }
          table <- switch(side, bottom = , top = gtable_add_rows(table, 
              max_height(grobs), row), left = , right = gtable_add_cols(table, 
              max_width(grobs), col))
          name <- paste(name, seq_along(grobs), sep = "-")
          row <- row + as.numeric(side %in% c("top", "bottom"))
          col <- col + as.numeric(side %in% c("left", "right"))
          gtable_add_grob(table, grobs, t = row, l = col, name = name, 
              z = z, clip = clip)
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          grobs <- table$grobs[grep(pattern, table$layout$name)]
          !all(vapply(grobs, is_zero, logical(1)))
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          panels <- table$layout[grepl("^panel", table$layout$name), 
              , drop = FALSE]
          unique0(panels[, c("l", "r")])
      }

---

    Code
      print(body(gg_fn(f)))
    Output
      {
          panels <- table$layout[grepl("^panel", table$layout$name), 
              , drop = FALSE]
          unique0(panels[, c("t", "b")])
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
      print(body(environment(ggplot2::FacetGrid[[m]])$f))
    Output
      {
          draw_axes <- params$draw_axes %||% list(x = FALSE, y = FALSE)
          axis_labels <- params$axis_labels %||% list(x = TRUE, y = TRUE)
          dim <- c(max(layout$ROW), max(layout$COL))
          if (!axis_labels$x) {
              cols <- seq_len(nrow(layout))
              x_order <- as.integer(layout$PANEL[order(layout$ROW, 
                  layout$COL)])
          }
          else {
              cols <- which(layout$ROW == 1)
              x_order <- layout$COL
          }
          if (!axis_labels$y) {
              rows <- seq_len(nrow(layout))
              y_order <- as.integer(layout$PANEL[order(layout$ROW, 
                  layout$COL)])
          }
          else {
              rows <- which(layout$COL == 1)
              y_order <- layout$ROW
          }
          ranges <- censor_labels(ranges, layout, axis_labels)
          axes <- render_axes(ranges[cols], ranges[rows], coord, theme, 
              transpose = TRUE)
          mtx <- function(x, o) matrix(x[o], dim[1], dim[2], byrow = TRUE)
          if (draw_axes$x) {
              table <- weave_axes(table, lapply(axes$x, mtx, o = x_order))
          }
          else {
              table <- seam_table(table, axes$x$top, side = "top", 
                  name = "axis-t", z = 3)
              table <- seam_table(table, axes$x$bottom, side = "bottom", 
                  name = "axis-b", z = 3)
          }
          if (draw_axes$y) {
              table <- weave_axes(table, lapply(axes$y, mtx, o = y_order))
          }
          else {
              table <- seam_table(table, axes$y$left, side = "left", 
                  name = "axis-l", z = 3)
              table <- seam_table(table, axes$y$right, side = "right", 
                  name = "axis-r", z = 3)
          }
          table
      }

---

    Code
      print(body(environment(ggplot2::FacetGrid[[m]])$f))
    Output
      {
          strips <- self$format_strip_labels(layout, params)
          strips <- render_strips(strips$cols, strips$rows, theme = theme)
          padding <- convertUnit(calc_element("strip.switch.pad.grid", 
              theme), "cm")
          switch_x <- !is.null(params$switch) && params$switch %in% 
              c("both", "x")
          inside_x <- (calc_element("strip.placement.x", theme) %||% 
              "inside") == "inside"
          shift_x <- if (inside_x) 
              1
          else 2
          if (switch_x) {
              space <- if (!inside_x & table_has_grob(table, "axis-b")) 
                  padding
              table <- seam_table(table, strips$x$bottom, side = "bottom", 
                  name = "strip-b", shift = shift_x, z = 2, clip = "off", 
                  spacing = space)
          }
          else {
              space <- if (!inside_x & table_has_grob(table, "axis-t")) 
                  padding
              table <- seam_table(table, strips$x$top, side = "top", 
                  name = "strip-t", shift = shift_x, z = 2, clip = "off", 
                  spacing = space)
          }
          switch_y <- !is.null(params$switch) && params$switch %in% 
              c("both", "y")
          inside_y <- (calc_element("strip.placement.y", theme) %||% 
              "inside") == "inside"
          shift_y <- if (inside_y) 
              1
          else 2
          if (switch_y) {
              space <- if (!inside_y & table_has_grob(table, "axis-l")) 
                  padding
              table <- seam_table(table, strips$y$left, side = "left", 
                  name = "strip-l", shift = shift_y, z = 2, clip = "off", 
                  spacing = space)
          }
          else {
              space <- if (!inside_y & table_has_grob(table, "axis-r")) 
                  padding
              table <- seam_table(table, strips$y$right, side = "right", 
                  name = "strip-r", shift = shift_y, z = 2, clip = "off", 
                  spacing = space)
          }
          table
      }

---

    Code
      print(body(environment(ggplot2::FacetGrid[[m]])$f))
    Output
      {
          labeller <- match.fun(params$labeller)
          cols <- intersect(names(layout), names(params$cols))
          if (length(cols) > 0) {
              col_vars <- unique0(layout[cols])
              attr(col_vars, "type") <- "cols"
              attr(col_vars, "facet") <- "grid"
              cols <- data_frame0(!!!labeller(col_vars))
          }
          else {
              cols <- NULL
          }
          rows <- intersect(names(layout), names(params$rows))
          if (length(rows) > 0) {
              row_vars <- unique0(layout[rows])
              attr(row_vars, "type") <- "rows"
              attr(row_vars, "facet") <- "grid"
              rows <- data_frame0(!!!labeller(row_vars))
          }
          else {
              rows <- NULL
          }
          list(cols = cols, rows = rows)
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian[[m]])$f))
    Output
      {
          list(top = panel_guides_grob(panel_params$guides, position = "top", 
              theme = theme, labels = panel_params$draw_labels$top), 
              bottom = panel_guides_grob(panel_params$guides, position = "bottom", 
                  theme = theme, labels = panel_params$draw_labels$bottom))
      }

---

    Code
      print(body(environment(ggplot2::CoordCartesian[[m]])$f))
    Output
      {
          list(left = panel_guides_grob(panel_params$guides, position = "left", 
              theme = theme, labels = panel_params$draw_labels$left), 
              right = panel_guides_grob(panel_params$guides, position = "right", 
                  theme = theme, labels = panel_params$draw_labels$right))
      }

# upstream complete themes and element grobs match what the full tier covers

    Code
      print(body(utils::getS3method("element_grob", "ggplot2::element_rect", envir = asNamespace(
        "ggplot2"))))
    Output
      {
          if (lifecycle::is_present(size)) {
              deprecate_warn0("3.4.0", "element_grob.element_rect(size)", 
                  "element_grob.element_rect(linewidth)")
              linewidth <- size
          }
          gp <- gg_par(lwd = linewidth, col = colour, fill = fill, 
              lty = linetype, linejoin = linejoin)
          element_gp <- gg_par(lwd = element@linewidth, col = element@colour, 
              fill = element@fill, lty = element@linetype, linejoin = element@linejoin)
          rectGrob(x, y, width, height, gp = modify_list(element_gp, 
              gp), ...)
      }

---

    Code
      print(body(utils::getS3method("element_grob", "ggplot2::element_line", envir = asNamespace(
        "ggplot2"))))
    Output
      {
          if (lifecycle::is_present(size)) {
              deprecate_warn0("3.4.0", "element_grob.element_line(size)", 
                  "element_grob.element_line(linewidth)")
              linewidth <- size
          }
          arrow <- if (is.logical(element@arrow) && !element@arrow) {
              NULL
          }
          else {
              element@arrow
          }
          if (is.null(arrow)) {
              arrow.fill <- colour
              element@arrow.fill <- element@colour
          }
          gp <- gg_par(col = colour, fill = arrow.fill %||% colour, 
              lwd = linewidth, lty = linetype, lineend = lineend, linejoin = linejoin)
          element_gp <- gg_par(col = element@colour, fill = element@arrow.fill %||% 
              element@colour, lwd = element@linewidth, lty = element@linetype, 
              lineend = element@lineend, linejoin = element@linejoin)
          polylineGrob(x, y, default.units = default.units, gp = modify_list(element_gp, 
              gp), id.lengths = id.lengths, arrow = arrow, ...)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          t <- theme(line = element_line(colour = ink, linewidth = base_line_size, 
              linetype = 1, lineend = "butt", linejoin = "round"), 
              rect = element_rect(fill = paper, colour = ink, linewidth = base_rect_size, 
                  linetype = 1, linejoin = "round"), text = element_text(family = base_family, 
                  face = "plain", colour = ink, size = base_size, lineheight = 0.9, 
                  hjust = 0.5, vjust = 0.5, angle = 0, margin = margin(), 
                  debug = FALSE), title = element_text(family = header_family), 
              spacing = unit(half_line, "pt"), margins = margin_auto(half_line), 
              point = element_point(colour = ink, shape = 19, fill = paper, 
                  size = (base_size/11) * 1.5, stroke = base_line_size), 
              polygon = element_polygon(fill = paper, colour = ink, 
                  linewidth = base_rect_size, linetype = 1, linejoin = "round"), 
              geom = element_geom(ink = ink, paper = paper, accent = accent, 
                  linewidth = base_line_size, borderwidth = base_line_size, 
                  linetype = 1L, bordertype = 1L, family = base_family, 
                  fontsize = base_size, pointsize = (base_size/11) * 
                      1.5, pointshape = 19), axis.line = element_blank(), 
              axis.line.x = NULL, axis.line.y = NULL, axis.text = element_text(size = rel(0.8), 
                  colour = col_mix(ink, paper, 0.302)), axis.text.x = element_text(margin = margin(t = 0.8 * 
                  half_line/2), vjust = 1), axis.text.x.top = element_text(margin = margin(b = 0.8 * 
                  half_line/2), vjust = 0), axis.text.y = element_text(margin = margin(r = 0.8 * 
                  half_line/2), hjust = 1), axis.text.y.right = element_text(margin = margin(l = 0.8 * 
                  half_line/2), hjust = 0), axis.text.r = element_text(margin = margin(l = 0.8 * 
                  half_line/2, r = 0.8 * half_line/2), hjust = 0.5), 
              axis.ticks = element_line(colour = col_mix(ink, paper, 
                  0.2)), axis.ticks.length = rel(0.5), axis.ticks.length.x = NULL, 
              axis.ticks.length.x.top = NULL, axis.ticks.length.x.bottom = NULL, 
              axis.ticks.length.y = NULL, axis.ticks.length.y.left = NULL, 
              axis.ticks.length.y.right = NULL, axis.minor.ticks.length = rel(0.75), 
              axis.title.x = element_text(margin = margin(t = half_line/2), 
                  vjust = 1), axis.title.x.top = element_text(margin = margin(b = half_line/2), 
                  vjust = 0), axis.title.y = element_text(angle = 90, 
                  margin = margin(r = half_line/2), vjust = 1), axis.title.y.right = element_text(angle = -90, 
                  margin = margin(l = half_line/2), vjust = 1), legend.background = element_rect(colour = NA), 
              legend.spacing = rel(2), legend.spacing.x = NULL, legend.spacing.y = NULL, 
              legend.margin = NULL, legend.key = NULL, legend.key.size = unit(1.2, 
                  "lines"), legend.key.height = NULL, legend.key.width = NULL, 
              legend.key.spacing = NULL, legend.text = element_text(size = rel(0.8)), 
              legend.title = element_text(hjust = 0), legend.ticks.length = rel(0.2), 
              legend.position = "right", legend.direction = NULL, legend.justification = "center", 
              legend.box = NULL, legend.box.margin = margin_auto(0), 
              legend.box.background = element_blank(), legend.box.spacing = rel(2), 
              panel.background = element_rect(fill = col_mix(ink, paper, 
                  0.92), colour = NA), panel.border = element_blank(), 
              panel.grid = element_line(colour = paper), panel.grid.minor = element_line(linewidth = rel(0.5)), 
              panel.spacing = NULL, panel.spacing.x = NULL, panel.spacing.y = NULL, 
              panel.ontop = FALSE, strip.background = element_rect(fill = col_mix(ink, 
                  paper, 0.85), colour = NA), strip.clip = "on", strip.text = element_text(colour = col_mix(ink, 
                  paper, 0.1), size = rel(0.8), margin = margin_auto(0.8 * 
                  half_line)), strip.text.x = NULL, strip.text.y = element_text(angle = -90), 
              strip.text.y.left = element_text(angle = 90), strip.placement = "inside", 
              strip.placement.x = NULL, strip.placement.y = NULL, strip.switch.pad.grid = unit(half_line/2, 
                  "pt"), strip.switch.pad.wrap = unit(half_line/2, 
                  "pt"), plot.background = element_rect(colour = paper), 
              plot.title = element_text(size = rel(1.2), hjust = 0, 
                  vjust = 1, margin = margin(b = half_line)), plot.title.position = "panel", 
              plot.subtitle = element_text(hjust = 0, vjust = 1, margin = margin(b = half_line)), 
              plot.caption = element_text(size = rel(0.8), hjust = 1, 
                  vjust = 1, margin = margin(t = half_line)), plot.caption.position = "panel", 
              plot.tag = element_text(size = rel(1.2), hjust = 0.5, 
                  vjust = 0.5), plot.tag.position = "topleft", plot.margin = NULL, 
              complete = TRUE)
          ggplot_global$theme_all_null %+replace% t
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          theme_grey(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(panel.background = element_rect(fill = paper, 
              colour = NA), panel.border = element_rect(colour = col_mix(ink, 
              paper, 0.2)), panel.grid = element_line(colour = col_mix(ink, 
              paper, 0.92)), panel.grid.minor = element_line(linewidth = rel(0.5)), 
              strip.background = element_rect(fill = col_mix(ink, paper, 
                  0.851), colour = col_mix(ink, paper, 0.2)), complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          theme_bw(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(axis.text = element_text(colour = ink, 
              size = rel(0.8)), axis.ticks = element_line(colour = ink, 
              linewidth = rel(0.5)), panel.border = element_rect(colour = ink, 
              linewidth = rel(1)), panel.grid = element_line(colour = ink), 
              panel.grid.major = element_line(linewidth = rel(0.1)), 
              panel.grid.minor = element_line(linewidth = rel(0.05)), 
              strip.background = element_rect(fill = ink), strip.text = element_text(colour = paper, 
                  size = rel(0.8), margin = margin_auto(0.8 * half_line)), 
              complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          theme_grey(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(panel.background = element_rect(fill = paper, 
              colour = NA), panel.border = element_rect(colour = col_mix(ink, 
              paper, 0.702), linewidth = rel(1)), panel.grid = element_line(colour = col_mix(ink, 
              paper, 0.871)), panel.grid.major = element_line(linewidth = rel(0.5)), 
              panel.grid.minor = element_line(linewidth = rel(0.25)), 
              axis.ticks = element_line(colour = col_mix(ink, paper, 
                  0.702), linewidth = rel(0.5)), strip.background = element_rect(fill = col_mix(ink, 
                  paper, 0.702), colour = NA), strip.text = element_text(colour = paper, 
                  size = rel(0.8), margin = margin_auto(0.8 * half_line)), 
              complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          theme_grey(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(panel.background = element_rect(fill = col_mix(ink, 
              paper, 0.499), colour = NA), panel.grid = element_line(colour = col_mix(ink, 
              paper, 0.42)), panel.grid.major = element_line(linewidth = rel(0.5)), 
              panel.grid.minor = element_line(linewidth = rel(0.25)), 
              axis.ticks = element_line(colour = col_mix(ink, paper, 
                  0.2), linewidth = rel(0.5)), strip.background = element_rect(fill = col_mix(ink, 
                  paper, 0.15), colour = NA), strip.text = element_text(colour = col_mix(ink, 
                  paper, 0.899), size = rel(0.8), margin = margin_auto(0.8 * 
                  half_line)), complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          theme_bw(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(axis.ticks = element_blank(), 
              axis.text.x.bottom = element_text(margin = margin(t = 0.45 * 
                  base_size)), axis.text.x.top = element_text(margin = margin(b = 0.45 * 
                  base_size)), axis.text.y.left = element_text(margin = margin(r = 0.45 * 
                  base_size)), axis.text.y.right = element_text(margin = margin(l = 0.45 * 
                  base_size)), legend.background = element_blank(), 
              legend.key = element_blank(), panel.background = element_blank(), 
              panel.border = element_blank(), strip.background = element_blank(), 
              plot.background = element_rect(fill = paper, colour = NA), 
              complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          theme_bw(base_size = base_size, base_family = base_family, 
              header_family = header_family, base_line_size = base_line_size, 
              base_rect_size = base_rect_size, ink = ink, paper = paper, 
              accent = accent) %+replace% theme(panel.border = element_blank(), 
              panel.grid = element_blank(), axis.text = element_text(size = rel(0.8)), 
              axis.line = element_line(lineend = "square"), axis.ticks = element_line(), 
              strip.background = element_rect(linewidth = rel(2)), 
              complete = TRUE)
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          t <- theme(line = element_blank(), rect = element_rect(fill = paper, 
              colour = NA, linewidth = 0, linetype = 1, inherit.blank = FALSE, 
              linejoin = "round"), polygon = element_blank(), point = element_blank(), 
              text = element_text(family = base_family, face = "plain", 
                  colour = ink, size = base_size, lineheight = 0.9, 
                  hjust = 0.5, vjust = 0.5, angle = 0, margin = margin(), 
                  debug = FALSE), title = element_text(family = header_family), 
              spacing = unit(half_line, "pt"), margins = margin_auto(half_line), 
              geom = element_geom(ink = ink, paper = paper, accent = accent, 
                  linewidth = base_line_size, borderwidth = base_line_size, 
                  linetype = 1L, bordertype = 1L, family = base_family, 
                  fontsize = base_size, pointsize = (base_size/11) * 
                      1.5, pointshape = 19), axis.text = element_blank(), 
              axis.title = element_blank(), axis.ticks.length = rel(0), 
              axis.ticks.length.x = NULL, axis.ticks.length.x.top = NULL, 
              axis.ticks.length.x.bottom = NULL, axis.ticks.length.y = NULL, 
              axis.ticks.length.y.left = NULL, axis.ticks.length.y.right = NULL, 
              axis.minor.ticks.length = NULL, legend.box = NULL, legend.key.size = unit(1.2, 
                  "lines"), legend.position = "right", legend.text = element_text(size = rel(0.8)), 
              legend.title = element_text(hjust = 0), legend.key.spacing = rel(1), 
              legend.margin = margin_auto(0), legend.box.margin = margin_auto(0), 
              legend.box.spacing = unit(0.2, "cm"), legend.ticks.length = rel(0.2), 
              legend.background = element_blank(), legend.frame = element_blank(), 
              legend.box.background = element_blank(), strip.clip = "on", 
              strip.text = element_text(size = rel(0.8)), strip.switch.pad.grid = rel(0.5), 
              strip.switch.pad.wrap = rel(0.5), strip.background = element_blank(), 
              panel.ontop = FALSE, panel.spacing = NULL, panel.background = element_blank(), 
              panel.border = element_blank(), plot.margin = margin_auto(0), 
              plot.title = element_text(size = rel(1.2), hjust = 0, 
                  vjust = 1, margin = margin(t = half_line)), plot.title.position = "panel", 
              plot.subtitle = element_text(hjust = 0, vjust = 1, margin = margin(t = half_line)), 
              plot.caption = element_text(size = rel(0.8), hjust = 1, 
                  vjust = 1, margin = margin(t = half_line)), plot.caption.position = "panel", 
              plot.tag = element_text(size = rel(1.2), hjust = 0.5, 
                  vjust = 0.5), plot.tag.position = "topleft", plot.background = element_rect(), 
              complete = TRUE)
          ggplot_global$theme_all_null %+replace% t
      }

---

    Code
      print(body(utils::getFromNamespace(f, "ggplot2")))
    Output
      {
          half_line <- base_size/2
          t <- theme(line = element_line(colour = ink, linewidth = base_line_size, 
              linetype = 1, lineend = "butt", linejoin = "round"), 
              rect = element_rect(fill = paper, colour = ink, linewidth = base_rect_size, 
                  linetype = 1, linejoin = "round"), text = element_text(family = base_family, 
                  face = "plain", colour = ink, size = base_size, lineheight = 0.9, 
                  hjust = 0.5, vjust = 0.5, angle = 0, margin = margin(), 
                  debug = FALSE), point = element_point(colour = ink, 
                  shape = 19, fill = paper, size = (base_size/11) * 
                      1.5, stroke = base_line_size), polygon = element_polygon(fill = paper, 
                  colour = ink, linewidth = base_rect_size, linetype = 1, 
                  linejoin = "round"), title = element_text(family = header_family), 
              spacing = unit(half_line, "pt"), margins = margin_auto(half_line), 
              geom = element_geom(ink = ink, paper = paper, accent = accent, 
                  linewidth = base_line_size, borderwidth = base_line_size, 
                  family = base_family, fontsize = base_size, linetype = 1L, 
                  pointsize = (base_size/11) * 1.5, pointshape = 19), 
              axis.line = element_blank(), axis.line.x = NULL, axis.line.y = NULL, 
              axis.text = element_text(size = rel(0.8), colour = col_mix(ink, 
                  paper, 0.302)), axis.text.x = element_text(margin = margin(t = 0.8 * 
                  half_line/2), vjust = 1), axis.text.x.top = element_text(margin = margin(b = 0.8 * 
                  half_line/2), vjust = 0), axis.text.y = element_text(margin = margin(r = 0.8 * 
                  half_line/2), hjust = 1), axis.text.y.right = element_text(margin = margin(l = 0.8 * 
                  half_line/2), hjust = 0), axis.ticks = element_line(colour = col_mix(ink, 
                  paper, 0.2)), axis.ticks.length = rel(0.5), axis.ticks.length.x = NULL, 
              axis.ticks.length.x.top = NULL, axis.ticks.length.x.bottom = NULL, 
              axis.ticks.length.y = NULL, axis.ticks.length.y.left = NULL, 
              axis.ticks.length.y.right = NULL, axis.minor.ticks.length = rel(0.75), 
              axis.title.x = element_text(margin = margin(t = half_line/2), 
                  vjust = 1), axis.title.x.top = element_text(margin = margin(b = half_line/2), 
                  vjust = 0), axis.title.y = element_text(angle = 90, 
                  margin = margin(r = half_line/2), vjust = 1), axis.title.y.right = element_text(angle = -90, 
                  margin = margin(l = half_line/2), vjust = 1), legend.background = element_rect(colour = NA), 
              legend.spacing = rel(2), legend.spacing.x = NULL, legend.spacing.y = NULL, 
              legend.margin = margin_auto(0, unit = "cm"), legend.key = NULL, 
              legend.key.size = unit(1.2, "lines"), legend.key.height = NULL, 
              legend.key.width = NULL, legend.key.spacing = NULL, legend.key.spacing.x = NULL, 
              legend.key.spacing.y = NULL, legend.text = element_text(size = rel(0.8)), 
              legend.title = element_text(hjust = 0), legend.ticks.length = rel(0.2), 
              legend.position = "right", legend.direction = NULL, legend.justification = "center", 
              legend.box = NULL, legend.box.margin = margin_auto(0, 
                  unit = "cm"), legend.box.background = element_blank(), 
              legend.box.spacing = rel(2), panel.background = element_rect(fill = paper, 
                  colour = NA), panel.border = element_rect(colour = col_mix(ink, 
                  paper, 0.2)), panel.grid.major = element_blank(), 
              panel.grid.minor = element_blank(), panel.spacing = NULL, 
              panel.spacing.x = NULL, panel.spacing.y = NULL, panel.ontop = FALSE, 
              strip.background = element_rect(fill = col_mix(ink, paper, 
                  0.85), colour = col_mix(ink, paper, 0.2)), strip.clip = "on", 
              strip.text = element_text(colour = col_mix(ink, paper, 
                  0.1), size = rel(0.8), margin = margin_auto(0.8 * 
                  half_line)), strip.text.x = NULL, strip.text.y = element_text(angle = -90), 
              strip.text.y.left = element_text(angle = 90), strip.placement = "inside", 
              strip.placement.x = NULL, strip.placement.y = NULL, strip.switch.pad.grid = rel(0.5), 
              strip.switch.pad.wrap = rel(0.5), plot.background = element_rect(colour = paper), 
              plot.title = element_text(size = rel(1.2), hjust = 0, 
                  vjust = 1, margin = margin(b = half_line)), plot.title.position = "panel", 
              plot.subtitle = element_text(hjust = 0, vjust = 1, margin = margin(b = half_line)), 
              plot.caption = element_text(size = rel(0.8), hjust = 1, 
                  vjust = 1, margin = margin(t = half_line)), plot.caption.position = "panel", 
              plot.tag = element_text(size = rel(1.2), hjust = 0.5, 
                  vjust = 0.5), plot.tag.position = "topleft", plot.margin = NULL, 
              complete = TRUE)
          ggplot_global$theme_all_null %+replace% t
      }

