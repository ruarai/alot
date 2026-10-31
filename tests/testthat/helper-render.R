# Fidelity and layout harness for rendering (PHASE2.md, Verification).
#
# expect_render_close() draws a plot live with ggplot2 on ragg and with
# alot, and compares pixels; no reference images are stored. layout_boxes()
# records where grid puts each named grob of a gtable, in device pixels, for
# comparison with the Rust layout's debug export via expect_layout_close().

# Page size for render checks: small, so live references stay fast.
render_size <- list(width = 400, height = 300, units = "px", res = 96)

# Channels of a nativeRaster (R | G << 8 | B << 16 | A << 24) as a 4 x n
# integer matrix, pixels in row-major order from the top-left.
raster_channels <- function(raster) {
  v <- as.integer(raster)
  rbind(
    bitwAnd(v, 255L), bitwAnd(bitwShiftR(v, 8L), 255L),
    bitwAnd(bitwShiftR(v, 16L), 255L), bitwShiftR(v, 24L)
  )
}

# ggplot2's own drawing of a built plot on ragg::agg_capture(). As in
# print.ggplot(), the gtable is built with the device open, since
# ggplot_gtable() measures text on the current device.
render_reference <- function(built, size = render_size) {
  cap <- do.call(ragg::agg_capture, size)
  on.exit(grDevices::dev.off())
  gtable <- ggplot2::ggplot_gtable(built)
  grid::grid.newpage()
  grid::grid.draw(gtable)
  cap(native = TRUE)
}

# Per-pixel largest channel difference between two nativeRasters.
render_px_diff <- function(a, b) {
  apply(abs(raster_channels(a) - raster_channels(b)), 2, max)
}

# Compares alot's drawing of `p` (a ggplot or a built plot) in `tier` with
# ggplot2 + ragg at the same size. Passes if no channel differs by more than
# `max` (of 255) and at most `share` of pixels differ by more than 8. Fails
# if alot raised a fallback warning or used another tier. On failure writes
# reference, result and diff PNGs to a temporary directory (under
# ALOT_RENDER_DIFF_DIR if set). `label` names
# the plot in failure messages. `reference`, a nativeRaster, replaces the live
# reference (see render_cached_reference()).
expect_render_close <- function(p, ..., max = 32, share = 0.01, tier = "full", label = NULL, reference = NULL) {
  size <- utils::modifyList(render_size, list(...))
  if (ggplot2::is_ggplot(p)) {
    set.seed(1)
    p <- ggplot2::ggplot_build(p)
  }
  ref <- reference %||% render_reference(p, size)
  fallback <- NULL
  out <- withCallingHandlers(
    render_raster(p, size),
    alot_render_fallback = function(w) {
      fallback <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  if (!is.null(fallback)) {
    return(testthat::fail(paste0(label, if (!is.null(label)) ": ", "alot raised a fallback warning:\n", fallback)))
  }
  if (!identical(out$tier, tier)) {
    return(testthat::fail(paste0(label, if (!is.null(label)) ": ", sprintf("alot used the %s tier, not %s.", out$tier, tier))))
  }
  if (!identical(dim(out$raster), dim(ref))) {
    return(testthat::fail(sprintf(
      "alot's page is %s px, ggplot2's %s px.",
      paste(rev(dim(out$raster)), collapse = " x "), paste(rev(dim(ref)), collapse = " x ")
    )))
  }
  px <- render_px_diff(out$raster, ref)
  ok <- max(px) <= max && mean(px > 8) <= share
  if (!ok) {
    # ggplot2 + ragg's own layout occasionally comes out differently on a
    # fresh device in a session that alternates resolutions (seen as a
    # whole-plot shift in the reference only; alot's result and an isolated
    # reference agree). Compare once more against a second reference; alot's
    # result is not redrawn, so a wrong result still fails.
    ref2 <- render_reference(p, size)
    px2 <- render_px_diff(out$raster, ref2)
    if (sum(px2 > 8) < sum(px > 8)) {
      ref <- ref2
      px <- px2
      ok <- max(px) <= max && mean(px > 8) <= share
    }
  }
  msg <- ""
  if (!ok) {
    # ALOT_RENDER_DIFF_DIR keeps the images after the R session ends.
    dir <- tempfile("alot-render-", tmpdir = Sys.getenv("ALOT_RENDER_DIFF_DIR", tempdir()))
    dir.create(dir, recursive = TRUE)
    diff <- ref
    diff[] <- bitwOr(as.integer(pmin(px * 4L, 255L)) * 65793L, -16777216L)
    write_png(ref, file.path(dir, "reference.png"))
    write_png(out$raster, file.path(dir, "result.png"))
    write_png(diff, file.path(dir, "diff.png"))
    msg <- sprintf(
      "Render differs from ggplot2 + ragg: max %d (allowed %d), %.4f%% of pixels by > 8 (allowed %.4f%%).\nImages: %s",
      max(px), max, 100 * mean(px > 8), 100 * share, dir
    )
  }
  testthat::expect(ok, paste0(label, if (!is.null(label)) ": ", msg))
  invisible(c(max = max(px), share = mean(px > 8)))
}

# Boxes of every named grob in the gtable of `built` (a built plot), laid
# out by ggplot_gtable() on a ragg page of `size`, in device pixels from the
# top-left: a data frame of `name` (the gtable layout names
# of the grob and its enclosing gtables, joined by "/"), `x0`, `y0`, `x1`
# and `y1`. Nested gtables are walked. Mirrors how gtable places children
# (gtable's makeContext.gtable and gtable_layout: a grid.layout of the
# table's widths and heights, each child in a viewport spanning its cells).
layout_boxes <- function(built, size = render_size) {
  do.call(ragg::agg_capture, size)
  on.exit(grDevices::dev.off())
  gtable_boxes(ggplot2::ggplot_gtable(built))
}

# The boxes of `gtable` on the open device (see layout_boxes()).
gtable_boxes <- function(gtable) {
  grid::grid.newpage()
  res <- grDevices::dev.size("px")[1] / grDevices::dev.size("in")[1]
  dev_h <- grDevices::dev.size("in")[2]
  box <- function(name) {
    lo <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
    hi <- grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
    data.frame(
      name = name, x0 = lo$x * res, y0 = (dev_h - hi$y) * res,
      x1 = hi$x * res, y1 = (dev_h - lo$y) * res
    )
  }
  walk <- function(g, prefix) {
    if (!is.null(g$vp)) {
      grid::pushViewport(g$vp)
      on.exit(grid::upViewport(), add = TRUE)
    }
    grid::pushViewport(grid::viewport(layout = grid::grid.layout(
      nrow(g), ncol(g),
      widths = g$widths, heights = g$heights, respect = g$respect
    )))
    on.exit(grid::popViewport(), add = TRUE)
    out <- list()
    for (i in seq_len(nrow(g$layout))) {
      l <- g$layout[i, ]
      grid::pushViewport(grid::viewport(
        layout.pos.row = l$t:l$b, layout.pos.col = l$l:l$r
      ))
      name <- paste0(prefix, l$name)
      out[[length(out) + 1]] <- box(name)
      child <- g$grobs[[i]]
      if (inherits(child, "gtable")) {
        out[[length(out) + 1]] <- walk(child, paste0(name, "/"))
      }
      grid::popViewport()
    }
    do.call(rbind, out)
  }
  out <- walk(gtable, "")
  rownames(out) <- NULL
  out
}

# Compares two layout exports (see layout_boxes()) by name: every box in
# `expected` must be in `object` with each edge within `tol` pixels. Repeated
# names match in order.
expect_layout_close <- function(object, expected, tol = 0.5) {
  # Names repeat (the table's spacers): the nth "spacer" matches the nth.
  object$name <- make.unique(object$name)
  expected$name <- make.unique(expected$name)
  m <- match(expected$name, object$name)
  missing <- expected$name[is.na(m)]
  if (length(missing)) {
    return(testthat::fail(paste("Missing boxes:", paste(missing, collapse = ", "))))
  }
  edges <- c("x0", "y0", "x1", "y1")
  d <- abs(as.matrix(object[m, edges]) - as.matrix(expected[edges]))
  bad <- which(apply(d, 1, max) > tol)
  testthat::expect(
    length(bad) == 0,
    sprintf(
      "Boxes off by more than %g px: %s",
      tol, paste(sprintf("%s (%.2f px)", expected$name[bad], apply(d[bad, , drop = FALSE], 1, max)), collapse = ", ")
    )
  )
}

# The sizes in pixels of the legend boxes in ggplot2's gtable for `built`,
# as list(position = c(width, height)) for the positions that have one, and
# the boxes of the top-level table, from one gtable. The Rust layout takes
# the legends' sizes until their layout is mirrored.
grid_layout <- function(built, size = render_size) {
  do.call(ragg::agg_capture, size)
  on.exit(grDevices::dev.off())
  gtable <- ggplot2::ggplot_gtable(built)
  res <- size$res
  legends <- list()
  for (pos in c("right", "left", "bottom", "top")) {
    i <- match(paste0("guide-box-", pos), gtable$layout$name)
    g <- gtable$grobs[[i]]
    if (!inherits(g, "zeroGrob")) {
      legends[[pos]] <- c(
        grid::convertWidth(gtable::gtable_width(g), "in", valueOnly = TRUE),
        grid::convertHeight(gtable::gtable_height(g), "in", valueOnly = TRUE)
      ) * res
    }
  }
  boxes <- gtable_boxes(gtable)
  list(legends = legends, boxes = boxes[!grepl("/", boxes$name, fixed = TRUE), ])
}

# Whether alot's layout of `built` (a built plot) matches grid's within
# `tol` pixels, or why alot declines it: returns NULL when it matches,
# otherwise the reason (a string); fails the expectation on a mismatch.
expect_layout_matches <- function(built, size = render_size, tol = 0.5, label = NULL) {
  ir <- render_ir(built)
  info <- grid_layout(built, size)
  mine <- layout_boxes_rust(built, size$width, size$height, size$res, ir, info$legends)
  if (length(mine) == 0) {
    return(attr(mine, "reason"))
  }
  expected <- info$boxes
  # The Rust table has the cells of the gtable, in the same order.
  testthat::expect(
    identical(make.unique(mine$name), make.unique(expected$name)),
    paste0(label, if (!is.null(label)) ": ", "alot's cells are ", paste(mine$name, collapse = ", "))
  )
  expect_layout_close(mine, expected, tol)
  NULL
}

# A reference raster cached on disk under the directory in the environment
# variable ALOT_RENDER_CACHE (off if unset): `key` names the plot (a string
# that changes whenever the plot, the page, or anything the reference
# depends on does), `build` makes the reference. The cache is local; nothing
# in it is committed.
render_cached_reference <- function(key, build) {
  dir <- Sys.getenv("ALOT_RENDER_CACHE")
  if (!nzchar(dir)) {
    return(build())
  }
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, paste0(rlang::hash(key), ".rds"))
  hit <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.null(hit)) {
    return(hit)
  }
  ref <- build()
  tryCatch(saveRDS(ref, path), error = function(e) NULL)
  ref
}

# What a cached reference depends on besides the plot: the page, R and the
# packages that draw it, and the fonts it resolves.
render_cache_context <- function(size = render_size) {
  fonts <- systemfonts::match_fonts(c("", "sans", "serif", "mono"))
  list(
    size, R.version.string,
    as.character(utils::packageVersion("ggplot2")), as.character(utils::packageVersion("ragg")),
    as.character(utils::packageVersion("systemfonts")), as.character(utils::packageVersion("textshaping")),
    fonts$path, unname(tools::md5sum(unique(fonts$path)))
  )
}

# alot_png() tries the full tier first. The hybrid tier's tests (and the
# rest of the suite) keep it off; test files for the full tier turn it on
# with withr::local_options(alot.full_tier = TRUE).
options(alot.full_tier = FALSE)
