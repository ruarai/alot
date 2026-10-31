# Render corpus (R0.2): the Phase 1 corpus plots within PHASE2.md's scope,
# listed in render-corpus.tsv by tools/render-corpus.R. Each plot is built
# once with ggplot2 and drawn by ggplot2 + ragg and by alot at
# render_size (helper-render.R). Plots that alot draws in one of its tiers
# must pass expect_render_close() in that tier; the rest are reported as
# fallbacks, with alot_render_coverage()'s reasons.
#
# By default one plot in `ALOT_RENDER_SAMPLE` (8) runs, spread evenly through
# the corpus; ALOT_RENDER_FULL=1 runs them all. ALOT_RENDER_CORPUS, a regex
# on corpus file names like ALOT_CORPUS, runs every plot in the matching
# files. ALOT_RENDER_SHARD="i/n" runs the files i, i + n, ... (1-based), so
# n processes can split the corpus (tools/render-corpus-sharded.R).
# ALOT_RENDER_CACHE=<dir> caches ggplot2's reference renders between runs
# (helper-render.R). The layout check (R4.1) runs once per distinct
# structure (theme, labels present, axes, legends, coord) unless
# ALOT_LAYOUT_ALL=1.

skip_on_cran()
library(ggplot2)

corpus_dir <- test_path("corpus")
render_ids <- utils::read.delim(test_path("render-corpus.tsv"), skip = 2, comment.char = "", quote = "")
render_filter <- Sys.getenv("ALOT_RENDER_CORPUS")
render_files <- unique(render_ids$file)
if (nzchar(render_filter)) {
  render_files <- grep(render_filter, render_files, value = TRUE)
} else if (!identical(Sys.getenv("ALOT_RENDER_FULL"), "1")) {
  every <- as.integer(Sys.getenv("ALOT_RENDER_SAMPLE", "8"))
  render_ids <- render_ids[seq_len(nrow(render_ids)) %% every == 1L, ]
  render_files <- unique(render_ids$file)
}
if (nzchar(Sys.getenv("ALOT_RENDER_SHARD"))) {
  shard <- as.integer(strsplit(Sys.getenv("ALOT_RENDER_SHARD"), "/")[[1]])
  render_files <- render_files[seq_along(render_files) %% shard[2] == shard[1] %% shard[2]]
}
render_counts <- new.env()
render_counts$tier <- character()
render_counts$reasons <- character()
render_counts$ir <- character()
render_counts$layout <- character()
render_counts$layout_seen <- character()
render_counts$file <- NA_character_
render_counts$context <- NULL

# Looser tolerances where many marks overplot: ragg rounds to 8 bits on
# every blend, alot accumulates in f32 (PHASE2.md, Canvas). Faint points
# (alpha 1/20, 1/100) stall short of alot's result on about 2% of pixels;
# about 100 opaque points stacked on one spot (scale_identity.Rd #1, the
# grey ramp at u = v = 0) differ on their shared edge pixels.
render_share <- c("geom_point.Rd #9" = 0.025, "geom_point.Rd #10" = 0.025)
render_max <- c("geom_point.Rd #10" = 64, "scale_identity.Rd #1" = 48)

render_corpus_check <- function(id, p) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot2::ggplot_build(p)))
  cov <- render_coverage(b)
  render_counts$tier <- c(render_counts$tier, cov$tier)
  # Every plot's render IR builds (R3.1); its support table gives the
  # reasons the full tier would decline.
  ir <- tryCatch(render_ir(b), error = function(e) e)
  if (inherits(ir, "error")) {
    return(fail(sprintf("%s: render_ir() failed: %s", id, conditionMessage(ir))))
  }
  render_counts$ir <- c(render_counts$ir, if (nrow(ir$support)) unique(paste0(ir$support$component, ": ", ir$support$reason)) else "full")
  # The Rust page layout (R4.1) matches grid's wherever alot lays the plot out.
  signature <- layout_signature(b, ir)
  if (!signature %in% render_counts$layout_seen || identical(Sys.getenv("ALOT_LAYOUT_ALL"), "1")) {
    render_counts$layout_seen <- c(render_counts$layout_seen, signature)
    layout <- tryCatch(expect_layout_matches(b, label = id), error = function(e) paste("error:", conditionMessage(e)))
    if (is.character(layout) && startsWith(layout, "error:")) {
      return(fail(sprintf("%s: layout failed: %s", id, layout)))
    }
    render_counts$layout <- c(render_counts$layout, layout %||% "laid out")
  }
  if (cov$tier == "ggplot2") {
    render_counts$reasons <- c(render_counts$reasons, unique(cov$layers$reason))
    return(succeed())
  }
  share <- if (id %in% names(render_share)) render_share[[id]] else 0.01
  max <- if (id %in% names(render_max)) render_max[[id]] else 32
  reference <- NULL
  if (nzchar(Sys.getenv("ALOT_RENDER_CACHE"))) {
    render_counts$context <- render_counts$context %||% render_cache_context()
    key <- list(
      render_counts$context, id, unname(tools::md5sum(file.path(corpus_dir, render_counts$file)))
    )
    reference <- render_cached_reference(key, function() render_reference(b))
  }
  suppressMessages(expect_render_close(b, max = max, share = share, tier = cov$tier, label = id, reference = reference))
}

# What the page layout depends on besides label text and breaks: the theme,
# which titles and legends are present, the axis guides, and the coord.
layout_signature <- function(built, ir) {
  rlang::hash(list(
    ir$theme, ir$coord$class, ir$facet$class,
    lengths(built@plot@labels[c("title", "subtitle", "caption", "tag")]) > 0,
    lapply(ir$scales[[1]]$axes, function(a) a[c("position", "angle", "n.dodge", "minor.ticks")]),
    vapply(ir$legends, function(l) l$class, character(1)),
    built@layout$coord$aspect(built@layout$panel_params[[1]]),
    is.null(built@layout$panel_params[[1]]$draw_labels)
  ))
}

# As run_corpus_block() in test-corpus.R, checking the listed plots only.
run_render_block <- function(code, ids) {
  env <- new.env(parent = asNamespace("ggplot2"))
  sys.source(file.path(corpus_dir, "_helpers.R"), envir = env)
  env$.plot <- function(id, expr) {
    p <- expr
    if (id %in% ids) {
      render_corpus_check(id, p)
    }
    invisible(p)
  }
  runner <- rlang::new_function(list(), code, env)
  old_opts <- options()
  old_theme <- ggplot2::theme_get()
  on.exit({
    options(old_opts)
    ggplot2::theme_set(old_theme)
  })
  set.seed(1)
  tryCatch(
    suppressWarnings(suppressMessages(runner())),
    packageNotFoundError = function(e) skip(conditionMessage(e))
  )
}

for (file in render_files) {
  ids <- render_ids$id[render_ids$file == file]
  for (block in parse(file.path(corpus_dir, file), keep.source = FALSE, encoding = "UTF-8")) {
    code <- block[[3]]
    if (!any(vapply(ids, grepl, logical(1), x = paste(deparse(code), collapse = "\n"), fixed = TRUE))) {
      next
    }
    local({
      code <- code
      file <- file
      test_that(paste("render corpus:", block[[2]]), {
        render_counts$file <- file
        run_render_block(code, ids)
      })
    })
  }
}

message(sprintf(
  "Render corpus: %d plots; %s. Fallback reasons: %s.",
  length(render_counts$tier),
  paste(sprintf("%d %s", table(render_counts$tier), names(table(render_counts$tier))), collapse = ", "),
  paste(sprintf("%s (%d)", names(table(render_counts$reasons)), table(render_counts$reasons)), collapse = ", ")
))
message(sprintf(
  "Render IR built for every plot; full-tier support: %s.",
  paste(sprintf("%s (%d)", names(table(render_counts$ir)), table(render_counts$ir)), collapse = ", ")
))
message(sprintf(
  "Layout (single panel): %s.",
  paste(sprintf("%s (%d)", names(table(render_counts$layout)), table(render_counts$layout)), collapse = ", ")
))
