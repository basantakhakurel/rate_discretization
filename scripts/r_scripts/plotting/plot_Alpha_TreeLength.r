#!/usr/bin/env Rscript
# R script to plot the posteriors
# Authors: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# date: 2025-07-08

# Load necessary libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(ggridges)
  library(pilot)
  library(extrafont)
})

# Set font family
set_pilot_family(family = "Montserrat")

# Configuration of plots and simulation settings
CONFIG <- list(
  true_alpha = 0.587,
  true_tree_length = 1.133,
  burnin = 150, # 0.25%
  factor_levels = c("100", "16", "8", "6", "4", "2"),
  plot_settings = list(
    scale = 1,
    alpha = 0.7,
    bins = 30,
    axis_title_size = 25,
    axis_text_size = 18,
    title_size = 25,
    output_width = 20,
    output_height = 6,
    dpi = 450
  )
)

# Load and combine data from all simulation types
load_all_simulation_data <- function(filename) {
  sim_types <- c("2cats", "4cats", "8cats")
  sim_labels <- c("k=2", "k=4", "k=8")

  all_data <- list()

  for (i in seq_along(sim_types)) {
    sim_type <- sim_types[i]
    sim_label <- sim_labels[i]

    output_dirs <- paste0("outputGamma_sim_", sim_type, "_inf_", c(2, 4, 6, 8, 16, 100), "cats")

    alpha_list <- list()
    tree_length <- list()

    for (output_dir in output_dirs) {
      log_path <- file.path("res-unnormalized-gamma", output_dir)

      logfiles <- list.files(log_path, pattern = "\\.log$", full.names = TRUE)
      logfile <- logfiles[grepl(filename, logfiles, fixed = TRUE) & !grepl("run", logfiles)]

      if (length(logfile) > 0) {
        tryCatch(
          {
            data <- read.delim(logfile[1]) # Take first match if multiple found
            if (CONFIG$burnin > 0) {
              data <- data[-seq_len(CONFIG$burnin),]
            }
            alpha_list[[output_dir]] <- data$alpha
            tree_length[[output_dir]] <- data$tree_length
          },
          error = function(e) {
            warning(paste("Error reading file", logfile[1], ":", e$message))
          }
        )
      }
    }

    # Combine data for simulation type
    if (length(alpha_list) > 0) {
      sim_data <- bind_rows(
        lapply(names(alpha_list), function(dir) {
          data.frame(
            alpha = alpha_list[[dir]],
            tree_length = tree_length[[dir]],
            output_dir = dir,
            sim_type = sim_label,
            stringsAsFactors = FALSE
          )
        })
      )

      # Extract number of categories and convert to factor
      sim_data$output_dir <- gsub(".*_inf_([0-9]+)cats", "\\1", sim_data$output_dir)
      sim_data$output_dir <- factor(sim_data$output_dir, levels = CONFIG$factor_levels)

      all_data[[sim_type]] <- sim_data
    }
  }

  # Combine all simulation types
  combined_data <- bind_rows(all_data)

  # Set factor levels for sim_type to control `facet` order
  combined_data$sim_type <- factor(combined_data$sim_type, levels = sim_labels)

  return(combined_data)
}

#' Create faceted plots for all simulation types
#' @param filename Character string for the specific log file to process
#' @return List containing faceted alpha and tree_length plots
generate_faceted_plots <- function(filename) {
  # Load all data
  data <- load_all_simulation_data(filename)

  if (nrow(data) == 0) {
    warning("No data found for any simulation type")
    return(list(alpha = NULL, treeLength = NULL))
  }

  # Base plot theme
  base_theme <- theme_pilot(
    axis_title_size = CONFIG$plot_settings$axis_title_size,
    axis_text_size = CONFIG$plot_settings$axis_text_size,
    title_size = CONFIG$plot_settings$title_size
  ) +
    theme(
      legend.position = "none",
      strip.text = element_text(size = CONFIG$plot_settings$axis_text_size)
    )

  # Alpha plot with facets
  alpha_plot <- data %>%
    filter(output_dir %in% CONFIG$factor_levels) %>%
    ggplot(aes(x = alpha, y = output_dir)) +
    stat_binline(
      scale = CONFIG$plot_settings$scale,
      alpha = CONFIG$plot_settings$alpha,
      bins = CONFIG$plot_settings$bins,
      draw_baseline = FALSE
    ) +
    geom_vline(
      xintercept = CONFIG$true_alpha,
      linetype = "dashed",
      color = "red",
      linewidth = 0.7
    ) +
    # scale_x_continuous(limits = c(0.4, 1), breaks = seq(0.4, 1, 0.2)) +
    labs(x = "Alpha", y = "Number of Rate Categories") +
    facet_grid(~sim_type) +
    base_theme +
    coord_cartesian(clip = "off")

  # Tree length plot with facets
  tree_length_plot <- data %>%
    filter(output_dir %in% CONFIG$factor_levels) %>%
    ggplot(aes(x = tree_length, y = output_dir)) +
    stat_binline(
      scale = CONFIG$plot_settings$scale,
      alpha = CONFIG$plot_settings$alpha,
      bins = CONFIG$plot_settings$bins,
      draw_baseline = FALSE
    ) +
    geom_vline(
      xintercept = CONFIG$true_tree_length,
      linetype = "dashed",
      color = "blue",
      linewidth = 0.7
    ) +
    # scale_x_continuous(limits = c(0.8, 1.5)) +
    labs(x = "Tree Length", y = "Number of Rate Categories") +
    facet_grid(~sim_type) +
    base_theme +
    coord_cartesian(clip = "off")

  return(list(alpha = alpha_plot, treeLength = tree_length_plot))
}

#' Main function to generate faceted plots and save them
#' @param filename Character string for the specific log file to process (default: "sim_1")
#' @param output_dir Character string for output directory (default: "Plots")
main <- function(filename = "sim_1", plot_output_dir = "Plots") {
  cat("Processing all simulation types with faceted plots...\n")

  # Generate faceted plots
  plots <- generate_faceted_plots(filename)

  # Save alpha plot
  if (!is.null(plots$alpha)) {
    alpha_output <- file.path(plot_output_dir, paste0(filename, "_alpha_plot.pdf"))
    ggsave(
      alpha_output,
      plots$alpha,
      width = CONFIG$plot_settings$output_width,
      height = CONFIG$plot_settings$output_height,
      units = "in",
      dpi = CONFIG$plot_settings$dpi,
      device = cairo_pdf
    )
    cat("Alpha plot saved to:", alpha_output, "\n")
  }

  # Save tree length plot
  if (!is.null(plots$treeLength)) {
    tree_length_output <- file.path(plot_output_dir, paste0(filename, "_treeLength_plot.pdf"))
    ggsave(
      tree_length_output,
      plots$treeLength,
      width = CONFIG$plot_settings$output_width,
      height = CONFIG$plot_settings$output_height,
      units = "in",
      dpi = CONFIG$plot_settings$dpi,
      device = cairo_pdf
    )
    cat("Tree length plot saved to:", tree_length_output, "\n")
  }

  return(plots)
}

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

# Set defaults if no arguments provided
filename <- if (length(args) > 0) args[1] else "sim_1"
plot_output_dir <- if (length(args) > 1) args[2] else "Plots"

# Create output directory if it doesn't exist
if (!dir.exists(plot_output_dir)) {
  dir.create(plot_output_dir, recursive = TRUE)
  cat("Created output directory:", plot_output_dir, "\n")
}

# Run main function
cat("Starting plot generation...\n")
cat("Input filename:", filename, "\n")
cat("Plot saved in directory:", plot_output_dir, "\n")

result <- main(filename, plot_output_dir)
cat("Script completed successfully!\n")
