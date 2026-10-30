# AGENTS.md

alot is an R package that reimplements `ggplot2::ggplot_build()` with the
hot paths in Rust. **Its output must equal ggplot2's** under
`expect_equal(..., tolerance = 1e-8)`. Speed only matters once that holds.

- [PLAN.md](PLAN.md) explains the strategy and why. [TASKS.md](TASKS.md) holds
  the work items. Before starting a task, read its entry and the shared
  completion criteria at the top of TASKS.md.
- [PHASE2.md](PHASE2.md) covers rendering. It is out of scope unless a task
  says otherwise.
- The reference source is ggplot2 4.0.3 at `../ggplot2` (relative to the repo
  root). Read the upstream function before mirroring or porting it, and cite
  it in a comment, for example `# Mirrors Layout$map_position (ggplot2
  R/layout.R).`
- For rendering (Phase 2), the references are ragg 1.5.2 at `../ragg`
  (mainly `src/AggDevice.h`) and R 4.6.1 at `../r-source` (graphics engine
  in `src/main/engine.c`, grid in `src/library/grid`). Cite them the same
  way.

## Commands

`cargo` lives in `~/.cargo/bin`, which may not be on `PATH`:

```sh
export PATH="$PATH:$HOME/.cargo/bin"

# Rust unit tests (alot-core)
(cd src/rust && cargo test)

# R tests; this compiles the Rust crates
NOT_CRAN=true Rscript -e 'pkgload::load_all(); testthat::test_dir("tests/testthat", load_package = "none")'

# Only one test file
NOT_CRAN=true Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-scale-train.R", load_package = "none")'
```

Run independent test files in parallel where it saves time, e.g. the corpus
subset alongside the other files, or a long file such as `test-corpus.R` on
its own. Build once first (`pkgload::load_all()`), then start each process
with `pkgload::load_all(compile = FALSE)` so they don't race to rebuild the
Rust crates, and pick files with `test_dir(..., filter = )`:

```sh
# $1: filter regex on test names (file names without `test-`), $2: invert
run() { NOT_CRAN=true Rscript -e "pkgload::load_all(compile = FALSE); testthat::test_dir('tests/testthat', filter = '$1', invert = $2, load_package = 'none')"; }
ALOT_CORPUS='...' run '^corpus$' FALSE > corpus.log 2>&1 &
run '^corpus$' TRUE > rest.log 2>&1 &
wait
```

The full corpus (`test-corpus.R`, about 2,000 plots) is slow. Unless the
user asks for the full corpus, limit it with `ALOT_CORPUS`, a regex on the
file names in `tests/testthat/corpus/`, to a small subset (around ten files)
relevant to your change, e.g.
`ALOT_CORPUS='^(man-geom_point|man-geom_histogram|test-geom-bar|test-scales)\.R$'`.
Do not run the full corpus without user permission even if your change affects all plots.
The corpus may be regenerated on a ggplot2 update with `Rscript tools/extract-corpus.R`.

Benchmarks: see `.claude/skills/alot-bench/SKILL.md` (release build required).

After changing `#[extendr]` signatures, regenerate `R/extendr-wrappers.R`
with `rextendr::document()`.

## Architecture

- `src/rust/alot-core`: pure Rust algorithms with no R types, tested with
  `cargo test`.
- `src/rust/alot-r`: extendr glue only. It converts R vectors and calls
  `alot-core`.
- `R/ggplot2-internals.R`: wrappers (`gg_*`) for unexported ggplot2
  functions. Add new ones here rather than calling `:::` inline.

## Rules for kernels

1. **Fall back rather than guess.** Return `NULL` for any parameter, class,
   transform, palette or input type the kernel doesn't handle exactly.
   Partial support with fallback beats broad support with drift.
2. **Some work stays in R:**
   - character sorting and anything locale-dependent (sort the unique values
     only);
   - random draws (`runif` etc.), so seeds reproduce;
   - label formatting (`format()`);
   - O(k) work such as breaks, palettes and limits;
   - user-facing warnings and messages (Rust returns counts; R emits the
     text).
3. **Test against ggplot2, not hand-computed values.** Use
   `expect_build_equal(p)` from `helper-equivalence.R`. Cover NA, Inf,
   empty data, a single row, integer vs double, and multiple panels/groups.
   Also test that each unsupported case falls back, by checking
   `alot_coverage()` for `"ggplot2"`. See `test-scale-train.R` for the
   pattern.
4. **Snapshot every newly mirrored ggproto method** in `test-internals.R`.
5. **Apply the 1.25× rule.** Keep a kernel only if its step is at least 1.25×
   faster than ggplot2 at 1e6 rows. If it isn't, delete it and record why in
   `inst/bench/RESULTS.md`.
6. **Match ggplot2's types and attributes:** integer vs double, factor
   levels, `mapped_discrete`, and column order. `expect_equal` checks them.
7. **Pin `ggplot2 (>= 4.0.0, < 4.1.0)` and `ragg (>= 1.5.0, < 1.6.0)`.**
   Rendering mirrors ragg's internals, so a new ragg version means
   re-verifying it. Don't add code paths for other ggplot2 or ragg
   versions.

## Style

- Match the surrounding code. R files are small, with a short header comment
  saying what they mirror. Use base R plus rlang/vctrs and add no new
  Imports without a reason. Rust is plain and uses `Option<f64>` for NA in
  `alot-core`.
- One R file and one Rust module per kernel family (`kernels-stat.R`,
  `alot-core/src/stat/…`), so parallel tasks rarely touch the same file.

## Workflow and review

Work happens on local branches; there is no GitHub PR step.

- Work on one task per branch, named `task/<ID>-<slug>` (for example
  `task/T1.1-discrete-train`), in its own worktree when tasks run in
  parallel.
- Before handing over, `cargo test` and the full R test suite must pass. The
  corpus test must pass too, once it exists. Don't hand over with failing
  tests. If you are stuck, stop and say so.
- Hand over as a single commit on top of `main`. Rebase rather than merge,
  and don't merge into `main` yourself. The commit message body is the
  review note, using this layout:

  ```
  T1.1: Discrete position training kernel

  What: <1–3 lines>
  Supported / falls back: <what runs in Rust, what declines>
  Tests: <files added/changed; suites run and their result>
  Bench: <step time, ggplot2 vs alot, at 1e6 rows>
  Review focus: <where exactness is most at risk; any judgement calls>
  ```

- When a task is done, update its status in TASKS.md in the same commit.
- Commit as Claude Code, not as the machine's default git user (`Ubuntu`):
  run `git -c user.name="Claude Code" -c user.email=noreply@anthropic.com
  commit ...`, which sets both author and committer.
