# Runs the render corpus (tests/testthat/test-render-corpus.R) in parallel
# processes, each on a share of the corpus files (ALOT_RENDER_SHARD), and
# reports the totals. Usage, from the repo root:
#
#   NOT_CRAN=true Rscript tools/render-corpus-sharded.R [shards] [log-dir]
#
# `shards` defaults to the number of cores. Set ALOT_RENDER_FULL=1 for every
# plot and ALOT_RENDER_CACHE=<dir> to cache ggplot2's references; both pass
# through to the shards. The crates are built once before the shards start.
args <- commandArgs(trailingOnly = TRUE)
n <- as.integer(if (length(args) >= 1) args[1] else parallel::detectCores())
dir <- if (length(args) >= 2) args[2] else tempfile("render-shards-")
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
pkgload::load_all(quiet = TRUE)

cmd <- "pkgload::load_all(compile = FALSE, quiet = TRUE); testthat::test_dir('tests/testthat', filter = '^render-corpus$', load_package = 'none')"
procs <- lapply(seq_len(n), function(i) {
  log <- file.path(dir, sprintf("shard-%d.log", i))
  system2(
    "Rscript", c("-e", shQuote(cmd)), stdout = log, stderr = log, wait = FALSE,
    env = c(sprintf("ALOT_RENDER_SHARD=%d/%d", i, n), "NOT_CRAN=true")
  )
  log
})
# system2(wait = FALSE) doesn't return a handle: wait for the summary line.
repeat {
  done <- vapply(unlist(procs), function(l) any(grepl("^\\[ FAIL", readLines(l, warn = FALSE))), logical(1))
  if (all(done)) break
  Sys.sleep(5)
}
sums <- vapply(unlist(procs), function(l) tail(grep("^\\[ FAIL", readLines(l, warn = FALSE), value = TRUE), 1), "")
cat(sprintf("shard %d: %s\n", seq_len(n), sums), sep = "")
cat("logs in", dir, "\n")
quit(status = as.integer(any(!grepl("^\\[ FAIL 0 ", sums))))
