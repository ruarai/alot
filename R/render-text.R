# String metrics as grid sees them on a ragg device (PHASE2.md, Architecture
# 4). R resolves family and face to font files once per distinct style, as
# ragg's TextRenderer::load_font() does through systemfonts (ragg
# src/text_renderer.h); Rust measures (alot-core/src/render/text.rs).

# Font file and face index for each family/face, NA where alot doesn't
# mirror ragg: the symbol face (5), and fonts with OpenType features or
# variations (textshaping would apply them). Faces 2 and 4 are bold, 3 and 4
# italic.
text_fonts <- function(family, face) {
  style <- vctrs::vec_unique(data.frame(family = family, face = as.integer(face)))
  ok <- !is.na(style$family) & style$face %in% 1:4
  font <- data.frame(path = rep(NA_character_, nrow(style)), index = NA_integer_)
  if (any(ok)) {
    s <- style[ok, ]
    m <- systemfonts::match_fonts(
      s$family,
      italic = s$face %in% c(3L, 4L),
      weight = ifelse(s$face %in% c(2L, 4L), "bold", "normal")
    )
    plain <- lengths(m$features) == 0 & lengths(m$variations) == 0
    font$path[ok] <- ifelse(plain, m$path, NA_character_)
    font$index[ok] <- m$index
  }
  font[vctrs::vec_match(data.frame(family = family, face = as.integer(face)), style), ]
}

# Metrics in device pixels of each string, as GEStrWidth(), GEStrMetric()
# and GEStrHeight() (R src/main/engine.c) report them on a ragg device of
# resolution `res`, `scaling` and `pointsize`: a data frame of `width`,
# `ascent`, `descent` and `height`, NA where alot would defer to ragg (see
# rs_text_metrics()). Arguments recycle to the length of `text`.
text_metrics <- function(text, family = "", face = 1L, fontsize = 12, cex = 1,
                         lineheight = 1.2, res = 72, scaling = 1,
                         pointsize = 12) {
  n <- length(text)
  args <- vctrs::vec_recycle_common(
    family = family, face = face, fontsize = fontsize, cex = cex,
    lineheight = lineheight, .size = n
  )
  font <- text_fonts(args$family, args$face)
  key <- vctrs::vec_group_id(font)
  first <- !duplicated(key)
  # ragg's res_mod, its stringWidth() and metricInfo() size (ps * cex *
  # res_mod) and GEStrHeight()'s line height (lineheight * cex * cra[1] *
  # ps / startps, with cra[1] = 1.2 * pointsize * res_mod).
  res_mod <- scaling * res / 72
  size <- args$fontsize * args$cex * res_mod
  line <- args$lineheight * args$cex * (1.2 * pointsize * res_mod) *
    args$fontsize / pointsize
  out <- rs_text_metrics(
    enc2utf8(as.character(text)), as.integer(key),
    font$path[first][order(key[first])], font$index[first][order(key[first])],
    as.double(size), as.double(line)
  )
  as.data.frame(out)
}

# The tier text limits a plot to: "full" if alot measures every string as
# ragg does, "hybrid" if any needs ragg (a glyph missing from its font,
# which ragg would draw from a fallback font, or a font alot doesn't
# mirror).
text_tier <- function(text, family = "", face = 1L) {
  m <- text_metrics(text, family, face)
  if (anyNA(m$width[!is.na(text)])) "hybrid" else "full"
}
