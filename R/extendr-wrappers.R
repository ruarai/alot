# R wrappers for Rust functions registered in src/rust/alot-r/src/lib.rs.

rs_train_continuous_grouped <- function(x, scale_id, existing) {
  .Call(wrap__train_continuous_grouped, x, scale_id, existing)
}
