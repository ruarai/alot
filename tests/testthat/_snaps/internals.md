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

