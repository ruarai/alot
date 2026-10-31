# String metrics as grid sees them on a ragg device (PHASE2.md, Architecture
# 4). R resolves family and face to font files once per distinct style, as
# ragg's TextRenderer::load_font() does through systemfonts (ragg
# src/text_renderer.h); Rust measures (alot-core/src/render/text.rs).

# Font file and face index for each family/face, NA where alot doesn't
# mirror ragg: the symbol face (5), and fonts with OpenType features or
# variations (textshaping would apply them). Faces 2 and 4 are bold, 3 and 4
# italic.
text_fonts <- function(family, face) {
  face <- as.integer(face)
  n <- max(length(family), length(face))
  family <- rep_len(family, n)
  face <- rep_len(face, n)
  key <- paste(family, face, sep = "\r")
  first <- !duplicated(key)
  fam <- family[first]
  fac <- face[first]
  ok <- !is.na(fam) & fac %in% 1:4
  path <- rep(NA_character_, length(fam))
  index <- rep(NA_integer_, length(fam))
  cache <- font_cache$fonts
  if (!is.null(cache)) {
    for (i in which(ok)) {
      hit <- cache[[key[first][i]]]
      if (!is.null(hit)) {
        path[i] <- hit$path
        index[i] <- hit$index
        ok[i] <- FALSE
      }
    }
  }
  if (any(ok)) {
    m <- systemfonts::match_fonts(
      fam[ok],
      italic = fac[ok] %in% c(3L, 4L),
      weight = ifelse(fac[ok] %in% c(2L, 4L), "bold", "normal")
    )
    plain <- lengths(m$features) == 0 & lengths(m$variations) == 0
    path[ok] <- ifelse(plain, m$path, NA_character_)
    index[ok] <- m$index
    if (!is.null(cache)) {
      for (i in which(ok)) {
        cache[[key[first][i]]] <- list(path = path[i], index = index[i])
      }
    }
  }
  at <- match(key, key[first])
  list2DF(list(path = path[at], index = index[at]))
}

# text_fonts()' matches, kept for the length of one render (render_raster(),
# alot_render_coverage()): systemfonts::match_fonts() takes about 0.3 ms a
# call and a page asks for the same few faces a dozen times or more. Fonts
# registered between renders are seen.
font_cache <- new.env(parent = emptyenv())

# Starts the cache unless a render up the stack has; TRUE if this call did,
# when the caller ends it with font_cache_close().
font_cache_open <- function() {
  if (!is.null(font_cache$fonts)) {
    return(FALSE)
  }
  font_cache$fonts <- new.env(parent = emptyenv())
  TRUE
}

font_cache_close <- function() {
  font_cache$fonts <- NULL
}

# Metrics in device pixels of each string, as GEStrWidth(), GEStrMetric()
# and GEStrHeight() (R src/main/engine.c) report them on a ragg device of
# resolution `res`, `scaling` and `pointsize`: a data frame of `width`,
# `ascent`, `descent` and `height`, NA where alot would defer to ragg (see
# rs_text_metrics()). Arguments recycle to the length of `text`.
text_metrics <- function(text, family = "", face = 1L, fontsize = 12, cex = 1,
                         lineheight = 1.2, res = 72, scaling = 1,
                         pointsize = 12) {
  n <- length(text)
  if (n == 0) {
    # Zero-length vectors aren't passed to Rust: their data pointers aren't
    # aligned, which Rust's slices reject.
    return(data.frame(width = double(), ascent = double(), descent = double(), height = double()))
  }
  args <- vctrs::vec_recycle_common(
    family = family, face = face, fontsize = fontsize, cex = cex,
    lineheight = lineheight, .size = n
  )
  font <- text_fonts(args$family, args$face)
  key <- vctrs::vec_group_id(font)
  first <- !duplicated(key)
  # ragg's res_mod, its stringWidth() and metricInfo() size (ps * cex *
  # res_mod) and GEStrHeight()'s line height (lineheight * cex * cra[1] *
  # ps / startps, with cra[1] = 1.2 * pointsize * res_mod).
  res_mod <- scaling * res / 72
  size <- args$fontsize * args$cex * res_mod
  line <- args$lineheight * args$cex * (1.2 * pointsize * res_mod) *
    args$fontsize / pointsize
  out <- rs_text_metrics(
    enc2utf8(as.character(text)), as.integer(key),
    font$path[first][order(key[first])], font$index[first][order(key[first])],
    as.double(size), as.double(line)
  )
  list2DF(out)
}

# The tier text limits a plot to: "full" if alot measures every string as
# ragg does, "hybrid" if any needs ragg (a glyph missing from its font,
# which ragg would draw from a fallback font, or a font alot doesn't
# mirror).
text_tier <- function(text, family = "", face = 1L) {
  m <- text_metrics(text, family, face)
  if (anyNA(m$width[!is.na(text)])) "hybrid" else "full"
}

# Text in the hybrid tier: grid text grobs in the gtable draw through Rust
# (rs_render_text(), alot-core/src/render/text.rs), as ragg would draw
# them, unless something isn't mirrored, when grid draws them as usual.

# Marks every grid text grob in a gtable (and the gTrees and gtables inside
# it) to draw with drawDetails.alot_text().
hybrid_text <- function(g) {
  cls <- class(g)
  if ("text" %in% cls) {
    if (!"alot_text" %in% cls) class(g) <- c("alot_text", cls)
    return(g)
  }
  # Each list is replaced once ([<- keeps its attributes): assigning
  # element by element copies a gtable's grobs on every step.
  if ("gtable" %in% cls) {
    g$grobs[] <- lapply(g$grobs, hybrid_text)
  } else if ("gTree" %in% cls && length(g$children)) {
    g$children[] <- lapply(g$children, hybrid_text)
  }
  g
}

#' @exportS3Method grid::drawDetails
drawDetails.alot_text <- function(x, recording) {
  img <- text_raster(x)
  if (is.null(img)) {
    return(NextMethod())
  }
  if (is.null(img$raster)) {
    return(invisible())
  }
  res <- raster_device_res()
  dev_h <- grDevices::dev.size("in")[2]
  dims <- dim(img$raster)
  # Pixel-aligned, so the raster maps 1:1. Rust clipped it as ragg clips
  # text; the device's own clipping of rasters is tighter.
  grid::pushViewport(grid::viewport(clip = "off"))
  on.exit(grid::popViewport())
  lo <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  grid::grid.raster(
    img$raster,
    x = grid::unit(img$x0 / res - lo$x, "in"),
    y = grid::unit(dev_h - (img$y0 + dims[1]) / res - lo$y, "in"),
    width = grid::unit(dims[2] / res, "in"),
    height = grid::unit(dims[1] / res, "in"),
    just = c("left", "bottom"),
    interpolate = FALSE
  )
}

# A text grob drawn in Rust as list(x0, y0, raster) (raster NULL if nothing
# shows), or NULL where grid should draw it: not a ragg device, a rotated
# viewport, non-character labels (plotmath), check.overlap, per-label
# graphical parameters, alpha, or text alot doesn't measure as ragg does.
text_raster <- function(x) {
  res <- raster_device_res()
  tr <- grid::current.transform()
  if (is.null(res) || tr[1, 2] != 0 || tr[2, 1] != 0 || !is.character(x$label) || isTRUE(x$check.overlap)) {
    return(NULL)
  }
  gp <- grid::get.gpar(c("fontsize", "cex", "lineheight", "fontfamily", "font", "col", "alpha"))
  if (any(lengths(gp) != 1) || !identical(gp$alpha, 1)) {
    return(NULL)
  }
  if (length(x$label) == 0 || is.na(gp$col)) {
    return(list(x0 = 0L, y0 = 0L, raster = NULL))
  }
  font <- text_fonts(gp$fontfamily, gp$font)
  colour <- point_colours(as.character(gp$col), NA)
  px <- grDevices::dev.size("px")
  clip <- text_clip(px[1], px[2])
  if (is.na(font$path) || is.null(colour) || is.null(clip)) {
    return(NULL)
  }
  # grid recycles labels, positions and justification to the longest
  # (grid's gridText()).
  n <- max(length(x$label), length(x$x), length(x$y))
  loc <- grid::deviceLoc(rep_len(x$x, n), rep_len(x$y, n), valueOnly = TRUE)
  dev_h <- grDevices::dev.size("in")[2]
  hjust <- utils::getFromNamespace("resolveHJust", "grid")(x$just, x$hjust)
  vjust <- utils::getFromNamespace("resolveVJust", "grid")(x$just, x$vjust)
  # ragg's size (fontsize * cex * res / 72) and GEText()'s line height
  # (lineheight * cex * cra[1] * ps / startps, cra[1] = 1.2 * pointsize *
  # res / 72), with res the device's pixels per inch.
  size <- gp$fontsize * gp$cex * res / 72
  line <- gp$lineheight * gp$cex * 1.2 * gp$fontsize * res / 72
  rs_render_text(
    enc2utf8(rep_len(x$label, n)), loc$x * res, (dev_h - loc$y) * res,
    as.double(rep_len(hjust, n)), as.double(rep_len(vjust, n)), as.double(rep_len(x$rot, n)),
    font$path, font$index, size, line, colour, clip
  )
}

# ragg's clip box for the current viewport in device pixels: grid's clip
# rectangle (the pushed viewport's `cliprect`, device units) limited to the
# device by GESetClip() (R src/main/engine.c), then truncated to integers
# and made inclusive by AGG's renderer_base::clip_box() (ragg
# AggDevice::clipRect()). NULL for clip paths, which alot doesn't mirror.
text_clip <- function(w, h) {
  pv <- utils::getFromNamespace("grid.Call", "grid")(utils::getFromNamespace("C_currentViewport", "grid"))
  if (!is.null(pv$clippath)) {
    return(NULL)
  }
  r <- pv$cliprect
  x <- sort(c(max(r[1], 0), min(r[3], w)))
  y <- sort(c(min(r[2], h), max(r[4], 0)))
  as.integer(c(max(trunc(x[1]), 0), max(trunc(y[1]), 0), min(trunc(x[2]), w - 1), min(trunc(y[2]), h - 1)))
}
