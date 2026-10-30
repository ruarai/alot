# Batched labeling::extended() (T5.2). The breaks must be identical to
# labeling's, and every range Rust declines must be one where labeling
# raises an error or warning.

# R's reference: the breaks, or "error"/"warning".
extended_ref <- function(dmin, dmax, m) {
  lapply(seq_along(dmin), function(i) {
    tryCatch(
      labeling::extended(dmin[i], dmax[i], m[i]),
      error = function(e) "error", warning = function(w) "warning"
    )
  })
}

expect_extended_identical <- function(dmin, dmax, m) {
  got <- rs_extended_breaks(dmin, dmax, m)
  ref <- extended_ref(dmin, dmax, m)
  declined <- vapply(got, is.null, logical(1))
  expect_identical(got[!declined], ref[!declined])
  expect_true(all(vapply(ref[declined], is.character, logical(1))))
  invisible(declined)
}

test_that("breaks equal labeling::extended() on 1e5 random ranges", {
  skip_on_cran()
  set.seed(1)
  n <- 1e5
  kind <- sample(1:6, n, TRUE)
  width <- ifelse(kind == 1, 10^runif(n, -15, 15),     # general
           ifelse(kind == 2, 10^runif(n, -16, -12),    # around the eps cut-off
           ifelse(kind == 3, 10^runif(n, 150, 308),    # beyond sqrt(xmax)
           ifelse(kind == 4, sample(1:200, n, TRUE),   # integer widths
           ifelse(kind == 5, runif(n), 10^runif(n, -3, 3))))))
  # Centred on zero, or offset by up to 1e10 either side; offsets far
  # beyond the width make %% warn, which Rust leaves to R.
  centre <- ifelse(kind == 6, 0, sample(c(-1, 1), n, TRUE) * 10^runif(n, -10, 10) * (runif(n) < 0.8))
  dmin <- ifelse(kind == 4, round(centre), centre) - width * runif(n)
  dmax <- pmin(dmin + width, .Machine$double.xmax)
  m <- sample(c(1:12, 2.5), n, TRUE, prob = c(1, 2, 3, 4, 20, 3, 3, 2, 2, 2, 1, 1, 1))
  # Swapped bounds.
  swap <- runif(n) < 0.1
  tmp <- dmin[swap]
  dmin[swap] <- dmax[swap]
  dmax[swap] <- tmp

  declined <- expect_extended_identical(dmin, dmax, m)
  expect_lt(mean(declined), 0.05)
})

test_that("degenerate, tiny, huge and negative ranges match", {
  xmax <- .Machine$double.xmax
  eps <- .Machine$double.eps * 100
  cases <- rbind(
    c(0, 0, 5), c(1, 1, 5), c(1, 1, 2), c(1, 1, 1), c(1, 1, 2.5),
    c(1, 1 + eps / 2, 5), c(1, 1 + eps * 2, 5), c(0, eps, 5), c(-eps, 0, 5),
    c(-xmax, xmax, 5), c(-xmax / 2, xmax / 2, 5), c(0, sqrt(xmax) * 2, 5), c(-1e300, -1e299, 5),
    c(1e-300, 2e-300, 5), c(-1e-200, 1e-200, 4),
    c(-10, -1, 5), c(-1, 1, 5), c(-3.2, 7.9, 5), c(0.1, 0.3, 5), c(0.1 + 0.2, 0.9, 7),
    c(1, 0, 5), c(-5, -50, 3),
    c(1e15, 1e15 + 10, 5), c(4.5e15, 4.5e15 + 1, 5),
    c(0, 1, 1), c(0, 1, 1.5),
    c(NA, 1, 5), c(0, NaN, 5), c(0, Inf, 5), c(-Inf, 0, 5), c(0, 1, NA)
  )
  expect_extended_identical(cases[, 1], cases[, 2], cases[, 3])
  # labeling::extended() never returns for m < 1 on a non-degenerate range;
  # Rust declines rather than loop.
  expect_identical(rs_extended_breaks(c(0, 0), c(1, 1), c(0.5, -1)), list(NULL, NULL))
})

test_that("breaks equal scales::extended_breaks() on realistic data ranges", {
  set.seed(2)
  ranges <- t(replicate(2000, range(stats::rnorm(sample(2:50, 1), runif(1, -1e4, 1e4), 10^runif(1, -4, 4)))))
  m <- rep(5, nrow(ranges))
  got <- rs_extended_breaks(ranges[, 1], ranges[, 2], m)
  ref <- lapply(seq_len(nrow(ranges)), function(i) scales::extended_breaks()(ranges[i, ]))
  expect_identical(got, ref)
})

test_that("extended_breaks_batch() runs labeling for declined ranges", {
  # m = 1 makes labeling error; NA input too.
  expect_identical(
    extended_breaks_batch(c(0, 1), c(10, 1), c(5, 2)),
    list(labeling::extended(0, 10, 5), labeling::extended(1, 1, 2))
  )
  expect_identical(
    tryCatch(extended_breaks_batch(0, 1, 1), error = conditionMessage),
    tryCatch(labeling::extended(0, 1, 1), error = conditionMessage)
  )
  expect_identical(
    tryCatch(extended_breaks_batch(NA_real_, 1, 5), error = conditionMessage),
    tryCatch(labeling::extended(NA_real_, 1, 5), error = conditionMessage)
  )
  # A zero-width range with m = 0 gives integer(0), which Rust leaves to R.
  expect_identical(
    extended_breaks_batch(c(1, 0), c(1, 10), c(0, 5)),
    list(labeling::extended(1, 1, 0), labeling::extended(0, 10, 5))
  )
  expect_identical(extended_breaks_batch(numeric(), numeric(), numeric()), list())
})

test_that("R's %% is reproduced bit for bit", {
  set.seed(3)
  # lmin %% lstep as extended() computes it.
  start <- sample(-40:40, 1e5, TRUE)
  step <- 10^sample(-16:8, 1e5, TRUE) * sample(c(1, 2, 2.5, 3, 4, 5), 1e5, TRUE)
  x <- start * (step / sample(1:12, 1e5, TRUE))
  expect_identical(rs_r_mod(x, step), x %% step)
  # Arbitrary pairs; NA exactly where R warns about lost accuracy.
  x <- runif(1e5, -1e6, 1e6) * 10^sample(c(0, 0, 13), 1e5, TRUE)
  y <- 10^runif(1e5, -10, 3)
  got <- rs_r_mod(x, y)
  lossy <- abs(x / y) > 2^63
  expect_identical(is.na(got), lossy)
  expect_identical(got[!lossy], x[!lossy] %% y[!lossy])
})
