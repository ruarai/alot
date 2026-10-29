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

