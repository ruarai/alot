# Written by hand for alot (B1): faceted steps and ECDFs, which reuse group
# IDs across panels. Kept by tools/extract-corpus.R.

corpus_block("alot-facet-steps", {
  steps <- data.frame(
    x = rep(c(1, 2, 4, 5, 7, 8), 4),
    y = c(1:6, 3:8, 101:106, 104:109) + rep(c(0, 0, 50, 50), each = 6),
    g = rep(c("a", "b"), each = 6, times = 2),
    f = rep(c("p", "q"), each = 12),
    h = rep(c("u", "v", "u", "v"), each = 6)
  )
  .plot("alot-facet-steps #1", ggplot(steps, aes(x, y, colour = g)) + geom_step() + facet_wrap(vars(f)))
  .plot("alot-facet-steps #2", ggplot(steps, aes(x, y, colour = g)) + geom_step(direction = "vh") +
    facet_wrap(vars(f), scales = "free_y"))
  .plot("alot-facet-steps #3", ggplot(steps, aes(x, y, colour = g)) + geom_step(direction = "mid") +
    facet_grid(rows = vars(f)))
  .plot("alot-facet-steps #4", ggplot(steps, aes(y, x, colour = g)) + geom_step(orientation = "y") +
    facet_wrap(vars(f), scales = "free"))
  .plot("alot-facet-steps #5", ggplot(steps, aes(x, y)) + geom_step() + facet_grid(vars(f), vars(h)))
  .plot("alot-facet-steps #6", ggplot(steps, aes(y, colour = g)) + stat_ecdf() + facet_wrap(vars(f), scales = "free_x"))
  .plot("alot-facet-steps #7", ggplot(steps, aes(y)) + stat_ecdf(pad = FALSE) + facet_grid(vars(f), vars(h)))
})
