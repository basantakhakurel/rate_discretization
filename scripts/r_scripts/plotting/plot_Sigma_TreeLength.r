#!/usr/bin/env Rscript
# R script to plot the posteriors for Lognromal output
# Authors: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# date: 2025-07-08

# Load necessary libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(ggridges)
  library(pilot)
  library(stringr)
  library(patchwork)
})

# Set font family
set_pilot_family(family = "Montserrat")


# Configuration of plots and simulation settings
CONFIG <- list(
  # True values
  true_sigma = 0.587405,
  true_tree_length = 1.02696,

  # Burn-in
  burnin_frac = 0.1,

  # Settings for ggplot aesthetics
  plot_settings = list(
    scale = 1,
    alpha = 0.6,
    bins = 40,
    axis_title_size = 25,
    axis_text_size = 18,
    plot_title_size = 25,
    output_width = 20,
    output_height = 12,
    dpi = 450
  )
)

# function to load and parse output with Gamma
# this function takes all the data from the log files
# and removes the burnin as well.
load_and_parse_data <- function(base_dir = "inference_results", rep_num = 1) {
  cat("Scanning for result directories for sim_", rep_num, "...\n", sep = "")
  all_dirs <- list.dirs(path = base_dir, recursive = TRUE)
  rep_string <- paste0("/sim_", rep_num)
  target_dirs <- all_dirs[endsWith(all_dirs, rep_string)]

  target_dirs <- target_dirs[grepl("Lognormal", target_dirs)]

  if (length(target_dirs) == 0) {
    warning("No Lognormal model result directories found for replicate: ", rep_num)
    return(data.frame())
  }

  cat("Found ", length(target_dirs), " Lognormal directories. Processing...\n", sep = "")

  all_data_list <- lapply(target_dirs, function(dir_path) {
    log_files <- list.files(path = dir_path, pattern = "\\.log$", full.names = TRUE)
    if (length(log_files) == 0) {
      return(NULL)
    }

    mcmc_data <- read.delim(log_files[1])
    burnin <- floor(CONFIG$burnin_frac * nrow(mcmc_data))
    if (nrow(mcmc_data) > burnin) mcmc_data <- mcmc_data[-seq_len(burnin), ]

    # magic string parsing (don't touch! it works!)
    inf_model <- str_match(dir_path, "with_([^_]+)_k")[1, 2]
    inf_k <- as.numeric(str_match(dir_path, "with_.*_k([0-9]+)")[1, 2])
    sim_string <- str_match(dir_path, "on_([^/]+)")[1, 2]
    sim_k <- str_extract(sim_string, "[0-9]+$")
    sim_model <- str_remove(sim_string, "_[0-9]+$")
    sim_k[is.na(sim_k)] <- "cont"

    data.frame(
      sigma = mcmc_data$sigma,
      tree_length = mcmc_data$tree_length,
      sim_model = sim_model,
      sim_k = sim_k,
      inf_model = inf_model,
      inf_k = inf_k
    )
  })

  combined_data <- bind_rows(all_data_list)

  # factor levels for ordering of the plots
  combined_data$sim_k <- factor(combined_data$sim_k, levels = c("2", "4", "8", "cont"))
  y_axis_order <- as.character(sort(unique(combined_data$inf_k), decreasing = TRUE))
  combined_data$inf_k <- factor(combined_data$inf_k, levels = y_axis_order)

  return(combined_data)
}


# function to create a single panel for the composite plot.
#
# data - A subset of the full data for one panel.
# true_value - The true value to draw as a vertical line.
# x_var - The name of the variable for the x-axis
# x_lab - The label for the x-axis (Only used for last plot)
# plot_title - The title for the panel
# A ggplot object representing one panel.
create_sigma_panel <- function(data, true_value, x_var, x_lab, plot_title) {
  base_theme <- theme_pilot(
    axis_title_size = CONFIG$plot_settings$axis_title_size,
    axis_text_size = CONFIG$plot_settings$axis_text_size
  ) +
    theme(
      legend.position = "none",
      strip.text = element_text(size = CONFIG$plot_settings$axis_text_size),
      plot.title = element_text(size = CONFIG$plot_settings$plot_title_size, face = "plain", hjust = 0.5)
    )

  ggplot(data, aes(x = .data[[x_var]], y = inf_k)) +
    stat_binline(
      scale = CONFIG$plot_settings$scale,
      alpha = CONFIG$plot_settings$alpha,
      bins = CONFIG$plot_settings$bins,
      draw_baseline = FALSE,
      aes(fill = inf_k)
    ) +
    geom_vline(xintercept = true_value, linetype = "dashed", color = "#e74c3c", linewidth = 0.8) +
    scale_x_continuous(limits = c(0.3, 0.9), breaks = seq(0.2, 1, 0.2)) +
    facet_wrap(~sim_k, nrow = 1, labeller = labeller(sim_k = function(x) paste("k =", x))) +
    scale_fill_viridis_d() +
    labs(x = x_lab, y = "Rate Categories", title = plot_title) +
    base_theme +
    coord_cartesian(clip = "off")
}

create_tl_panel <- function(data, true_value, x_var, x_lab, plot_title) {
  base_theme <- theme_pilot(
    axis_title_size = CONFIG$plot_settings$axis_title_size,
    axis_text_size = CONFIG$plot_settings$axis_text_size
  ) +
    theme(
      legend.position = "none",
      strip.text = element_text(size = CONFIG$plot_settings$axis_text_size),
      plot.title = element_text(size = CONFIG$plot_settings$plot_title_size, face = "plain", hjust = 0.5)
    )

  ggplot(data, aes(x = .data[[x_var]], y = inf_k)) +
    stat_binline(
      scale = CONFIG$plot_settings$scale,
      alpha = CONFIG$plot_settings$alpha,
      bins = CONFIG$plot_settings$bins,
      draw_baseline = FALSE,
      aes(fill = inf_k)
    ) +
    geom_vline(xintercept = true_value, linetype = "dashed", color = "#8e44ad", linewidth = 0.8) +
    scale_x_continuous(limits = c(0.9, 1.4), breaks = seq(0.9, 1.4, 0.2)) +
    # scale_x_continuous(limits = c(0.8, 1.5)) +
    facet_wrap(~sim_k, nrow = 1, labeller = labeller(sim_k = function(x) paste("k =", x))) +
    scale_fill_viridis_d() +
    labs(x = x_lab, y = "Rate Categories", title = plot_title) +
    base_theme +
    coord_cartesian(clip = "off")
}

# function to generate and save combined plots.
main <- function(rep_num = 1, plot_output_dir = "plots") {
  if (!dir.exists(plot_output_dir)) dir.create(plot_output_dir, recursive = TRUE)

  all_data <- load_and_parse_data(rep_num = rep_num)
  if (nrow(all_data) == 0) {
    return(invisible(NULL))
  }

  p_sigma <- create_sigma_panel(
    data = all_data %>% filter((sim_model == "discreteLognormalMedian" | sim_model == "continuousLognormal") & inf_model == "discreteLognormalMedian"),
    true_value = CONFIG$true_sigma, x_var = "sigma", x_lab = expression("Shape of Lognormal (" * sigma * ")"),
    plot_title = NULL
  )

  p_tl <- create_tl_panel(
    data = all_data %>% filter((sim_model == "discreteLognormalMedian" | sim_model == "continuousLognormal") & inf_model == "discreteLognormalMedian"),
    true_value = CONFIG$true_tree_length, x_var = "tree_length", x_lab = "Tree Length",
    plot_title = NULL
  )

  combined_plot <- p_sigma / p_tl

  combined_plot <- combined_plot + plot_annotation(tag_levels = "A") & theme(plot.tag = element_text(size = 30, face = "bold", hjust = 0, vjust = 0, family = "Montserrat"))

  filename <- file.path(plot_output_dir, paste0("sim_", rep_num, "_sigma_tl.pdf"))
  ggsave(filename, combined_plot,
    width = CONFIG$plot_settings$output_width,
    height = CONFIG$plot_settings$output_height, device = cairo_pdf
  )
  cat("✔ Plot saved to:", filename, "\n")
}

# --- SCRIPT EXECUTION ---
args <- commandArgs(trailingOnly = TRUE)
rep_to_process <- if (length(args) > 0) as.numeric(args[1]) else 1

cat("\n--- Starting Plot Generation for Replicate", rep_to_process, "---\n")
main(rep_num = rep_to_process)
cat("--- Script Finished ---\n")
