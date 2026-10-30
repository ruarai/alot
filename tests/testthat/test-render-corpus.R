# Render corpus (R0.2): the Phase 1 corpus plots within PHASE2.md's scope,
# listed in render-corpus.tsv by tools/render-corpus.R. Each plot is built
# once with ggplot2 and drawn by ggplot2 + ragg and by alot at
# render_size (helper-render.R). Plots that alot draws in one of its tiers
# must pass expect_render_close() in that tier; the rest are reported as
# fallbacks, with alot_render_coverage()'s reasons.
#
# ALOT_RENDER_CORPUS, a regex on corpus file names like ALOT_CORPUS, runs a
# subset.

skip_on_cran()
library(ggplot2)

corpus_dir <- test_path("corpus")
render_ids <- utils::read.delim(test_path("render-corpus.tsv"), skip = 2, comment.char = "", quote = "")
render_filter <- Sys.getenv("ALOT_RENDER_CORPUS")
render_files <- unique(render_ids$file)
if (nzchar(render_filter)) {
  render_files <- grep(render_filter, render_files, value = TRUE)
}
render_counts <- new.env()
render_counts$tier <- character()
render_counts$reasons <- character()

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
  if (cov$tier == "ggplot2") {
    render_counts$reasons <- c(render_counts$reasons, unique(cov$layers$reason))
    return(succeed())
  }
  share <- if (id %in% names(render_share)) render_share[[id]] else 0.01
  max <- if (id %in% names(render_max)) render_max[[id]] else 32
  suppressMessages(expect_render_close(b, max = max, share = share, tier = cov$tier, label = id))
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
      test_that(paste("render corpus:", block[[2]]), run_render_block(code, ids))
    })
  }
}

message(sprintf(
  "Render corpus: %d plots; %s. Fallback reasons: %s.",
  length(render_counts$tier),
  paste(sprintf("%d %s", table(render_counts$tier), names(table(render_counts$tier))), collapse = ", "),
  paste(sprintf("%s (%d)", names(table(render_counts$reasons)), table(render_counts$reasons)), collapse = ", ")
))
