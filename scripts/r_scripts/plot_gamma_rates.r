# R script to plot discrete gamma rates
# This script plots discrete gamma rates for various k values both using mean and the median approach.
# Authors: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# date: 2025-08-20

library(ggplot2)
library(dplyr)
library(purrr)
library(extrafont)
library(pilot)

set_pilot_family(family = "Montserrat")
set.seed(33)

# Parameters
alpha <- 3
k_values <- c(1, 2, 3, 5, 7, 11, 15, 23)

# Discretization functions

# Mean of each bin
discrete.gamma.mean <- function(alpha, k) {
  if (k == 1) {
    return(1)
  }
  quants <- qgamma((1:(k - 1)) / k, shape = alpha, rate = alpha)
  rates <- diff(c(0, pgamma(quants * alpha, shape = alpha + 1), 1)) * k
  return(rates)
}

# Median of each bin
discrete.gamma.median <- function(alpha, k) {
  midpoints <- (0:(k - 1)) / k + 1 / (2 * k)
  rates <- qgamma(midpoints, shape = alpha, rate = alpha)
  return(rates / mean(rates)) # normalized so mean = 1
}

# Generate all data
make_data <- function(method, k_values, alpha) {
  map_dfr(
    k_values,
    ~ {
      rates <- if (method == "mean") {
        discrete.gamma.mean(alpha, .x)
      } else {
        discrete.gamma.median(alpha, .x)
      }
      tibble(
        center = rates,
        k = .x,
        density = dgamma(rates, shape = alpha, rate = alpha)
      )
    }
  )
}

all_discretizations_mean <- make_data("mean", k_values, alpha)
all_discretizations_median <- make_data("median", k_values, alpha)

# plotting function
make_faceted_plot <- function(data, title) {
  ggplot(data) +
    # gamma curve
    stat_function(
      fun = dgamma,
      args = list(shape = alpha, rate = alpha),
      linewidth = 1,
      color = "#2c3e50",
      alpha = 0.8
    ) +
    # vertical droplines
    geom_segment(
      aes(x = center, xend = center, y = density, yend = 0),
      color = "#e74c3c",
      linewidth = 1,
      alpha = 0.85
    ) +
    geom_point(
      aes(x = center, y = density),
      color = "#8e44ad",
      size = 1.5,
      alpha = 0.9
    ) +
    facet_wrap(~k,
      ncol = 2, scales = "fixed",
      labeller = labeller(k = function(x) paste0("k = ", x))
    ) +
    scale_x_continuous(limits = c(0, 3), expand = c(0.02, 0)) +
    scale_y_continuous(limits = c(0, NA), expand = c(0.02, 0)) +
    labs(
      title = title,
      x = "rate",
      y = "probability"
    ) +
    theme_pilot(
      title_size = 22,
      facet_title_size = 20,
      axis_title_size = 20,
      axis_text_size = 18
    ) +
    theme(
      plot.title = element_text(hjust = 0.5),
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      strip.text = element_text(face = "plain")
    )
}

# Generate all plots
faceted_plot_mean <- make_faceted_plot(
  all_discretizations_mean,
  "Mean discretization"
)

faceted_plot_median <- make_faceted_plot(
  all_discretizations_median,
  "Median discretization"
)


# mean_plot_labeled <- faceted_plot_mean +
#   labs(tag = "a)") +
#   theme(plot.tag = element_text(size = 20, face = "bold", hjust = 0, vjust = 0, family = "Montserrat"))

# median_plot_labeled <- faceted_plot_median +
#   labs(tag = "b)") +
#   theme(plot.tag = element_text(size = 20, face = "bold", hjust = 0, vjust = 0, family = "Montserrat"))


# Mean version
ggsave("Plots/gamma_mean.pdf", mean_plot_labeled,
  device = cairo_pdf, width = 12, height = 10, dpi = 450, bg = "white"
)
ggsave("Plots/gamma_mean.png", mean_plot_labeled,
  width = 16, height = 13, dpi = 450, bg = "white"
)

# Median version
ggsave("Plots/gamma_median.pdf", median_plot_labeled,
  device = cairo_pdf, width = 12, height = 10, dpi = 450, bg = "white"
)
ggsave("Plots/gamma_median.png", median_plot_labeled,
  width = 16, height = 13, dpi = 450, bg = "white"
)

print("Plots saved successfully!")


library(patchwork)

final_plot <- mean_plot_labeled + median_plot_labeled +
  plot_annotation(
    tag_levels = "A",
    theme = theme(plot.title = element_text(size = 24, face = "bold", family = "Montserrat"))
  )

final_plot + canvas(24, 10)

ggsave("Plots/gamma_discretization.pdf", final_plot,
  device = cairo_pdf, width = 20, height = 8, dpi = 450, bg = "white"
)
