# Pairs plot for README.md: an MCMC pairs plot of 13 parameters (1.2 million
# points), drawn with alot_png() and timed against ggsave() on ragg.
#
#   Rscript tools/readme-pairs.R
#
# Run from the repo root, with a release build installed or compiled. The
# package is loaded with helpers = FALSE: the test helpers set
# options(alot.full_tier = FALSE), which would hide the full render tier.

suppressMessages(pkgload::load_all(compile = FALSE, helpers = FALSE, quiet = TRUE))
library(ggplot2)
set.seed(1)

# Simulated posterior: 4 chains x 4,000 draws of 13 parameters.
# theta[1] funnels in log(tau); the betas track mu; the sigmas trade off with tau.
n_chain <- 4; n_iter <- 4000; n <- n_chain * n_iter
log_tau <- rnorm(n, 0.3, 0.6)
mu      <- rnorm(n, 4.4, 1.1)
draws <- data.frame(
  chain      = factor(rep(seq_len(n_chain), each = n_iter)),
  mu         = mu,
  `log(tau)` = log_tau,
  `theta[1]` = mu + exp(log_tau) * rnorm(n),
  beta1       = 0.7 * mu + rnorm(n, 0, 0.3),
  beta2       = 0.3 * mu + rnorm(n, 0, 0.2),
  beta3       = 0.5 * mu + rnorm(n, 0, 0.6),
  beta4       = 0.9 * mu + rnorm(n, 0, 1.3),
  beta5       = 1.2 * mu + rnorm(n, 0, 0.2),
  sigma1      = exp(rnorm(n, 1.4 - 0.2 * log_tau, 0.1)),
  sigma2      = exp(rnorm(n, 1.5 - 0.1 * log_tau, 0.1)),
  sigma3      = exp(rnorm(n, 1.6 - 0.3 * log_tau, 0.1)),
  sigma4      = exp(rnorm(n, 1.7 - 0.4 * log_tau, 0.1)),
  check.names = FALSE
)
pars <- setdiff(names(draws), "chain")
lv <- factor(pars, levels = pars)

# Off-diagonal panels: chains 1-2 below the diagonal, chains 3-4 above
grid <- subset(expand.grid(i = seq_along(pars), j = seq_along(pars)), i != j)
off <- do.call(rbind, Map(function(i, j) {
  d <- draws[draws$chain %in% (if (i > j) 1:2 else 3:4), ]
  data.frame(chain = d$chain, x = d[[pars[j]]], y = d[[pars[i]]],
             xvar = lv[j], yvar = lv[i])
}, grid$i, grid$j))
off <- off[sample(nrow(off)), ]  # interleave chains so neither hides the other

# Diagonal panels: per-chain kernel densities, rescaled to the panel's y range
dens <- do.call(rbind, lapply(seq_along(pars), function(i) {
  v <- draws[[pars[i]]]; r <- range(v)
  d <- do.call(rbind, lapply(split(v, draws$chain), function(vc) {
    k <- density(vc, from = r[1], to = r[2], n = 256)
    data.frame(x = k$x, dens = k$y)
  }))
  d$chain <- factor(rep(levels(draws$chain), each = 256))
  d$y <- r[1] + d$dens / max(d$dens) * diff(r) * 0.95
  transform(d, xvar = lv[i], yvar = lv[i])
}))

p <- ggplot(mapping = aes(x, y, colour = chain)) +
  geom_point(data = off, size = 0.2, alpha = 0.05, shape = 16) +
  geom_line(data = dens, linewidth = 0.6) +
  facet_grid(yvar ~ xvar, scales = "free", switch = "both") +
  scale_colour_manual(values = c("#1b4f72", "#5dade2", "#a04000", "#f5b041")) +
  guides(colour = guide_legend(override.aes = list(size = 3, alpha = 1, linewidth = 1))) +
  labs(x = NULL, y = NULL, colour = "Chain",
       title = "Posterior pairs plot") +
  scale_x_continuous(breaks = scales::breaks_extended(3)) +
  scale_y_continuous(breaks = scales::breaks_extended(3)) +
  theme_bw(base_size = 11) +
  theme(strip.placement = "outside", strip.background = element_blank(),
        strip.text = element_text(size = 11), panel.grid.minor = element_blank(),
        strip.text.y.left = element_text(angle = 0),
        panel.spacing = unit(8, "pt"), legend.position = "bottom")

stopifnot(alot_render_coverage(p)$tier == "full")

# Time ggplot -> PNG, interleaved, and report medians
size <- list(width = 1600, height = 1700, units = "px", dpi = 150)
tmp <- tempfile(fileext = ".png")
times <- replicate(3, c(
  ggsave = system.time(do.call(ggsave, c(list(tmp, p, device = ragg::agg_png), size)))[["elapsed"]],
  alot_png = system.time(do.call(alot_png, c(list(p, tmp), size)))[["elapsed"]]
))
med <- apply(times, 1, median)
cat(sprintf("ggsave() with ragg: %.2f s\nalot_png(): %.2f s\nspeedup: %.1fx\n",
            med[["ggsave"]], med[["alot_png"]], med[["ggsave"]] / med[["alot_png"]]))

do.call(alot_png, c(list(p, "man/figures/readme-pairs.png"), size))
