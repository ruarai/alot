# Runs the test files in parallel processes (one file per process, a pool of
# workers) and reports a summary line per file, then the failures. Usage,
# from the repo root:
#
#   NOT_CRAN=true Rscript tools/test-parallel.R [workers] [filter] [log-dir]
#
# `workers` defaults to half the cores (each render test also uses Rust
# threads). `filter` is a regex on the file names without `test-` and `.R`;
# by default every file except `corpus` and `render-corpus` runs (those have
# their own subsets and tools/render-corpus-sharded.R). Set
# ALOT_RENDER_CACHE=<dir> to cache ggplot2's reference renders and layouts
# between runs (see helper-render.R). The crates are built once before the
# workers start. Exits non-zero if any file fails.
args <- commandArgs(trailingOnly = TRUE)
workers <- as.integer(if (length(args) >= 1 && nzchar(args[1])) args[1] else max(2L, parallel::detectCores() %/% 2L))
filter <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "^(?!(corpus|render-corpus)$)"
dir <- if (length(args) >= 3) args[3] else tempfile("test-parallel-")
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
pkgload::load_all(quiet = TRUE)

files <- list.files("tests/testthat", "^test-.*\\.R$")
names <- sub("\\.R$", "", sub("^test-", "", files))
keep <- grepl(filter, names, perl = TRUE)
files <- files[keep]
# Biggest files first, so the pool finishes together.
files <- files[order(-file.size(file.path("tests/testthat", files)))]

worker <- paste(
  "pkgload::load_all(compile = FALSE, quiet = TRUE)",
  "t <- system.time(res <- testthat::test_file(commandArgs(TRUE)[1], load_package = 'none', reporter = 'silent', stop_on_failure = FALSE))[3]",
  "df <- as.data.frame(res)",
  "cat(sprintf('RESULT %d %d %d %d %.1f\\n', sum(df$passed), sum(df$failed + df$error), sum(df$warning), sum(df$skipped), t))",
  "for (r in res) for (e in r$results) if (!inherits(e, 'expectation_success') && !inherits(e, 'expectation_skip') && !inherits(e, 'expectation_warning')) cat('\\n', r$test, ':', conditionMessage(e), '\\n')",
  sep = "; "
)
run_one <- function(f) {
  log <- file.path(dir, paste0(f, ".log"))
  status <- system2("Rscript", c("-e", shQuote(worker), file.path("tests/testthat", f)),
    stdout = log, stderr = log, env = "NOT_CRAN=true")
  line <- grep("^RESULT ", readLines(log, warn = FALSE), value = TRUE)
  if (length(line) == 0) {
    return(c(file = f, pass = NA, fail = NA, warn = NA, skip = NA, secs = NA))
  }
  v <- strsplit(line[1], " ")[[1]][-1]
  c(file = f, pass = v[1], fail = v[2], warn = v[3], skip = v[4], secs = v[5])
}
start <- Sys.time()
out <- parallel::mclapply(files, run_one, mc.cores = workers, mc.preschedule = FALSE)
tab <- as.data.frame(do.call(rbind, out))
tab[-1] <- lapply(tab[-1], as.numeric)
print(tab[order(-tab$secs), ], row.names = FALSE)
bad <- is.na(tab$fail) | tab$fail > 0
cat(sprintf("\n%d files, %d passed, %d failed, %d warnings, %d skipped; %.0f s wall, %.0f s of test time\n",
  nrow(tab), sum(tab$pass, na.rm = TRUE), sum(tab$fail, na.rm = TRUE), sum(tab$warn, na.rm = TRUE), sum(tab$skip, na.rm = TRUE),
  as.numeric(difftime(Sys.time(), start, units = "secs")), sum(tab$secs, na.rm = TRUE)))
for (f in tab$file[bad]) {
  cat("\n==", f, "==\n")
  cat(tail(readLines(file.path(dir, paste0(f, ".log")), warn = FALSE), 40), sep = "\n")
}
cat("logs in", dir, "\n")
quit(status = as.integer(any(bad)))
