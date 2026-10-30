# Batched labeling::extended() (labeling 0.4.3), the algorithm behind
# scales::extended_breaks(), with its default Q, w and only.loose. Rust
# computes the breaks for every range at once; ranges where R would raise
# an error or warning come back NULL and run labeling::extended() itself.
extended_breaks_batch <- function(dmin, dmax, m) {
  n <- length(dmin)
  dmax <- rep_len(as.double(dmax), n)
  m <- rep_len(as.double(m), n)
  out <- rs_extended_breaks(as.double(dmin), dmax, m)
  for (i in which(vapply(out, is.null, logical(1)))) {
    out[i] <- list(labeling::extended(dmin[[i]], dmax[[i]], m[[i]]))
  }
  out
}
