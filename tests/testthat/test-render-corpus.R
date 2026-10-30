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

# Looser tolerances for the hybrid tier's point drawer (R0.1 prototype),
# measured on the full render corpus at R0.2:
# - Disc edges: sprite coverage (16 x 16 samples, 1/16-px offsets) differs
#   from AGG's exact-area coverage by up to about 14 of 255 per point, and
#   the difference compounds where points overplot (duplicate rows in mpg),
#   reaching about 150 on a few edge pixels while well under 1% of pixels
#   differ by more than 8. Point sprite fidelity is R1.2's, which should
#   restore the default `max`.
# - Many faint overlapping points: ragg rounds to 8 bits on every blend, so
#   low-alpha overplotting stalls short of where alot's f32 accumulation
#   ends (about 2% of pixels differ by more than 8). Mirroring that is a
#   canvas question for R1.1.
hybrid_max <- 160
hybrid_share <- c("geom_point.Rd #9" = 0.025, "geom_point.Rd #10" = 0.025)

render_corpus_check <- function(id, p) {
  set.seed(1)
  b <- suppressWarnings(suppressMessages(ggplot2::ggplot_build(p)))
  cov <- render_coverage(b)
  render_counts$tier <- c(render_counts$tier, cov$tier)
  if (cov$tier == "ggplot2") {
    render_counts$reasons <- c(render_counts$reasons, unique(cov$layers$reason))
    return(succeed())
  }
  if (cov$tier == "hybrid") {
    share <- if (id %in% names(hybrid_share)) hybrid_share[[id]] else 0.01
    return(suppressMessages(expect_render_close(b, max = hybrid_max, share = share, tier = "hybrid", label = id)))
  }
  suppressMessages(expect_render_close(b, tier = cov$tier, label = id))
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
