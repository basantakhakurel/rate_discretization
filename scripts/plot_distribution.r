library(ggplot2)
library(dplyr)
library(tidyr)
library(purrr)
library(patchwork) # For arranging plots
library(extrafont)
library(pilot)

set_pilot_family(family = "Bookman Old Style")
# Parameters
alpha <- 0.5 # Shape for gamma
meanlog <- 0 # Mean for lognormal
sdlog <- 1 # SD for lognormal
k_values <- 2:8

set.seed(33)

# Helper to get discrete categories from continuous distribution
discretize_distribution <- function(dist, k, n = 10000) {
  x <- if (dist == "gamma") {
    rgamma(n, shape = alpha, rate = alpha) # mean = 1
  } else {
    rlnorm(n, meanlog = meanlog, sdlog = sdlog)
  }

  breaks <- quantile(x, probs = seq(0, 1, length.out = k + 1))
  categories <- cut(x, breaks = breaks, include.lowest = TRUE)
  weights <- as.numeric(table(categories)) / length(x)
  centers <- tapply(x, categories, mean)

  tibble(center = centers, weight = weights)
}

# Helper to make one row of plots
make_plots_for_k <- function(k) {
  gamma_df <- discretize_distribution("gamma", k)
  lnorm_df <- discretize_distribution("lnorm", k)

  x_grid <- seq(0, 5, length.out = 500)

  gamma_plot <- ggplot() +
    stat_function(fun = dgamma, args = list(shape = alpha, rate = alpha), size = 1) +
    geom_segment(data = gamma_df, aes(x = center, xend = center, y = 0, yend = weight), color = "blue") +
    ggtitle(paste("Gamma (k =", k, ")")) +
    xlim(0, 5) +
    ylim(0, 1) +
    theme_pilot()

  lnorm_plot <- ggplot() +
    stat_function(fun = dlnorm, args = list(meanlog = meanlog, sdlog = sdlog), size = 1) +
    geom_segment(data = lnorm_df, aes(x = center, xend = center, y = 0, yend = weight), color = "red") +
    ggtitle(paste("Lognormal (k =", k, ")")) +
    xlim(0, 5) +
    ylim(0, 1) +
    theme_pilot()

  gamma_plot + lnorm_plot
}

# Combine all rows
all_plots <- map(k_values, make_plots_for_k)
final_plot <- wrap_plots(all_plots, ncol = 1)

ggsave("Plots/dist_plot_2.pdf", plot = plot, device = cairo_pdf, width = 10, height = 20, dpi = 450, limitsize = FALSE, create.dir = TRUE, bg = "white")
