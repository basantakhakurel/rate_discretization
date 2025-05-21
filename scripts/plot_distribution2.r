library(ggplot2)
library(dplyr)
library(tidyr)
library(extrafont)
library(pilot)

set_pilot_family(family = "Bookman Old Style")

# alpha for gamma distribution
alpha <- 0.5

# parameters for lognormal distribution
meanlog <- 0
sdlog <- 1

# number of discrete rate categories
k_values <- 2:8

# number of samples for quantile calculation
n_samples <- 100000

# Labels for facets
g_label <- paste0("Gamma (alpha=", alpha, ")")
ln_label <- paste0("Lognormal (meanlog=", meanlog, ", sdlog=", sdlog, ")")

# --- Generate PDFs ---
g_x <- seq(qgamma(0.0001, shape = alpha, rate = alpha), qgamma(0.9999, shape = alpha, rate = alpha), length.out = 300)
ln_x <- seq(qlnorm(0.0001, meanlog = meanlog, sdlog = sdlog), qlnorm(0.9999, meanlog = meanlog, sdlog = sdlog), length.out = 300)

df_pdf <- bind_rows(
  data.frame(x_pdf = g_x, y_pdf = dgamma(g_x, shape = alpha, rate = alpha), dist = g_label),
  data.frame(x_pdf = ln_x, y_pdf = dlnorm(ln_x, meanlog = meanlog, sdlog = sdlog), dist = ln_label)
) %>% crossing(k = k_values)

# --- Generate quantiles and category means using sampling ---
set.seed(33)
g_samples <- rgamma(n_samples, shape = alpha, rate = alpha)
ln_samples <- rlnorm(n_samples, meanlog = meanlog, sdlog = sdlog)

# Store data frames
df_points_list <- list()
df_vlines_list <- list()

for (k in k_values) {
  probs <- seq(0, 1, length.out = k + 1)

  # Gamma
  g_qs <- quantile(g_samples, probs)
  g_cats <- cut(g_samples, breaks = g_qs, include.lowest = TRUE, right = FALSE)
  g_means <- tapply(g_samples, g_cats, mean)
  g_weights <- prop.table(table(g_cats))
  df_points_list[[length(df_points_list) + 1]] <- data.frame(
    k = k,
    dist = g_label,
    x_point = g_means,
    y_point = as.numeric(g_weights)
  )
  if (k > 1) {
    df_vlines_list[[length(df_vlines_list) + 1]] <- data.frame(
      k = k,
      dist = g_label,
      xintercept = g_qs[-c(1, length(g_qs))]
    )
  }

  # Lognormal
  ln_qs <- quantile(ln_samples, probs)
  ln_cats <- cut(ln_samples, breaks = ln_qs, include.lowest = TRUE, right = FALSE)
  ln_means <- tapply(ln_samples, ln_cats, mean)
  ln_weights <- prop.table(table(ln_cats))
  df_points_list[[length(df_points_list) + 1]] <- data.frame(
    k = k,
    dist = ln_label,
    x_point = ln_means,
    y_point = as.numeric(ln_weights)
  )
  if (k > 1) {
    df_vlines_list[[length(df_vlines_list) + 1]] <- data.frame(
      k = k,
      dist = ln_label,
      xintercept = ln_qs[-c(1, length(ln_qs))]
    )
  }
}

df_points <- bind_rows(df_points_list)
df_vlines <- bind_rows(df_vlines_list)

# --- Convert factors for facet ordering ---
dist_order <- c(g_label, ln_label)
df_pdf$dist <- factor(df_pdf$dist, levels = dist_order)
df_points$dist <- factor(df_points$dist, levels = dist_order)
df_vlines$dist <- factor(df_vlines$dist, levels = dist_order)

# --- Plot ---
plot <- ggplot() +
  # PDF curve
  geom_line(data = df_pdf, aes(x = x_pdf, y = y_pdf), color = "black") +
  # Quantile lines (discrete category segments)
  geom_vline(data = df_vlines, aes(xintercept = xintercept), linetype = "dashed", color = "grey50") +
  # Category medians
  geom_point(data = df_points, aes(x = x_point, y = y_point), color = "blue", size = 1.5, alpha = 0.7) +
  facet_grid(k ~ dist, scales = "free_x") +
  xlim(0, 10) +
  ylim(0, 1) +
  labs(
    title = "Discretized Gamma and Lognormal Distributions",
    x = "Values",
    y = "Density"
  ) +
  theme_pilot() #+
# theme(
# strip.text = element_text(size = 8),
# plot.title = element_text(hjust = 0.5),
# plot.subtitle = element_text(hjust = 0.5, size = 9)
# )

ggsave("Plots/dist_plot_1.pdf", plot = plot, device = cairo_pdf, width = 8, height = 10, dpi = 450, limitsize = FALSE, create.dir = TRUE, bg = "white")
