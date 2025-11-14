# R script to plot discrete gamma rates
# This script plots discrete gamma rates for various k values both using mean and the median approach.
# Authors: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# date: 2025-08-20

library(ggplot2)
library(dplyr)
library(purrr)
library(extrafont)
library(pilot)
library(patchwork)

set_pilot_family(family = "Montserrat")
set.seed(33)
# alpha <- 3.3582
# alpha <- 1.1168
alpha <- 2.5
k_values <- c(1, 3, 9)

# generate data for mean
make_mean_data <- function(k_values, alpha) {
  map_dfr(k_values, ~ {
    quants <- qgamma((1:(.x - 1)) / .x, shape = alpha, rate = alpha)
    rates <- if (.x == 1) 1 else diff(c(0, pgamma(quants * alpha, shape = alpha + 1), 1)) * .x
    tibble(center = rates, k = .x)
  }) %>%
    mutate(density = dgamma(center, shape = alpha, rate = alpha))
}

# generate data for median with status (shared/unique)
make_median_data_with_status <- function(method, k_values, alpha) {
  get_prior_midpoints <- function(current_k, all_ks) {
    smaller_ks <- all_ks[all_ks < current_k]
    if (length(smaller_ks) == 0) {
      return(numeric(0))
    }
    unlist(map(smaller_ks, ~ (0:(. - 1)) / . + 1 / (2 * .)))
  }

  map_dfr(k_values, ~ {
    current_k <- .x
    midpoints <- (0:(current_k - 1)) / current_k + 1 / (2 * current_k)
    prior_midpoints <- get_prior_midpoints(current_k, k_values)

    status <- if (current_k == 1) {
      rep("Shared", length(midpoints))
    } else {
      if_else(round(midpoints, 6) %in% round(prior_midpoints, 6), "Shared", "Unique")
    }

    rates <- qgamma(midpoints, shape = alpha, rate = alpha)

    if (method == "normalized") {
      rates <- rates / mean(rates)
    }

    tibble(
      center = rates,
      k = current_k,
      density = dgamma(rates, shape = alpha, rate = alpha),
      status = factor(status, levels = c("Shared", "Unique"))
    )
  })
}

# Generate data for all plots
all_discretizations_mean <- make_mean_data(k_values, alpha)
all_discretizations_median <- make_median_data_with_status("normalized", k_values, alpha)
all_discretizations_median_unnormalized <- make_median_data_with_status("unnormalized", k_values, alpha)

# plotting function for median
make_faceted_plot_median <- function(data, title) {
  ggplot(data) +
    stat_function(fun = dgamma, args = list(shape = alpha, rate = alpha), linewidth = 1, color = "#2c3e50") +
    geom_segment(aes(x = center, xend = center, y = density, yend = 0, linetype = status), color = "#e74c3c", linewidth = 1) +
    geom_point(aes(x = center, y = density), color = "#8e44ad", size = 2.0) +
    facet_wrap(~k, ncol = 1, labeller = labeller(k = function(x) paste0("k = ", x))) +
    scale_linetype_manual(
      name = "Rate Type",
      values = c("Shared" = "solid", "Unique" = "dotted")
    ) +
    scale_x_continuous(limits = c(0, 3.5), expand = c(0.02, 0)) +
    scale_y_continuous(limits = c(0, NA), expand = c(0.02, 0)) +
    labs(title = title, x = "rate", y = "") +
    theme_pilot(title_size = 22, facet_title_size = 20, axis_title_size = 20, axis_text_size = 18) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "plain"),
      axis.text.y = element_blank(), axis.ticks.y = element_blank(),
      axis.title.y = element_blank(),
      strip.text = element_text(face = "bold"), legend.position = "none",
      legend.text = element_text(size = 16), legend.title = element_text(size = 16, face = "bold")
    )
}

# plotting function for mean
make_faceted_plot_mean <- function(data, title) {
  ggplot(data) +
    stat_function(fun = dgamma, args = list(shape = alpha, rate = alpha), linewidth = 1, color = "#2c3e50") +
    geom_segment(aes(x = center, xend = center, y = density, yend = 0), color = "#e74c3c", linewidth = 1, linetype = "twodash") +
    geom_point(aes(x = center, y = density), color = "#8e44ad", size = 2.0) +
    facet_wrap(~k, ncol = 1, labeller = labeller(k = function(x) paste0("k = ", x))) +
    scale_x_continuous(limits = c(0, 3.5), expand = c(0.02, 0)) +
    scale_y_continuous(limits = c(0, NA), expand = c(0.02, 0)) +
    labs(title = title, x = "rate", y = "probability") +
    theme_pilot(title_size = 22, facet_title_size = 20, axis_title_size = 20, axis_text_size = 18) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "plain"),
      axis.text.y = element_blank(), axis.ticks.y = element_blank(),
      strip.text = element_text(face = "bold"),
      legend.position = "none"
    )
}

faceted_plot_mean <- make_faceted_plot_mean(all_discretizations_mean, "Mean")
faceted_plot_median <- make_faceted_plot_median(all_discretizations_median, "Normalized Median")
faceted_plot_median_unnormalized <- make_faceted_plot_median(all_discretizations_median_unnormalized, "Unnormalized Median")

mean_plot_labeled <- faceted_plot_mean + labs(tag = "A") + theme(plot.tag = element_text(size = 20, face = "bold", hjust = -0.5, vjust = 1))
median_plot_labeled <- faceted_plot_median + labs(tag = "B") + theme(plot.tag = element_text(size = 20, face = "bold", hjust = -0.5, vjust = 1))
unnormalized_plot_labeled <- faceted_plot_median_unnormalized + labs(tag = "C") + theme(plot.tag = element_text(size = 20, face = "bold", hjust = -0.5, vjust = 1))

final_plot <- mean_plot_labeled | median_plot_labeled | unnormalized_plot_labeled

ggsave(paste0("IntroPlots/gamma_discretization_alpha", alpha, ".pdf"), final_plot,
  device = cairo_pdf, width = 15, height = 7, dpi = 450, bg = "white", create.dir = T
)
