# Trajectories plot for README.md: a forecast ensemble of 4,500 geom_line()
# trajectories (1.8 million rows) across 9 facets, drawn with alot_png() and
# timed against ggsave() on ragg.
#
#   Rscript tools/readme-trajectories.R
#
# Run from the repo root, with a release build installed or compiled. The
# package is loaded with helpers = FALSE: the test helpers set
# options(alot.full_tier = FALSE), which would hide the full render tier.

suppressMessages(pkgload::load_all(compile = FALSE, helpers = FALSE, quiet = TRUE))
library(ggplot2)
set.seed(2)

# Simulated epidemic forecast ensemble: for each of 9 regions, 500 stochastic
# trajectories of daily cases over 400 days of recurring waves, fitted to the
# first year of observed counts and projected forward with a drifting growth
# rate.
regions <- c("A", "B", "C", "D", "E", "F", "G", "H", "I")
n_sim <- 500; n_day <- 400; fit_days <- 365
dates <- as.Date("2025-01-01") + seq_len(n_day) - 1

sims <- do.call(rbind, lapply(seq_along(regions), function(k) {
  period <- runif(1, 150, 200)        # days between wave peaks
  phase <- runif(1, 0, 2 * pi)
  base <- 0.035 * sin(2 * pi * seq_len(n_day) / period + phase)
  sd <- ifelse(seq_len(n_day) < fit_days, 0.00005, 0.0015)
  r <- matrix(base, n_day, n_sim) + rep(rnorm(n_sim, 0, 0.0004), each = n_day) +
    apply(matrix(rnorm(n_day * n_sim, 0, sd), n_day), 2, cumsum)
  log_inc <- log(runif(1, 200, 600)) + apply(r, 2, cumsum)
  data.frame(
    region = regions[k],
    sim = rep(seq_len(n_sim), each = n_day),
    date = rep(dates, n_sim),
    cases = as.vector(exp(log_inc))
  )
}))
sims$region <- factor(sims$region, levels = regions)
sims$group <- interaction(sims$region, sims$sim)

# Ensemble median, and the observed counts up to the forecast date
med <- aggregate(cases ~ region + date, sims, median)
obs <- subset(med, date < dates[fit_days])
obs$cases <- rpois(nrow(obs), obs$cases * exp(rnorm(nrow(obs), 0, 0.15)))

p <- ggplot(sims, aes(date, cases)) +
  geom_line(aes(group = group), colour = "#3b6ea8", alpha = 0.04, linewidth = 0.3) +
  geom_vline(xintercept = dates[fit_days], linetype = "dashed", colour = "grey40") +
  geom_point(data = obs, size = 0.3, stroke = 0.3, colour = "black") +
  facet_wrap(~region, ncol = 3) +
  scale_y_log10(labels = scales::label_comma()) +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  labs(x = NULL, y = "Count") +
  theme_bw(base_size = 11) +
  theme(panel.grid.minor = element_blank(), strip.background = element_blank(),
        strip.text = element_text(hjust = 0, face = "bold"))

stopifnot(alot_render_coverage(p)$tier == "full")

# Time ggplot -> PNG, interleaved, and report medians
size <- list(width = 1600, height = 1400, units = "px", dpi = 150)
tmp <- tempfile(fileext = ".png")
times <- replicate(3, c(
  ggsave = system.time(do.call(ggsave, c(list(tmp, p, device = ragg::agg_png), size)))[["elapsed"]],
  alot_png = system.time(do.call(alot_png, c(list(p, tmp), size)))[["elapsed"]]
))
secs <- apply(times, 1, median)
cat(sprintf("ggsave() with ragg: %.2f s\nalot_png(): %.2f s\nspeedup: %.1fx\n",
            secs[["ggsave"]], secs[["alot_png"]], secs[["ggsave"]] / secs[["alot_png"]]))

do.call(alot_png, c(list(p, "man/figures/readme-trajectories.png"), size))
