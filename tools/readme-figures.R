# Figures for README.md: coverage over the corpora, and benchmark results.
#
#   Rscript tools/readme-figures.R            # draw from tools/readme-data/
#   Rscript tools/readme-figures.R --collect  # recompute the coverage CSVs first
#   Rscript tools/readme-figures.R --collect --collect-only  # CSVs, no figures
#
# Run from the repo root. The coverage CSVs come from running every plot in
# tests/testthat/corpus/ (as test-corpus.R does) through alot_build() and,
# for the plots listed in tests/testthat/render-corpus.tsv, through
# alot_render_coverage() (as test-render-corpus.R does). Collection runs the
# corpus files in parallel (up to 8 processes) and takes a few minutes.
#
# The benchmark CSVs (bench-*.csv) are copied by hand from the Markdown
# output of the scripts in inst/bench/ (render-e2e.R, render-suite.R,
# row-scaling.R, facet-scaling.R, step-profile.R); see inst/bench/RESULTS.md,
# "Full benchmark run (2026-10-31)".
#
# The package is loaded with helpers = FALSE: the test helpers set
# options(alot.full_tier = FALSE), which would hide the full render tier.
# The figures themselves are drawn with alot_png().

suppressMessages(pkgload::load_all(compile = FALSE, helpers = FALSE, quiet = TRUE))
library(ggplot2)
Sys.setenv(NOT_CRAN = "true") # as the corpus tests run; skip_on_cran() would skip blocks

data_dir <- "tools/readme-data"
fig_dir <- "man/figures"
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# Collection ----------------------------------------------------------------

corpus_dir <- "tests/testthat/corpus"

# Run one corpus file's blocks as run_corpus_block() in test-corpus.R does,
# recording each plot's build trace (alot_coverage()) and, for render
# corpus plots, alot_render_coverage(). Plots that fail to build are skipped
# (alot fails exactly where ggplot2 does).
collect_file <- function(file, render_ids) {
  build <- list()
  render <- list()
  layers <- list()
  record <- function(id, p) {
    if (!ggplot2::is_ggplot(p)) return()
    trace_env$records <- list()
    set.seed(1)
    b <- tryCatch(suppressWarnings(suppressMessages(alot_build(p))), error = function(e) NULL)
    recs <- trace_env$records
    trace_env$records <- NULL
    if (is.null(b)) return()
    steps <- if (length(recs)) {
      data.frame(
        step = vapply(recs, `[[`, "", "step"),
        class = vapply(recs, `[[`, "", "class"),
        path = vapply(recs, `[[`, "", "path")
      )
    } else {
      data.frame(step = "none", class = "", path = "")
    }
    build[[length(build) + 1L]] <<- cbind(file = file, id = id, steps)
    if (id %in% render_ids) {
      cov <- tryCatch(suppressWarnings(suppressMessages(alot_render_coverage(b))), error = function(e) NULL)
      if (is.null(cov)) return()
      reason <- if (nrow(cov$full)) paste(unique(paste0(cov$full$component, ": ", cov$full$reason)), collapse = " | ") else ""
      render[[length(render) + 1L]] <<- data.frame(file = file, id = id, tier = cov$tier, reason = reason)
      if (nrow(cov$layers)) {
        geom_reason <- cov$full$reason[match(cov$layers$geom, cov$full$name)]
        layers[[length(layers) + 1L]] <<- data.frame(
          file = file, id = id, tier = cov$tier, geom = cov$layers$geom,
          hybrid = cov$layers$engine, full_reason = ifelse(is.na(geom_reason), "", geom_reason)
        )
      }
    }
  }
  for (block in parse(file.path(corpus_dir, file), keep.source = FALSE, encoding = "UTF-8")) {
    env <- new.env(parent = asNamespace("ggplot2"))
    sys.source(file.path(corpus_dir, "_helpers.R"), envir = env)
    env$.plot <- function(id, expr) {
      p <- expr
      record(id, p)
      invisible(p)
    }
    runner <- rlang::new_function(list(), block[[3]], env)
    old_opts <- options()
    old_theme <- ggplot2::theme_get()
    set.seed(1)
    tryCatch(suppressWarnings(suppressMessages(runner())), skip = function(e) NULL, error = function(e) NULL)
    options(old_opts)
    ggplot2::theme_set(old_theme)
  }
  list(build = do.call(rbind, build), render = do.call(rbind, render), layers = do.call(rbind, layers))
}

# Components with nothing to compute, which alot leaves to ggplot2:
# facet_null(), stat_identity(), position_identity(), and discrete scales'
# transform (ggplot2's ScaleDiscrete$transform returns x unchanged).
is_noop <- function(step, class) {
  (step %in% c("facet_compute_layout", "facet_map_data") & class == "FacetNull") |
    (step == "stat" & class == "StatIdentity") |
    (step == "position" & class == "PositionIdentity") |
    (step == "scale_transform" & class %in% c("ScaleDiscrete", "ScaleDiscretePosition"))
}

collect <- function() {
  render_ids <- utils::read.delim("tests/testthat/render-corpus.tsv", skip = 2, comment.char = "", quote = "")$id
  files <- list.files(corpus_dir, "\\.R$")
  files <- files[!startsWith(files, "_")]
  # Big files first, so the parallel run ends evenly.
  files <- files[order(-file.size(file.path(corpus_dir, files)))]
  res <- parallel::mclapply(files, collect_file, render_ids = render_ids,
    mc.cores = min(8L, parallel::detectCores()), mc.preschedule = FALSE)
  bad <- vapply(res, inherits, NA, "try-error")
  if (any(bad)) stop("collection failed for: ", paste(files[bad], collapse = ", "))
  build <- do.call(rbind, lapply(res, `[[`, "build"))
  # Per plot: did every facet, scale and coord component with work run in
  # Rust? (Stats and positions have no kernels yet.)
  build$fallback <- build$path == "ggplot2" & !is_noop(build$step, build$class) & !build$step %in% c("stat", "position", "none")
  plots <- stats::aggregate(list(fallback = build$fallback), build[c("file", "id")], any)
  plots <- data.frame(file = plots$file, id = plots$id, all_rust = !plots$fallback)
  plots <- plots[order(plots$file, plots$id), ]
  utils::write.csv(plots, file.path(data_dir, "coverage-build-plots.csv"), row.names = FALSE)
  # Calls per step, class and path over the whole corpus.
  build <- stats::aggregate(list(n = rep(1L, nrow(build))), build[c("step", "class", "path")], length)
  build <- build[order(build$step, build$class, build$path), ]
  utils::write.csv(build, file.path(data_dir, "coverage-build.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, lapply(res, `[[`, "render")), file.path(data_dir, "coverage-render.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, lapply(res, `[[`, "layers")), file.path(data_dir, "coverage-render-layers.csv"), row.names = FALSE)
}

if ("--collect" %in% commandArgs(TRUE) || !file.exists(file.path(data_dir, "coverage-build.csv"))) {
  collect()
}

if ("--collect-only" %in% commandArgs(TRUE)) quit(save = "no")

# Theme and helpers -----------------------------------------------------------

col_alot <- "#2a78d6"
col_hybrid <- "#86b6ef"
col_gg <- "#a3a29c"
col_text <- "#0b0b0b"
col_text2 <- "#52514e"
col_grid <- "#e6e5e0"
col_track <- "#eeede9"

theme_readme <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background = element_rect(fill = "white", colour = NA),
      text = element_text(colour = col_text),
      plot.title = element_text(face = "bold", size = rel(1.2), margin = margin(b = 4)),
      plot.title.position = "plot",
      plot.subtitle = element_text(colour = col_text2, margin = margin(b = 12), lineheight = 1.1),
      plot.caption = element_text(colour = col_text2, size = rel(0.75), hjust = 0, margin = margin(t = 10)),
      plot.caption.position = "plot",
      axis.text = element_text(colour = col_text2),
      axis.title = element_text(colour = col_text2, size = rel(0.85)),
      panel.grid.major = element_line(colour = col_grid, linewidth = 0.4),
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", hjust = 0, colour = col_text),
      legend.position = "none",
      plot.margin = margin(14, 18, 10, 14)
    )
}

# Figures are drawn by alot itself, at README width.
save_figure <- function(p, name, width = 1600, height = 1000) {
  file <- file.path(fig_dir, name)
  alot_png(p, file, width = width, height = height, units = "px", dpi = 150)
  message("wrote ", file, " (", alot_render_coverage(p)$tier, " tier)")
}

fmt_ms <- function(ms) {
  ifelse(ms >= 1000, sprintf("%.1f s", ms / 1000), sprintf("%.0f ms", ms))
}
fmt_x <- function(x) ifelse(x >= 10, sprintf("%.0f×", x), sprintf("%.1f×", x))
pct <- function(x) sprintf("%.0f%%", 100 * x)

# Figure 1: ggplot to PNG, end to end -----------------------------------------

e2e <- utils::read.csv(file.path(data_dir, "bench-render-e2e.csv"))
case_labels <- c(
  readme = "README plot: 1M points, 6 panels",
  readme_page = "README plot at 7 × 7 in, 300 dpi",
  readme_10 = "README plot with 10 points",
  point_1e6 = "1M points",
  size_1e4 = "10k points sized by value",
  tile_1000 = "1M tiles",
  line_1e6 = "Line through 1M points",
  facets_400 = "400 facet panels",
  grid_free_1e6 = "facet_grid(), free scales, 1M points",
  legends_inside_1e6 = "Binned legends inside, 1M points",
  area_1e6 = "Stacked areas, 1M rows*",
  errorbar_1e5 = "100k error bars",
  boxplot_1e6 = "Notched boxplots of 1M rows",
  segment_1e5 = "100k segments",
  label_2e3 = "2,000 labels",
  polygon_1e4 = "10k polygons",
  flip_1e5 = "coord_flip(), 100k points",
  transform_1e5 = "coord_transform(), 100k points"
)
e2e$label <- case_labels[e2e$case]
e2e$speedup <- e2e$ggplot2_ms / e2e$alot_ms
e2e$label <- factor(e2e$label, e2e$label[order(e2e$speedup)])
e2e$readme <- e2e$case == "readme"

p1 <- ggplot(e2e, aes(y = label)) +
  geom_segment(aes(x = alot_ms, xend = ggplot2_ms, yend = label), colour = col_grid, linewidth = 2.2) +
  geom_point(aes(x = ggplot2_ms), colour = col_gg, size = 3.6) +
  geom_point(aes(x = alot_ms), colour = col_alot, size = 3.6) +
  geom_text(aes(x = ggplot2_ms * 1.25, label = fmt_x(speedup), fontface = ifelse(readme, "bold", "plain")),
    hjust = 0, size = 3.8, colour = col_text) +
  annotate("text", x = e2e$alot_ms[e2e$speedup == max(e2e$speedup)], y = nrow(e2e) + 0.75, label = "alot_png()",
    colour = col_alot, size = 3.8, fontface = "bold", hjust = 0.5) +
  annotate("text", x = e2e$ggplot2_ms[e2e$speedup == max(e2e$speedup)], y = nrow(e2e) + 0.75, label = "ggsave() + ragg",
    colour = col_text2, size = 3.8, fontface = "bold", hjust = 0.5) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.1))) +
  scale_x_log10(
    breaks = c(100, 300, 1000, 3000, 10000, 30000, 1e5),
    labels = c("0.1 s", "0.3 s", "1 s", "3 s", "10 s", "30 s", "100 s"),
    expand = expansion(mult = c(0.03, 0.12))
  ) +
  labs(
    title = "alot_png() turns a ggplot into a PNG up to 29× faster than ggsave()",
    subtitle = "Time from ggplot object to PNG file, 1600 × 1000 px at 150 dpi (log scale). Both paths build the plot;\nalot draws the whole page in Rust (full tier) in all 18 cases.",
    x = NULL, y = NULL,
    caption = "* Dominated by building the plot (stat_align over 1M rows takes ~80 s in both). Medians of interleaved runs, release build,\nAMD EPYC 9474F, R 4.6.1, ggplot2 4.0.3, ragg 1.5.2. Data: tools/readme-data/bench-render-e2e.csv (inst/bench/render-e2e.R)."
  ) +
  theme_readme() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text, size = rel(0.95)))
save_figure(p1, "readme-render-speed.png", height = 1100)

# Figure 2: build coverage per pipeline step ----------------------------------

cov <- utils::read.csv(file.path(data_dir, "coverage-build.csv"))
build_plots <- utils::read.csv(file.path(data_dir, "coverage-build-plots.csv"))
n_plots <- nrow(build_plots)
step_labels <- c(
  facet_compute_layout = "Facet layout",
  facet_map_data = "Facet panel assignment",
  scale_transform = "Scale transforms",
  scale_train = "Position scale training",
  scale_map = "Position scale mapping",
  stat = "Stats",
  position = "Position adjustments",
  setup_panel_params = "Panel parameters",
  setup_panel_guides = "Panel guides (axes)",
  np_train = "Non-position scale training",
  np_map = "Non-position scale mapping"
)
noop <- is_noop(cov$step, cov$class)
cov$kind <- ifelse(cov$path == "rust", "rust", ifelse(noop, "noop", "ggplot2"))
cov <- cov[cov$step %in% names(step_labels), ]
steps <- stats::aggregate(n ~ step + kind, cov, sum)
steps <- stats::reshape(steps, idvar = "step", timevar = "kind", direction = "wide")
steps[is.na(steps)] <- 0
names(steps) <- sub("^n\\.", "", names(steps))
steps$work <- steps$rust + steps$ggplot2
steps$share <- steps$rust / steps$work
steps$label <- factor(step_labels[steps$step], rev(step_labels))
overall <- sum(steps$rust) / sum(steps$work)
all_rust <- mean(build_plots$all_rust)
utils::write.csv(steps[c("step", "rust", "ggplot2", "noop", "share")], file.path(data_dir, "coverage-build-steps.csv"), row.names = FALSE)

p2 <- ggplot(steps, aes(y = label)) +
  geom_col(aes(x = 1), fill = col_track, width = 0.62) +
  geom_col(aes(x = share), fill = col_alot, width = 0.62) +
  geom_text(aes(x = 1.02, label = sprintf("%s  (%s of %s)", pct(share), prettyNum(rust, big.mark = ","), prettyNum(work, big.mark = ","))),
    hjust = 0, size = 3.7, colour = col_text) +
  scale_x_continuous(breaks = c(0, 0.25, 0.5, 0.75, 1), labels = pct, limits = c(0, 1.42), expand = expansion(mult = c(0, 0))) +
  labs(
    title = sprintf("%s of the build components in %s corpus plots run in Rust", pct(overall), format(n_plots, big.mark = ",")),
    subtitle = sprintf(
      "Each bar: the share of components at that build step (one per layer, scale or facet) that ran a Rust kernel.\nIn %s of plots, every facet, scale and coord step ran in Rust. Stats and position adjustments have no kernels yet.",
      pct(all_rust)
    ),
    x = NULL, y = NULL,
    caption = sprintf(
      "Corpus: ggplot2 4.0.3's examples and tests (tests/testthat/corpus/). Left out: %s components with nothing to compute (facet_null(), stat_identity(),\nposition_identity(), discrete scale transforms). Every build equals ggplot2::ggplot_build(). Data: tools/readme-data/coverage-build*.csv.",
      format(sum(steps$noop), big.mark = ",")
    )
  ) +
  theme_readme() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text, size = rel(0.95)))
save_figure(p2, "readme-coverage-build.png", height = 900)

# Figure 3: render tiers over the render corpus -------------------------------

rcov <- utils::read.csv(file.path(data_dir, "coverage-render.csv"))
rcov$reason[is.na(rcov$reason)] <- ""
tiers <- as.data.frame(table(tier = factor(rcov$tier, c("full", "hybrid", "ggplot2"))))
tiers$share <- tiers$Freq / sum(tiers$Freq)
utils::write.csv(tiers[c("tier", "Freq")], file.path(data_dir, "coverage-render-tiers.csv"), row.names = FALSE)
# Name the geoms behind "no Rust drawer" (those in two or more plots).
layers <- utils::read.csv(file.path(data_dir, "coverage-render-layers.csv"))
undrawn <- table(layers$geom[layers$full_reason == "no Rust drawer for this geom"])
undrawn <- names(sort(undrawn[undrawn >= 2], decreasing = TRUE))
undrawn <- paste0("geom_", tolower(sub("^Geom", "", undrawn)), "()", collapse = ", ")
cap1 <- function(x) paste0(toupper(substr(x, 1, 1)), substring(x, 2))
relabel <- function(x) {
  x <- ifelse(x == "no Rust drawer for this geom", sprintf("no Rust drawer for the geom: %s", undrawn), x)
  # The same reason, worded by the layer check (text layers) and by the
  # page check (titles, axis and legend labels).
  x <- ifelse(x %in% c("label is not plain text (plotmath or another type)", "a label that is not plain text"),
    "a label is not plain text (plotmath or another type)", x)
  cap1(x)
}
# One row per plot not drawn in full and reason it gives.
fb <- rcov[rcov$tier != "full", ]
fb_reasons <- strsplit(fb$reason, " | ", fixed = TRUE)
fb <- data.frame(
  plot = rep(paste(fb$file, fb$id), lengths(fb_reasons)),
  tier = rep(fb$tier, lengths(fb_reasons)),
  reason = relabel(sub("^[a-z]+: ", "", unlist(fb_reasons)))
)
fb <- unique(fb)
counts <- sort(table(fb$reason), decreasing = TRUE)
top <- 10
keep <- names(counts)[seq_len(top)]
other <- sprintf("%d other reasons", length(counts) - top)
fb$reason <- ifelse(fb$reason %in% keep, fb$reason, other)
fb <- unique(fb)
fb$reason <- factor(fb$reason, rev(c(keep, other)))
fb$tier <- factor(fb$tier, c("ggplot2", "hybrid"))
tier_n <- stats::setNames(tiers$Freq, tiers$tier)

p3 <- ggplot(fb, aes(y = reason, fill = tier)) +
  geom_bar(width = 0.62, colour = "white", linewidth = 0.6) +
  scale_fill_manual(values = c(hybrid = col_hybrid, ggplot2 = col_gg), breaks = c("hybrid", "ggplot2"),
    labels = c(hybrid = "drawn by the hybrid tier", ggplot2 = "drawn by ggplot2 + ragg"), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.05)), position = "top") +
  labs(
    title = sprintf("alot draws %s of %s corpus plots entirely in Rust",
      pct(tiers$share[1]), format(nrow(rcov), big.mark = ",")),
    subtitle = sprintf(
      paste0(
        "%s plots render in the full tier (layout, text and marks in Rust). The rest fall back: %d to the hybrid tier\n",
        "(ggplot2 lays the page out, Rust draws the marks) and %d to ggplot2 + ragg, for these reasons (plots per reason)."
      ),
      format(tier_n[["full"]], big.mark = ","), tier_n[["hybrid"]], tier_n[["ggplot2"]]
    ),
    x = NULL, y = NULL,
    caption = "Render corpus: the ggplot2 example and test plots within the rendering scope (tests/testthat/render-corpus.tsv), as reported by\nalot_render_coverage(). A plot may give several reasons. Data: tools/readme-data/coverage-render.csv."
  ) +
  theme_readme() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text, size = rel(0.95)))
save_figure(p3 + theme(
  legend.position = "inside", legend.position.inside = c(0.98, 0.3), legend.justification.inside = c(1, 0.5),
  legend.text = element_text(colour = col_text, size = rel(0.9)), legend.key.size = unit(14, "pt")
), "readme-coverage-render.png", height = 900)

# Figure 4: build time at 1e6 and 1e7 rows -------------------------------------

rows <- utils::read.csv(file.path(data_dir, "bench-row-scaling.csv"))
build_labels <- c(
  point_discrete = "Points, discrete colour",
  point_continuous = "Points, continuous colour",
  facet_wrap_point = "Points in facet_wrap()",
  histogram_fill = "Histogram, filled by group",
  bar_dodge = "Dodged bars",
  density_groups = "Densities by group",
  boxplot = "Boxplots",
  smooth_lm = "Linear smooth"
)
rows$speedup <- rows$ggplot2_ms / rows$alot_ms
rows$label <- build_labels[rows$case]
order_1e7 <- rows[rows$rows == 1e7, ]
rows$label <- factor(rows$label, order_1e7$label[order(order_1e7$speedup)])
rows <- rows[rows$rows != 1e4, ]
rows$panel <- factor(ifelse(rows$rows == 1e6, "1 million rows", "10 million rows"), c("1 million rows", "10 million rows"))
small <- utils::read.csv(file.path(data_dir, "bench-row-scaling.csv"))
small <- small[small$rows == 1e4, ]
small_range <- range(small$ggplot2_ms / small$alot_ms)
series <- rows[rows$label == levels(rows$label)[nlevels(rows$label)], ]

p4 <- ggplot(rows, aes(y = label)) +
  geom_segment(aes(x = alot_ms, xend = ggplot2_ms, yend = label), colour = col_grid, linewidth = 2.2) +
  geom_point(aes(x = ggplot2_ms), colour = col_gg, size = 3.6) +
  geom_point(aes(x = alot_ms), colour = col_alot, size = 3.6) +
  geom_text(aes(x = ggplot2_ms * 1.12, label = fmt_x(speedup)), hjust = 0, size = 3.7, colour = col_text) +
  geom_text(aes(x = alot_ms, label = "alot_build()"), y = nlevels(rows$label) + 0.75, colour = col_alot,
    size = 3.6, fontface = "bold", hjust = 0.2, data = series) +
  geom_text(aes(x = ggplot2_ms, label = "ggplot_build()"), y = nlevels(rows$label) + 0.75, colour = col_text2,
    size = 3.6, fontface = "bold", hjust = 0.6, data = series) +
  facet_wrap(~panel, scales = "free_x") +
  scale_x_log10(labels = function(x) fmt_ms(x), breaks = c(100, 200, 500, 1000, 2000, 5000, 10000),
    expand = expansion(mult = c(0.08, 0.2))) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.1))) +
  labs(
    title = "alot_build() builds large plots 1.2–4.3× faster than ggplot_build()",
    subtitle = sprintf(
      "Build time (log scale) for eight plot types; the output is identical. Gains grow with data size, and where the\nposition scales, not stats, dominate. At 10,000 rows both take 20–60 ms (%.2f–%.2f×).",
      small_range[1], small_range[2]
    ),
    x = NULL, y = NULL,
    caption = "Release build, AMD EPYC 9474F, R 4.6.1, ggplot2 4.0.3. Data: tools/readme-data/bench-row-scaling.csv (inst/bench/row-scaling.R);\nper-step times and facet scaling in inst/bench/RESULTS.md."
  ) +
  theme_readme() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text, size = rel(0.95)),
    panel.spacing.x = unit(28, "pt"), strip.text = element_text(size = rel(1), margin = margin(b = 6)))
save_figure(p4, "readme-build-speed.png", height = 850)
