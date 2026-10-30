# Extract the plot corpus for tests/testthat/test-corpus.R (T0.5).
#
# Run from the repo root:
#
#   Rscript tools/extract-corpus.R [path/to/ggplot2]
#
# The ggplot2 source defaults to ../ggplot2. Every man/*.Rd example section
# and every tests/testthat/test-*.R file is evaluated statement by statement.
# A statement whose value is a ggplot becomes a plot, and so does a ggplot
# passed to a consumer such as ggplot_build(), layer_data() or
# expect_doppelganger() inside an expectation. Setup statements (assignments,
# library(), theme_set(), skips, ...) that ran without error are kept so the
# plots can be rebuilt. Everything else is dropped. Each source becomes one
# file in tests/testthat/corpus/ made of corpus_block() calls; skipped and
# failed statements are logged to tests/testthat/corpus/_dropped.tsv.

args <- commandArgs(trailingOnly = TRUE)
ggplot2_src <- normalizePath(if (length(args)) args[[1]] else "../ggplot2", mustWork = TRUE)
out_dir <- file.path("tests", "testthat", "corpus")
stopifnot(dir.exists(dirname(out_dir)))

suppressPackageStartupMessages({
  library(ggplot2)
  library(testthat)
})
local_edition(3)
# ggplot2's tests run with NOT_CRAN set, so skip_on_cran() must not fire.
Sys.setenv(NOT_CRAN = "true")

# Calls whose first argument, when it evaluates to a ggplot, is a plot.
consumers <- c(
  "ggplot_build", "build_ggplot", "ggplot_gtable", "ggplotGrob", "layer_data",
  "get_layer_data", "layer_grob", "get_layer_grob", "layer_scales",
  "get_panel_scales", "get_guide_data", "get_labs", "get_alt_text", "print",
  "plot", "cdata", "pranges", "ggsave"
)
# Calls kept as setup even though they are not assignments.
setup_calls <- c(
  "library", "require", "requireNamespace", "suppressPackageStartupMessages",
  "set.seed", "data", "options", "Sys.setenv", "Sys.setlocale", "invisible",
  "theme_set", "set_theme", "theme_update", "update_theme", "theme_replace",
  "replace_theme", "reset_theme_settings", "update_geom_defaults",
  "update_stat_defaults", "reset_geom_defaults", "reset_stat_defaults",
  "update_theme_settings", "local_edition", "local_options", "local_seed",
  "local_locale", "local_envvar", "local_timezone", "defer", "rm"
)
# withr calls whose `code` is handled statement by statement inside the
# wrapper's context, then kept wrapped in the same call.
with_calls <- c("with_options", "with_seed", "with_preserve_seed", "with_locale",
                "with_collate", "with_envvar", "with_timezone", "with_language")
# Calls never evaluated (they draw, write files or need a graphics device).
drop_calls <- c("print", "plot", "ggsave", "grid.draw", "grid.newpage", "dev.off",
                "local_pdf", "local_tempfile", "with_tempfile", "str", "summary")

call_name <- function(x) {
  if (!is.call(x)) return("")
  fn <- x[[1]]
  if (is.symbol(fn)) return(as.character(fn))
  if (is.call(fn) && as.character(fn[[1]]) %in% c("::", ":::")) return(as.character(fn[[3]]))
  ""
}

is_assignment <- function(x) call_name(x) %in% c("<-", "=", "<<-")

stmt_text <- function(expr, ref = NULL) {
  if (!is.null(ref)) return(as.character(ref, useSource = TRUE))
  deparse(expr, width.cutoff = 80L)
}

# Statements of `{`, with srcrefs when the parser kept them.
brace_stmts <- function(expr, refs = NULL) {
  if (call_name(expr) == "{") {
    refs <- attr(expr, "srcref")
    exprs <- as.list(expr)[-1]
    refs <- if (length(refs) == length(exprs) + 1) refs[-1] else NULL
  } else {
    exprs <- list(expr)
    refs <- if (!is.null(refs)) list(refs) else NULL
  }
  lapply(seq_along(exprs), function(i) list(expr = exprs[[i]], ref = refs[[i]]))
}

# Consumer-call arguments inside `expr`, outermost first.
consumer_args <- function(expr) {
  out <- list()
  walk <- function(x) {
    if (!is.call(x)) return()
    nm <- call_name(x)
    if (nm %in% c("expect_doppelganger") && length(x) >= 3) {
      args <- as.list(x)[-1]
      unnamed <- args[(names(args) %||% rep("", length(args))) == ""]
      out[[length(out) + 1]] <<- if (!is.null(args$fig)) args$fig else unnamed[[2]]
    } else if (nm %in% consumers && length(x) >= 2) {
      out[[length(out) + 1]] <<- x[[2]]
    }
    if (nm == "function") return()
    args <- as.list(x)[-1]
    for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) walk(args[[i]])
  }
  walk(expr)
  out
}

is_plot <- function(x) inherits(x, "ggplot") && !inherits(x, "ggplot_built")

dropped <- list()
log_drop <- function(block, expr, reason) {
  dropped[[length(dropped) + 1]] <<- data.frame(
    block = block,
    statement = substr(gsub("\\s+", " ", paste(deparse(expr, width.cutoff = 500L)[1], collapse = " ")), 1, 100),
    reason = substr(gsub("\\s+", " ", reason), 1, 200)
  )
}

tools_env <- environment()

# Evaluate `stmts` for block `name` in a fresh function frame (so withr and
# testthat local_*() helpers have a frame to attach to) and return the lines
# of the corpus_block() call, or NULL if it holds no plot.
extract_block <- function(name, stmts) {
  runner <- function(.corpus_stmts, .corpus_name) {
    .corpus_env <- environment()
    .corpus_lines <- character()
    .corpus_n <- 0L
    .corpus_seen <- list()
    .corpus_skip <- FALSE

    .corpus_try <- function(expr) {
      tryCatch(
        {
          utils::capture.output(value <- suppressWarnings(suppressMessages(eval(expr, .corpus_env))))
          list(ok = TRUE, value = value)
        },
        skip = function(e) { .corpus_skip <<- TRUE; list(ok = FALSE, msg = paste("skip:", conditionMessage(e))) },
        error = function(e) list(ok = FALSE, msg = conditionMessage(e))
      )
    }
    .corpus_emit_plot <- function(expr, text) {
      .corpus_n <<- .corpus_n + 1L
      id <- sprintf("%s #%d", .corpus_name, .corpus_n)
      .corpus_lines <<- c(.corpus_lines, sprintf(".plot(%s, %s)", deparse(id), paste(text, collapse = "\n")))
    }
    .corpus_seen_before <- function(value) {
      any(vapply(.corpus_seen, identical, logical(1), value))
    }
    .corpus_handle <- function(expr, ref) {
      nm <- .corpus_tools$call_name(expr)
      if (nm == "{") {
        for (s in .corpus_tools$brace_stmts(expr)) if (!.corpus_skip) .corpus_handle(s$expr, s$ref)
        return()
      }
      if (nm == "if") {
        cond <- .corpus_try(expr[[2]])
        if (!cond$ok || !is.logical(cond$value) || length(cond$value) != 1 || is.na(cond$value)) {
          .corpus_tools$log_drop(.corpus_name, expr, if (cond$ok) "if: condition not TRUE/FALSE" else cond$msg)
          return()
        }
        branch <- if (cond$value) expr[[3]] else if (length(expr) >= 4) expr[[4]] else NULL
        if (!is.null(branch)) for (s in .corpus_tools$brace_stmts(branch)) if (!.corpus_skip) .corpus_handle(s$expr, s$ref)
        return()
      }
      # for (var in seq) body: unrolled, each iteration emitting the loop
      # variable's binding and then the body's statements. Loops using next
      # or break run as one statement instead.
      if (nm == "for" && !any(c("next", "break") %in% all.names(expr[[4]]))) {
        seq <- .corpus_try(expr[[3]])
        if (!seq$ok) {
          .corpus_tools$log_drop(.corpus_name, expr, seq$msg)
          return()
        }
        var <- as.character(expr[[2]])
        for (i in seq_along(seq$value)) {
          bind <- call("<-", as.name(var), call("[[", call("(", expr[[3]]), i))
          .corpus_handle(bind, NULL)
          for (s in .corpus_tools$brace_stmts(expr[[4]])) if (!.corpus_skip) .corpus_handle(s$expr, s$ref)
        }
        return()
      }
      if (nm %in% .corpus_tools$with_calls) {
        .corpus_handle_with(expr)
        return()
      }
      # Plots handed to consumers inside this statement, evaluated in the
      # state before the statement runs.
      for (arg in .corpus_tools$consumer_args(expr)) {
        res <- .corpus_try(arg)
        if (res$ok && .corpus_tools$is_plot(res$value) && !.corpus_seen_before(res$value)) {
          .corpus_seen[[length(.corpus_seen) + 1]] <<- res$value
          .corpus_emit_plot(arg, .corpus_tools$stmt_text(arg))
        }
      }
      if (startsWith(nm, "expect_") || nm %in% .corpus_tools$drop_calls) return()
      if (startsWith(nm, "skip")) {
        res <- .corpus_try(expr)
        .corpus_lines <<- c(.corpus_lines, .corpus_tools$stmt_text(expr, ref))
        if (!res$ok) .corpus_tools$log_drop(.corpus_name, expr, res$msg)
        return()
      }
      res <- .corpus_try(expr)
      if (!res$ok) {
        .corpus_tools$log_drop(.corpus_name, expr, res$msg)
        return()
      }
      if (.corpus_tools$is_plot(res$value)) {
        .corpus_seen[[length(.corpus_seen) + 1]] <<- res$value
        .corpus_emit_plot(expr, .corpus_tools$stmt_text(expr, ref))
      } else if (.corpus_tools$is_assignment(expr) || nm %in% .corpus_tools$setup_calls || startsWith(nm, "local_")) {
        .corpus_lines <<- c(.corpus_lines, .corpus_tools$stmt_text(expr, ref))
      }
    }

    # withr::with_*(..., code): run `code`'s statements through
    # .corpus_handle() inside the wrapper, so its options, seed or locale
    # apply and its assignments land in this frame, as they would in the
    # test. The kept lines are emitted wrapped in the same call.
    .corpus_handle_with <- function(expr) {
      fn <- .corpus_try(expr[[1]])
      matched <- if (fn$ok && is.function(fn$value)) match.call(fn$value, expr) else NULL
      if (is.null(matched$code)) {
        .corpus_tools$log_drop(.corpus_name, expr, "with_*: no `code` argument")
        return()
      }
      code <- matched$code
      outer_lines <- .corpus_lines
      .corpus_lines <<- character()
      matched$code <- as.call(list(function() {
        for (s in .corpus_tools$brace_stmts(code)) if (!.corpus_skip) .corpus_handle(s$expr, s$ref)
      }))
      res <- .corpus_try(matched)
      inner_lines <- .corpus_lines
      .corpus_lines <<- outer_lines
      if (!res$ok) {
        .corpus_tools$log_drop(.corpus_name, expr, res$msg)
        return()
      }
      if (length(inner_lines) == 0) return()
      matched$code <- quote(.CORPUS_CODE.)
      head <- strsplit(paste(deparse(matched, width.cutoff = 500L), collapse = " "), ".CORPUS_CODE.", fixed = TRUE)[[1]]
      body <- paste0("  ", gsub("\n", "\n  ", inner_lines))
      .corpus_lines <<- c(.corpus_lines, paste(c(paste0(head[1], "{"), body, paste0("}", head[2])), collapse = "\n"))
    }

    for (.corpus_s in .corpus_stmts) {
      if (.corpus_skip) break
      .corpus_handle(.corpus_s$expr, .corpus_s$ref)
    }
    if (.corpus_n == 0L) return(NULL)
    .corpus_lines
  }
  # The runner's frame is where the plot code runs, so it sees ggplot2's
  # namespace (tests use internals) and this script's helpers only through
  # `.corpus_tools`.
  environment(runner) <- new.env(parent = asNamespace("ggplot2"))
  environment(runner)$.corpus_tools <- tools_env
  # Helpers from ggplot2's tests (cdata(), pranges(), quos_list()).
  sys.source(file.path(out_dir, "_helpers.R"), envir = environment(runner))
  old_opts <- options()
  old_theme <- theme_get()
  on.exit({
    options(old_opts)
    theme_set(old_theme)
  })
  set.seed(1)
  lines <- runner(stmts, name)
  if (is.null(lines)) return(NULL)
  body <- paste0("  ", gsub("\n", "\n  ", lines))
  c(sprintf("corpus_block(%s, {", deparse(name)), body, "})", "")
}

write_corpus_file <- function(file, source, blocks) {
  blocks <- Filter(Negate(is.null), blocks)
  if (length(blocks) == 0) return(0L)
  header <- c(
    sprintf("# Generated by tools/extract-corpus.R from ggplot2 %s %s.",
            utils::packageVersion("ggplot2"), source),
    "# Do not edit by hand; rerun the script instead.",
    ""
  )
  writeLines(c(header, unlist(blocks)), file.path(out_dir, file), useBytes = TRUE)
  sum(lengths(regmatches(unlist(blocks), gregexpr("^  \\.plot\\(", unlist(blocks)))))
}

# Start from a clean directory.
unlink(out_dir, recursive = TRUE)
dir.create(out_dir)
helper_files <- file.path(ggplot2_src, "tests", "testthat", c("helper-plot-data.R", "helper-facet.R"))
writeLines(c(
  "# Copied by tools/extract-corpus.R from ggplot2's tests/testthat helpers.",
  "# Do not edit by hand; rerun the script instead.",
  "",
  unlist(lapply(helper_files, readLines))
), file.path(out_dir, "_helpers.R"))

counts <- integer()

# man/*.Rd examples: one block per page; examples share state.
for (rd in sort(list.files(file.path(ggplot2_src, "man"), "\\.Rd$", full.names = TRUE))) {
  ex <- tempfile(fileext = ".R")
  tools::Rd2ex(rd, ex, commentDontrun = TRUE, commentDonttest = FALSE)
  if (!file.exists(ex)) next
  exprs <- parse(ex, keep.source = TRUE, encoding = "UTF-8")
  refs <- attr(exprs, "srcref")
  stmts <- lapply(seq_along(exprs), function(i) list(expr = exprs[[i]], ref = refs[[i]]))
  page <- basename(rd)
  block <- extract_block(page, stmts)
  file <- paste0("man-", sub("\\.Rd$", ".R", page))
  counts[file] <- write_corpus_file(file, paste0("man/", page), list(block))
}

# tests/testthat/test-*.R: one block per test_that(); top-level code outside
# test_that() runs before each later block.
for (tf in sort(list.files(file.path(ggplot2_src, "tests", "testthat"), "^test-.*\\.R$", full.names = TRUE))) {
  exprs <- parse(tf, keep.source = TRUE, encoding = "UTF-8")
  refs <- attr(exprs, "srcref")
  preamble <- list()
  blocks <- list()
  for (i in seq_along(exprs)) {
    e <- exprs[[i]]
    if (call_name(e) == "test_that") {
      args <- as.list(e)[-1]
      desc <- args[[1]]
      code <- if (!is.null(args$code)) args$code else args[[2]]
      if (!is.character(desc)) desc <- deparse(desc)
      stmts <- c(preamble, brace_stmts(code))
      blocks[[length(blocks) + 1]] <- extract_block(paste0(basename(tf), ": ", desc), stmts)
    } else {
      preamble[[length(preamble) + 1]] <- list(expr = e, ref = refs[[i]])
    }
  }
  file <- basename(tf)
  counts[file] <- write_corpus_file(file, paste0("tests/testthat/", file), blocks)
}

dropped <- do.call(rbind, dropped)
utils::write.table(dropped, file.path(out_dir, "_dropped.tsv"), sep = "\t", row.names = FALSE, quote = TRUE)

cat(sprintf("Corpus: %d plots in %d files (%d from man/, %d from tests/).\n",
            sum(counts), sum(counts > 0),
            sum(counts[startsWith(names(counts), "man-")]),
            sum(counts[!startsWith(names(counts), "man-")])))
cat(sprintf("Dropped %d statements; see %s.\n", nrow(dropped), file.path(out_dir, "_dropped.tsv")))
