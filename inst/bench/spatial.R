# Spatial bench (S0.2, SPATIAL.md "Verification"): time per stage, from a
# ggplot to a PNG file, for high-resolution geom_raster() and geom_sf()
# plots, the north star and its faceted variant. Prints the Markdown tables
# recorded in RESULTS.md ("S0.2: spatial baseline").
#
#   NOT_CRAN=true Rscript -e 'pkgbuild::compile_dll(force = TRUE, debug = FALSE); pkgload::load_all(compile = FALSE, helpers = FALSE); source("inst/bench/spatial.R")'
#
# Paths, each run on its own build of the plot, drawn to a 7 x 7 in PNG at
# 300 dpi (the north star's page):
#   ggplot2  ggplot_build(); then on ragg::agg_png(): ggplot_gtable(), grid
#            drawing, and dev.off(), which writes the PNG (encode).
#   hybrid   alot_build(), then the hybrid tier (run_hybrid()), for cases
#            where it draws a layer in Rust (S1.1: the rasters; S3.2: sf
#            polygons; S3.3: sf lines and points).
#   alot     what alot_png() does: alot_build(), then the tier it picks
#            (run_alot()): the full tier for the rasters since S1.1, the
#            hybrid tier for sf layers since S3.2 / S3.3; the ggplot2 tier,
#            after the full tier's attempt, for the rest.
# The device is opened before the gtable is built, as print.ggplot() does.
#
# Each case also gets, unless ALOT_BENCH_PROFILE=false:
#   - per-step build times (R/timing.R step_times()) with kernels off (each
#     step runs ggplot2's own method) and on: the basis for S1.2 / S2.2;
#   - one Rprof'd rep of the ggplot2 path, per stage: the top functions by
#     self time (generic frames such as lapply() and .Call() are skipped, so
#     a sample counts for the innermost named function), and the time with
#     PROJ on the stack (st_transform(), sf_project(), st_graticule() and
#     the sf C entry points that call PROJ): the floor alot can't cut.
# and the run ends with direct PROJ timings (st_transform() of 1e6 vertices,
# st_graticule() of the north star's panel).
#
# Runs are sequential with the paths interleaved; medians are reported. An
# untimed warm-up plot runs first (first calls, font lookups).
#   ALOT_BENCH_CASES   comma-separated case names (default: all synthetic)
#   ALOT_BENCH_REPS    reps per case (default: per case, 1-3)
#   ALOT_BENCH_PROFILE false skips the step and Rprof passes
#   ALOT_BENCH_OUT     directory for the PNGs (default: tempdir())
#   ALOT_SPATIAL_DATA  directory with real data (opt-in cases, see below)
source("inst/bench/cases.R")
if (!requireNamespace("sf", quietly = TRUE)) stop("The spatial bench needs sf (SPATIAL.md, Decisions).")
if (isFALSE(getOption("alot.full_tier"))) stop("options(alot.full_tier = FALSE) is set; load with pkgload::load_all(helpers = FALSE).")

# ---- Generators ------------------------------------------------------------

# An n x n raster over a 4000 km square of Australia in EPSG:3577 metres, as
# a data frame of cell centres: about half the cells are "land" (an irregular
# disc) and present, the rest absent, as in an SDM output with NA outside
# land. `suitability` is a smooth continuous field plus noise in (0, 1).
# With `species` > 1, one such raster per species (each its own land mask
# and field), stacked with a `species` factor for facet_wrap().
raster_grid <- function(n, species = 1L) {
  cell <- 4e6 / n
  xs <- -2e6 + (seq_len(n) - 0.5) * cell
  ys <- -5e6 + (seq_len(n) - 0.5) * cell
  one <- function(s) {
    g <- expand.grid(x = xs, y = ys, KEEP.OUT.ATTRS = FALSE)
    u <- g$x / 2e6
    v <- (g$y + 3e6) / 2e6
    theta <- atan2(v, u)
    # pi * 0.8^2 ~ 2, half the [-1, 1]^2 square.
    land <- sqrt(u^2 + v^2) < 0.8 * (1 + 0.1 * sin(5 * theta + s) + 0.05 * sin(13 * theta))
    g <- g[land, ]
    u <- u[land]
    v <- v[land]
    g$suitability <- stats::plogis(2 * sin(3 * u + s) * cos(2 * v) + stats::rnorm(nrow(g), sd = 0.3))
    if (species > 1) g$species <- s
    g
  }
  out <- do.call(rbind, lapply(seq_len(species), one))
  if (species > 1) out$species <- factor(paste0("species_", out$species))
  rownames(out) <- NULL
  out
}

# `n` polygon features with about `vertices` vertices in total, laid out on
# a grid over Australia (longitude 113-153, latitude -43 to -11): each one a
# jagged closed ring inside its grid cell, so features don't overlap.
# Generated in EPSG:4326; any other `crs` is reached with st_transform()
# here, outside the timed code. `value` is a continuous attribute for fill.
sf_regions <- function(n, vertices = 1e6, crs = 4326) {
  cols <- ceiling(sqrt(n * 40 / 32))
  rows <- ceiling(n / cols)
  w <- 40 / cols
  h <- 32 / rows
  k <- max(4L, as.integer(round(vertices / n)))
  i <- seq_len(n) - 1
  cx <- 113 + (i %% cols + 0.5) * w
  cy <- -43 + (i %/% cols + 0.5) * h
  r <- 0.45 * min(w, h)
  theta <- seq(0, 2 * pi, length.out = k)[-k]
  geoms <- lapply(seq_len(n), function(j) {
    rad <- r * (1 + 0.15 * sin(7 * theta + j) + 0.05 * stats::runif(k - 1, -1, 1))
    xy <- cbind(cx[j] + rad * cos(theta), cy[j] + rad * sin(theta))
    sf::st_polygon(list(rbind(xy, xy[1, ])))
  })
  out <- sf::st_sf(id = seq_len(n), value = stats::runif(n), geometry = sf::st_sfc(geoms, crs = 4326))
  if (!identical(crs, 4326)) out <- sf::st_transform(out, crs)
  out
}

# ---- Cases -----------------------------------------------------------------

raster_plot <- function(n) {
  function() {
    ggplot(raster_grid(n), aes(x, y, fill = suitability)) +
      geom_raster() +
      scale_fill_viridis_c() +
      coord_fixed()
  }
}

sf_plot <- function(n, crs, outline = FALSE) {
  function() {
    if (outline) {
      # The north star's sf layer alone (S3.2).
      return(ggplot(sf_regions(n, crs = crs)) + geom_sf(fill = NA, colour = "grey20"))
    }
    ggplot(sf_regions(n, crs = crs)) +
      geom_sf(aes(fill = value), colour = "grey20")
  }
}

# The north star (SPATIAL.md): a 2000^2 raster, ~500 features of ~1e6
# vertices, both in EPSG:3577. The faceted variant uses four species, with a
# 1000^2 raster each (2e6 cells drawn, as in the single map), so a run stays
# within minutes; the sf layer is drawn in every panel.
north_star_plot <- function(n = 2000, species = 1L) {
  function() {
    regions <- sf_regions(500, crs = 3577)
    p <- ggplot() +
      geom_raster(aes(x, y, fill = suitability), data = raster_grid(n, species)) +
      geom_sf(data = regions, fill = NA, colour = "grey20") +
      scale_fill_viridis_c() +
      coord_sf(crs = 3577)
    if (species > 1) p <- p + facet_wrap(~species)
    p
  }
}

spatial_cases <- list(
  raster_500 = list(plot = raster_plot(500), reps = 3L),
  raster_1000 = list(plot = raster_plot(1000), reps = 3L),
  raster_2000 = list(plot = raster_plot(2000), reps = 1L),
  sf_1e2_3577 = list(plot = sf_plot(1e2, 3577), reps = 3L),
  sf_1e3_3577 = list(plot = sf_plot(1e3, 3577), reps = 3L),
  sf_1e4_3577 = list(plot = sf_plot(1e4, 3577), reps = 3L),
  sf_1e2_4326 = list(plot = sf_plot(1e2, 4326), reps = 3L),
  sf_1e3_4326 = list(plot = sf_plot(1e3, 4326), reps = 3L),
  sf_1e4_4326 = list(plot = sf_plot(1e4, 4326), reps = 3L),
  sf_1e3_3577_outline = list(plot = sf_plot(1e3, 3577, outline = TRUE), reps = 3L),
  # 1e3 features in EPSG:4326 drawn in EPSG:3577: CoordSf$setup_data
  # reprojects all 1e6 vertices in the build.
  sf_1e3_reproject = list(
    plot = function() {
      ggplot(sf_regions(1e3, crs = 4326)) +
        geom_sf(aes(fill = value), colour = "grey20") +
        coord_sf(crs = 3577)
    },
    reps = 3L
  ),
  # S3.3: the regions' boundaries as 1e3 LINESTRINGs (1e6 vertices), and 1e5
  # POINTs (one per 10 vertices) in two shapes.
  sf_lines_1e3_3577 = list(
    plot = function() {
      lines <- sf::st_cast(sf::st_cast(sf_regions(1e3, crs = 3577), "MULTILINESTRING"), "LINESTRING", warn = FALSE)
      ggplot(lines) + geom_sf(aes(colour = value))
    },
    reps = 3L
  ),
  sf_points_1e5_3577 = list(
    plot = function() {
      pts <- sf::st_cast(sf::st_cast(sf_regions(1e4, vertices = 1e5, crs = 3577), "MULTIPOINT", warn = FALSE), "POINT", warn = FALSE)
      ggplot(pts) + geom_sf(aes(colour = value, shape = value > 0.5)) + scale_shape_manual(values = c(19, 3))
    },
    reps = 3L
  ),
  north_star = list(plot = north_star_plot(2000), reps = 1L),
  north_star_facet = list(plot = north_star_plot(1000, species = 4L), reps = 1L)
)

# ---- Opt-in real data ------------------------------------------------------

# ALOT_SPATIAL_DATA names a directory holding a boundary layer (the first
# .gpkg, .shp or .geojson, read with sf::st_read()) and/or an SDM raster:
# the first .tif read with terra or stars if one is installed, or an .rds
# data frame with columns x, y and a numeric third column. The raster is
# taken to be in the map's CRS (coord_sf() reprojects only sf layers); the
# boundaries are reprojected to it. Never run by tests.
real_cases <- function(dir) {
  if (!nzchar(dir)) {
    return(list())
  }
  if (!dir.exists(dir)) stop("ALOT_SPATIAL_DATA is not a directory: ", dir)
  first <- function(pattern) utils::head(list.files(dir, pattern, full.names = TRUE, ignore.case = TRUE), 1)
  vec <- first("\\.(gpkg|shp|geojson)$")
  ras <- first("\\.(tif|tiff)$")
  rds <- first("\\.rds$")
  read_raster <- function() {
    if (length(ras) && requireNamespace("terra", quietly = TRUE)) {
      r <- terra::rast(ras)[[1]]
      d <- terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)
      return(list(data = stats::setNames(d[1:3], c("x", "y", "suitability")), crs = sf::st_crs(terra::crs(r))))
    }
    if (length(ras) && requireNamespace("stars", quietly = TRUE)) {
      r <- stars::read_stars(ras)
      d <- as.data.frame(r)
      d <- d[!is.na(d[[3]]), ]
      return(list(data = stats::setNames(d[1:3], c("x", "y", "suitability")), crs = sf::st_crs(r)))
    }
    if (length(rds)) {
      d <- readRDS(rds)
      d <- d[!is.na(d[[3]]), ]
      return(list(data = stats::setNames(d[1:3], c("x", "y", "suitability")), crs = sf::st_crs(attr(d, "crs") %||% 3577)))
    }
    NULL
  }
  out <- list()
  if (length(vec)) {
    out$real_sf <- list(
      plot = function() {
        ggplot(sf::st_read(vec, quiet = TRUE)) + geom_sf(fill = NA, colour = "grey20") + coord_sf(crs = 3577)
      },
      reps = 1L
    )
  }
  if (length(ras) || length(rds)) {
    out$real_raster <- list(
      plot = function() {
        r <- read_raster()
        if (is.null(r)) stop("No reader for ", ras, ": install terra or stars, or provide an .rds data frame.")
        ggplot(r$data, aes(x, y, fill = suitability)) + geom_raster() + scale_fill_viridis_c() + coord_fixed()
      },
      reps = 1L
    )
    if (length(vec)) {
      out$real_north_star <- list(
        plot = function() {
          r <- read_raster()
          if (is.null(r)) stop("No reader for ", ras, ": install terra or stars, or provide an .rds data frame.")
          ggplot() +
            geom_raster(aes(x, y, fill = suitability), data = r$data) +
            geom_sf(data = sf::st_read(vec, quiet = TRUE), fill = NA, colour = "grey20") +
            scale_fill_viridis_c() +
            coord_sf(crs = r$crs)
        },
        reps = 1L
      )
    }
  }
  out
}

# ---- Timing ----------------------------------------------------------------

page <- list(width = 7, height = 7, units = "in", res = 300)

secs <- function(expr) {
  t <- proc.time()[["elapsed"]]
  force(expr)
  proc.time()[["elapsed"]] - t
}

# Times (or with `prof`, Rprofs into prof$dir) one stage.
stage <- function(name, expr, prof = NULL) {
  if (!is.null(prof)) utils::Rprof(file.path(prof$dir, paste0(name, ".out")), interval = prof$interval)
  t <- secs(expr)
  if (!is.null(prof)) utils::Rprof(NULL)
  t
}

run_ggplot2 <- function(p, file, prof = NULL, keep = NULL) {
  t_build <- stage("build", b <- quiet(ggplot_build(p)), prof)
  do.call(ragg::agg_png, c(list(file), page))
  t_gtable <- stage("gtable", g <- quiet(ggplot_gtable(b)), prof)
  t_draw <- stage("draw", {
    grid::grid.newpage()
    grid::grid.draw(g)
  }, prof)
  t_encode <- stage("encode", grDevices::dev.off(), prof)
  if (!is.null(keep)) keep$built <- b
  c(build = t_build, decide = 0, gtable = t_gtable, draw = t_draw, encode = t_encode)
}

# The tier alot_png() picks for a built plot (untimed).
alot_tier <- function(b) quiet(alot_ns$alot_render_coverage(b))$tier

# What alot_png() does, per stage, in the tier it picks. Full tier (S1.1):
# "decide" is the render IR and page spec (render_ir() and page_spec(),
# what render_full() builds before Rust draws; the tier choice is part of
# it), "draw" rs_render_page() (layout, display list and band rasterising
# to a nativeRaster) and "encode" write_png(). render_full() with a file
# streams the bands to the PNG instead, with the same work. Hybrid tier:
# run_hybrid(). ggplot2 tier: the full tier's attempt and render_coverage()
# ("decide"), then ggplot2's render on ragg as run_ggplot2().
run_alot <- function(p, file, keep = NULL) {
  t_build <- secs(b <- quiet(alot_build(p)))
  if (!is.null(keep)) keep$built <- b
  size <- c(page, list(bg = alot_ns$plot_background(b)))
  tier <- alot_tier(b)
  if (tier == "full") {
    t_decide <- secs(spec <- quiet(alot_ns$page_spec(b, alot_ns$render_ir(b), size)))
    t_draw <- secs(img <- alot_ns$rs_render_page(spec, alot_ns$render_threads()))
    if (is.null(img)) stop("the full tier declined the page spec")
    t_encode <- secs(alot_ns$write_png(img, file, size$bg, page$res))
    return(c(build = t_build, decide = t_decide, gtable = 0, draw = t_draw, encode = t_encode))
  }
  if (tier == "hybrid") {
    return(c(build = t_build, run_hybrid_render(b, file)))
  }
  t_decide <- secs(out <- quiet(alot_ns$render_raster(b, size, file)))
  if (out$tier != "ggplot2") stop("alot's tier for this case is ", out$tier, " but alot_render_coverage() says ggplot2")
  do.call(ragg::agg_png, c(list(file), page))
  t_gtable <- secs(g <- quiet(ggplot_gtable(b)))
  t_draw <- secs({
    grid::grid.newpage()
    grid::grid.draw(g)
  })
  t_encode <- secs(grDevices::dev.off())
  c(build = t_build, decide = t_decide, gtable = t_gtable, draw = t_draw, encode = t_encode)
}

# The hybrid tier (options(alot.full_tier = FALSE)), as render_hybrid()
# draws it: hybrid_gtable() on ragg::agg_capture() ("gtable"; layers with a
# Rust drawer become lazy grobs), grid drawing, where those grobs render in
# Rust ("draw"), then capturing the page and write_png() ("encode").
run_hybrid_render <- function(b, file) {
  size <- c(page, list(bg = alot_ns$plot_background(b)))
  old <- grDevices::dev.cur()
  cap <- do.call(ragg::agg_capture, page)
  dev <- grDevices::dev.cur()
  on.exit(alot_ns$close_device(dev, old))
  t_gtable <- secs(g <- quiet(alot_ns$hybrid_gtable(b)))
  t_draw <- secs({
    grid::grid.newpage()
    grid::grid.draw(g)
  })
  t_encode <- secs(alot_ns$write_png(cap(native = TRUE), file, size$bg, page$res))
  c(decide = 0, gtable = t_gtable, draw = t_draw, encode = t_encode)
}

run_hybrid <- function(p, file) {
  withr::local_options(alot.full_tier = FALSE)
  t_build <- secs(b <- quiet(alot_build(p)))
  if (alot_tier(b) != "hybrid") stop("the hybrid tier doesn't draw this case")
  c(build = t_build, run_hybrid_render(b, file))
}

# ---- Profile summaries -----------------------------------------------------

# Frames that say nothing about where time goes; a sample counts for the
# innermost frame not in this list.
generic_frames <- c(
  ".Call", ".External", ".External2", ".Internal", "FUN", "lapply", "vapply", "sapply",
  "mapply", "Map", "do.call", "eval", "force", "<Anonymous>", "withCallingHandlers",
  "tryCatch", "tryCatchList", "tryCatchOne", "doTryCatch", "suppressWarnings",
  "suppressMessages", "unlist", "%||%", "Reduce", "standardGeneric", "NextMethod", "UseMethod"
)
# Frames whose time is PROJ's (and sf's projection glue around it).
proj_frames <- c(
  "st_transform", "st_transform.sfc", "st_transform.sf", "st_transform.sfg", "CPL_transform",
  "sf_project", "CPL_proj_direct", "st_graticule"
)

read_rprof <- function(file) {
  lines <- readLines(file)
  interval <- as.numeric(sub(".*sample.interval=([0-9]+).*", "\\1", lines[1])) / 1e6
  stacks <- lapply(lines[-1], function(l) scan(text = l, what = "", quiet = TRUE))
  list(interval = interval, stacks = stacks)
}

# Top `n` functions by self time (ms) and the PROJ time, for one stage.
profile_stage <- function(file, n = 5) {
  pr <- read_rprof(file)
  if (!length(pr$stacks)) {
    return(list(top = character(), proj = 0, total = 0))
  }
  leaf <- vapply(pr$stacks, function(s) {
    s <- s[!s %in% generic_frames]
    if (length(s)) s[1] else "(native)"
  }, "")
  proj <- vapply(pr$stacks, function(s) any(s %in% proj_frames), logical(1))
  tab <- sort(table(leaf), decreasing = TRUE)
  ms <- 1000 * pr$interval
  top <- utils::head(tab, n)
  list(
    top = sprintf("`%s` %s", names(top), formatC(as.numeric(top) * ms, format = "f", digits = 0)),
    proj = sum(proj) * ms,
    total = length(leaf) * ms
  )
}

median_steps <- function(p, kernels) {
  gc(FALSE)
  quiet(alot_ns$step_times(p, kernels = kernels))
}

# ---- Run -------------------------------------------------------------------

cases <- select_cases(c(spatial_cases, real_cases(Sys.getenv("ALOT_SPATIAL_DATA"))))
if (!nzchar(Sys.getenv("ALOT_SPATIAL_DATA"))) progress("ALOT_SPATIAL_DATA is unset: skipping the real-data cases.")
out_dir <- Sys.getenv("ALOT_BENCH_OUT", tempdir())
profile <- !identical(Sys.getenv("ALOT_BENCH_PROFILE"), "false")

cat("## Spatial bench\n\n")
cat(sprintf(
  "%s; %s; ggplot2 %s; ragg %s; sf %s (GEOS %s, GDAL %s, PROJ %s); alot %s; %d threads available. 7 x 7 in at 300 dpi. Medians of interleaved runs, ms.\n\n",
  R.version.string, utils::sessionInfo()$running, utils::packageVersion("ggplot2"),
  utils::packageVersion("ragg"), utils::packageVersion("sf"), sf::sf_extSoftVersion()[["GEOS"]],
  sf::sf_extSoftVersion()[["GDAL"]], sf::sf_extSoftVersion()[["PROJ"]],
  utils::packageVersion("alot"), parallel::detectCores()
))

progress("warm-up")
set.seed(1)
local({
  file <- tempfile(fileext = ".png")
  p <- ggplot(raster_grid(50), aes(x, y, fill = suitability)) + geom_raster() +
    geom_sf(data = sf_regions(10, 1e3, 3577), fill = NA, inherit.aes = FALSE) + coord_sf(crs = 3577)
  run_ggplot2(p, file)
  run_alot(p, file)
  p <- ggplot(raster_grid(50), aes(x, y, fill = suitability)) + geom_raster() + coord_fixed()
  run_hybrid(p, file)
  run_alot(p, file)
})

stages <- c("build", "decide", "gtable", "draw", "encode")
summary <- list()
proj_rows <- list()
for (name in names(cases)) {
  case <- cases[[name]]
  reps <- as.integer(Sys.getenv("ALOT_BENCH_REPS", case$reps %||% 3L))
  progress(name, ": generating")
  set.seed(42)
  p <- case$plot()
  # The hybrid path runs where the hybrid tier draws a layer in Rust.
  set.seed(1)
  hybrid <- withr::with_options(list(alot.full_tier = FALSE), alot_tier(quiet(alot_build(p))) == "hybrid")
  paths <- c("ggplot2", if (hybrid) "hybrid", "alot")
  times <- list()
  for (i in seq_len(reps)) {
    for (path in paths) {
      progress(name, " rep ", i, ": ", path)
      file <- file.path(out_dir, paste0("spatial-", name, "-", path, ".png"))
      gc(FALSE)
      t <- switch(path, ggplot2 = run_ggplot2(p, file), hybrid = run_hybrid(p, file), alot = run_alot(p, file))
      times[[path]] <- rbind(times[[path]], t)
    }
  }
  med <- lapply(times, function(t) {
    t <- cbind(t, render = t[, "decide"] + t[, "gtable"] + t[, "draw"] + t[, "encode"])
    t <- cbind(t, total = t[, "build"] + t[, "render"])
    1000 * apply(t, 2, stats::median)
  })
  set.seed(1)
  tier <- alot_tier(quiet(alot_build(p)))
  cat(sprintf("### %s (%d rep%s; alot's tier: %s)\n\n", name, reps, if (reps > 1) "s" else "", tier))
  hyb <- med$hybrid %||% stats::setNames(rep(NA_real_, length(med$ggplot2)), names(med$ggplot2))
  md_table(data.frame(
    stage = names(med$ggplot2), ggplot2 = unname(med$ggplot2), hybrid = unname(hyb), alot = unname(med$alot),
    speedup = ifelse(med$alot > 0, paste0(formatC(med$ggplot2 / pmax(med$alot, 1e-3), format = "f", digits = 2), "x"), "-")
  ))
  summary[[name]] <- data.frame(
    case = name, tier = tier,
    ggplot2_build = med$ggplot2[["build"]], ggplot2_render = med$ggplot2[["render"]],
    ggplot2_total = med$ggplot2[["total"]],
    hybrid_render = hyb[["render"]], hybrid_total = hyb[["total"]],
    alot_build = med$alot[["build"]], alot_render = med$alot[["render"]], alot_total = med$alot[["total"]],
    speedup = paste0(formatC(med$ggplot2[["total"]] / med$alot[["total"]], format = "f", digits = 2), "x")
  )

  if (!profile) next

  # Build steps, kernels off (ggplot2's methods) and on; steps under 3% of
  # the kernels-off total are folded into "other".
  progress(name, ": build steps")
  off <- median_steps(p, FALSE)
  on <- median_steps(p, TRUE)
  tab <- merge(off, on, by = "step", all = TRUE, sort = FALSE, suffixes = c("_off", "_on"))
  tab[is.na(tab)] <- 0
  tab <- tab[match(off$step, tab$step), ]
  total_off <- sum(tab$seconds_off)
  major <- tab$seconds_off >= 0.03 * total_off
  rows <- rbind(
    tab[major, ],
    data.frame(step = "other", seconds_off = sum(tab$seconds_off[!major]), seconds_on = sum(tab$seconds_on[!major])),
    data.frame(step = "**total**", seconds_off = total_off, seconds_on = sum(tab$seconds_on))
  )
  cat("Build steps (kernels off = ggplot2's methods):\n\n")
  md_table(data.frame(
    step = rows$step,
    ggplot2_ms = 1000 * rows$seconds_off,
    share = sprintf("%.0f%%", 100 * rows$seconds_off / total_off),
    alot_ms = 1000 * rows$seconds_on,
    speedup = paste0(formatC(rows$seconds_off / pmax(rows$seconds_on, 1e-6), format = "f", digits = 2), "x")
  ))

  # One Rprof'd rep of the ggplot2 path; checks alot's build against it.
  progress(name, ": profile")
  prof <- list(dir = tempfile("rprof-"), interval = 0.01)
  dir.create(prof$dir)
  keep <- new.env()
  gc(FALSE)
  set.seed(1)
  run_ggplot2(p, file.path(out_dir, paste0("spatial-", name, "-prof.png")), prof, keep)
  set.seed(1)
  a <- quiet(alot_build(p))
  if (!isTRUE(all.equal(a@data, keep$built@data, tolerance = 1e-8))) stop(name, ": alot and ggplot2 builds differ")
  rm(a, keep)
  pst <- lapply(c("build", "gtable", "draw", "encode"), function(s) profile_stage(file.path(prof$dir, paste0(s, ".out"))))
  names(pst) <- c("build", "gtable", "draw", "encode")
  unlink(prof$dir, recursive = TRUE)
  cat("Profile of the ggplot2 path (one Rprof'd rep, 10 ms samples; top functions by self time, ms):\n\n")
  md_table(data.frame(
    stage = names(pst),
    sampled_ms = vapply(pst, `[[`, 0, "total"),
    proj_ms = vapply(pst, `[[`, 0, "proj"),
    top = vapply(pst, function(s) paste(s$top, collapse = ", "), "")
  ))
  proj_ms <- sum(vapply(pst, `[[`, 0, "proj"))
  sampled <- sum(vapply(pst, `[[`, 0, "total"))
  proj_rows[[name]] <- data.frame(
    case = name, ggplot2_total = med$ggplot2[["total"]],
    proj_build = pst$build$proj, proj_render = pst$gtable$proj + pst$draw$proj + pst$encode$proj,
    proj_share = sprintf("%.1f%%", 100 * proj_ms / max(sampled, 1)),
    max_speedup = if (proj_ms > 0) sprintf("%.0fx", sampled / proj_ms) else "-"
  )
}

cat("### Summary (ms)\n\n")
md_table(do.call(rbind, summary))

if (profile && length(proj_rows)) {
  cat("### PROJ floor in context (ms, from the profile)\n\n")
  cat("`max_speedup` is the end-to-end speedup if everything but PROJ took no time.\n\n")
  md_table(do.call(rbind, proj_rows))
}

# Direct PROJ timings: the projection work alot leaves to sf.
progress("PROJ floor")
set.seed(42)
r4326 <- sf_regions(500, crs = 4326)
r3577 <- sf::st_transform(r4326, 3577)
g4326 <- sf::st_geometry(r4326)
g3577 <- sf::st_geometry(r3577)
bb <- sf::st_bbox(c(xmin = -2e6, ymin = -5e6, xmax = 2e6, ymax = -1e6), crs = sf::st_crs(3577))
proj_ops <- list(
  `st_transform(), 1e6 vertices, 4326 -> 3577` = function() sf::st_transform(g4326, 3577),
  `st_transform(), 1e6 vertices, 3577 -> 3577 (no-op)` = function() sf::st_transform(g3577, 3577),
  `st_graticule() of the north star's panel` = function() sf::st_graticule(bb, crs = sf::st_crs(3577), datum = sf::st_crs(4326))
)
cat("### PROJ floor, direct (median of 3, ms)\n\n")
md_table(data.frame(
  operation = names(proj_ops),
  ms = vapply(proj_ops, function(f) time_ms(f, 3L), double(1)),
  row.names = NULL
))
