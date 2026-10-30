---
name: alot-bench
description: Run alot's benchmarks or a new kernel's 1.25× speed check (release build, sequential runs)
---

Benchmarks (`inst/bench/`, see `RESULTS.md`) need a release build:
`pkgload::load_all()` builds debug Rust, so first run
`pkgbuild::compile_dll(force = TRUE, debug = FALSE)`, then
`pkgload::load_all(compile = FALSE)`. The suites run in parallel by default,
which is fine for a quick overview. A new kernel's 1.25× check must run
sequentially (`ALOT_BENCH_CORES=1`) with ggplot2 and alot reps interleaved.
