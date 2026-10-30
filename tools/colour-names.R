# Writes src/rust/alot-core/src/colour/names.rs: R's named colours
# (grDevices::colors()) with their RGB values, for parsing colour names in
# Rust (R3.2). farver's decode_colour(), which scales::alpha() uses, gives
# the same values for every name (checked here). Run from the repo root:
#   Rscript tools/colour-names.R
names <- grDevices::colors()
rgb <- grDevices::col2rgb(names)
stopifnot(
  identical(names, tolower(gsub(" ", "", names))),
  all(t(farver::decode_colour(names)) == rgb)
)
o <- order(names, method = "radix")
rows <- sprintf("    (b\"%s\", [%d, %d, %d]),", names[o], rgb[1, o], rgb[2, o], rgb[3, o])
writeLines(c(
  "//! R's named colours (`grDevices::colors()`), sorted by name, generated",
  "//! by tools/colour-names.R. farver's `decode_colour()` gives the same RGB",
  "//! for each.",
  "",
  sprintf("pub const NAMES: [(&[u8], [u8; 3]); %d] = [", length(names)),
  rows,
  "];"
), "src/rust/alot-core/src/colour/names.rs")
