# The Rust port of farver's Lab <-> sRGB conversion and hex encoding
# (alot_core::colour) against farver itself, string for string.

white <- farver::as_white_ref("D65")

rs_encode <- function(lab, alpha = NULL) {
  rs_encode_lab(as.double(lab), alpha, white)
}

fv_encode <- function(lab, alpha = NULL) {
  unname(farver::encode_colour(lab, alpha = alpha, from = "lab"))
}

expect_encode_equal <- function(lab, alpha = NULL) {
  expect_identical(rs_encode(lab, alpha), fv_encode(lab, alpha))
}

test_that("D65 matches as_white_ref()", {
  expect_identical(unname(white), c(95.042854537718071, 100, 108.890037079812814))
})

test_that("a dense Lab grid encodes as farver does", {
  lab <- as.matrix(expand.grid(
    l = seq(-5, 105, by = 1),
    a = seq(-128, 128, by = 4),
    b = seq(-128, 128, by = 4)
  ))
  expect_encode_equal(lab)
})

test_that("random Lab and converted RGB encode as farver does", {
  set.seed(1)
  n <- 2e5
  lab <- cbind(runif(n, -10, 110), runif(n, -150, 150), runif(n, -150, 150))
  expect_encode_equal(lab)

  # Lab of in-gamut colours, which land on or near channel rounding
  # boundaries: half-integer and integer RGB.
  rgb <- cbind(runif(n, 0, 255), runif(n, 0, 255), runif(n, 0, 255))
  rgb <- rbind(rgb, round(rgb), floor(rgb) + 0.5)
  expect_encode_equal(farver::convert_colour(rgb, "rgb", "lab"))

  # The colour_ramp() path: palette colours decoded to Lab.
  hex <- grDevices::rgb(rgb[seq_len(1e4), ] %/% 1, maxColorValue = 255)
  expect_encode_equal(farver::decode_colour(hex, to = "lab"))
})

test_that("invalid and extreme Lab values match, NA giving NA", {
  lab <- cbind(
    c(NA, NaN, Inf, -Inf, 50, 50, 50, 50, 50, 50, 50, -1e300, 1e300, 0, 100),
    c(0, 0, 0, 0, NA, Inf, 1e100, -1e100, 1e300, 1e154, 0, 0, 0, 0, 0),
    c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -Inf, 0, 0, 1e-300, -1e-300)
  )
  expect_encode_equal(lab)
  expect_true(all(is.na(rs_encode(lab[1:6, ]))))
  expect_identical(rs_encode(matrix(numeric(), 0, 3)), character())

  # Integer input, as farver's integer path sees it.
  lab_i <- cbind(c(NA, 0L, 50L, 100L, 120L), c(0L, 20L, NA, -60L, 0L), c(0L, -20L, 0L, 80L, 0L))
  expect_identical(rs_encode(lab_i), fv_encode(lab_i))
})

test_that("alpha is encoded as farver does", {
  set.seed(2)
  lab <- cbind(runif(50, 0, 100), runif(50, -80, 80), runif(50, -80, 80))
  lab[3, ] <- NA

  # A single alpha: NA and 1 / 255 drop the suffix; 1 keeps `FF`.
  for (a in list(NULL, numeric(), 1, 0, 0.5, 1 / 255, 2 / 255, NA_real_, NaN, Inf, -Inf, -1, 7)) {
    expect_encode_equal(lab, a)
  }
  expect_encode_equal(lab[1, , drop = FALSE], 0.25)

  # Per-row alpha: 255 drops the suffix; NA is opaque but NaN is `00`.
  a <- c(runif(40), 1, 0, NA, NaN, Inf, -Inf, 0.5 / 255, 1.5 / 255, 254.5 / 255, 1e10)
  expect_encode_equal(lab, a)
  expect_encode_equal(lab, a[1:7])
  expect_encode_equal(lab, c(a, 0.3))
  expect_encode_equal(lab[1:2, ], c(1, 1))
})

test_that("RGB to Lab matches convert_colour() and decode_colour()", {
  set.seed(3)
  n <- 1e5
  rgb <- cbind(runif(n, -20, 275), runif(n, -20, 275), runif(n, -20, 275))
  rgb <- rbind(rgb, c(NA, 0, 0), c(0, Inf, 0), c(0, 0, -Inf), c(255, 255, 255), c(0, 0, 0))
  as_lab <- function(x, cap) matrix(rs_rgb_to_lab(as.double(x), white, cap), ncol = 3)

  # Rust's cbrt (compiler_builtins) is not glibc's, so Lab can differ in
  # the last bits; the hex strings above are unaffected (Lab -> RGB uses
  # no cbrt).
  expected <- unname(farver::convert_colour(rgb, "rgb", "lab"))
  expect_equal(as_lab(rgb, cap = TRUE), expected, tolerance = 1e-8)

  # decode_colour() does not cap L, which white takes just over 100.
  int <- floor(rgb[seq_len(1e4), ]) %% 256
  int <- rbind(int, c(255, 255, 255))
  hex <- grDevices::rgb(int, maxColorValue = 255)
  expected <- unname(farver::decode_colour(hex, to = "lab"))
  dimnames(expected) <- NULL
  got <- as_lab(int, cap = FALSE)
  expect_equal(got, expected, tolerance = 1e-8)
  expect_gt(got[nrow(got), 1], 100)
})
