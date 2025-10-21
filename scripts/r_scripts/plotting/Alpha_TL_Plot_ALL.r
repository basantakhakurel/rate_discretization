#!/usr/bin/env Rscript
# R script to plot the posteriors
# Authors: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# date: 2025-07-08
# MODIFIED: 2025-10-20 to combine Lognormal (multi-level) and Gamma (Mean/Median) plot styles

# Load necessary libraries
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(ggridges)
  library(pilot)
  library(stringr)
  library(patchwork)
  library(purrr)
  library(ggh4x)
})


set_pilot_family(family = "Montserrat")

# Configuration of plots and simulation settings
CONFIG <- list(
  heterogeneity_levels = list(
    `1-Order` = list(
      label = "1-Order",
      path = "cluster_output/one_order_magnitude/inference_results",
      true_alpha = 3.3582,
      alpha_limits = c(2, 7.5),
      tl_limits = c(0.8, 1.2)
    ),
    `2-Order` = list(
      label = "2-Orders",
      path = "cluster_output/two_orders_magnitude/inference_results",
      true_alpha = 1.1168,
      alpha_limits = c(0.6, 2),
      tl_limits = c(0.8, 1.2)
    ),
    `3-Order` = list(
      label = "3-Orders",
      path = "cluster_output/three_orders_magnitude/inference_results",
      true_alpha = 0.6490,
      alpha_limits = c(0.4, 1.1),
      tl_limits = c(0.8, 1.2)
    )
  ),
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
    output_height = 20,
    dpi = 450,
    alpha_line_color = "#e74c3c",
    tl_line_color = "#8e44ad",
    tag_size = 30
  )
)

load_and_parse_data <- function(data_path, level_label, true_alpha, rep_num = 1) {
  cat("Scanning for result directories in:", data_path, "for sim_", rep_num, "...\n", sep = "")
  all_dirs <- list.dirs(path = data_path, recursive = TRUE)
  rep_string <- paste0("/sim_", rep_num)
  target_dirs <- all_dirs[endsWith(all_dirs, rep_string)]

  target_dirs <- target_dirs[grepl("Gamma", target_dirs)]

  if (length(target_dirs) == 0) {
    warning("No Gamma model result directories found in: ", data_path)
    return(data.frame())
  }

  cat("Found ", length(target_dirs), " Gamma directories. Processing...\n", sep = "")

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
      alpha = mcmc_data$alpha,
      tree_length = mcmc_data$tree_length,
      sim_model = sim_model,
      sim_k = sim_k,
      inf_model = inf_model,
      inf_k = inf_k
    )
  })

  combined_data <- bind_rows(all_data_list)

  if (nrow(combined_data) > 0) {
    combined_data$heterogeneity_level <- level_label
    combined_data$true_alpha <- true_alpha

    combined_data$sim_k <- factor(combined_data$sim_k, levels = c("2", "4", "8", "cont"))
    y_axis_order <- as.character(sort(unique(combined_data$inf_k), decreasing = TRUE))
    combined_data$inf_k <- factor(combined_data$inf_k, levels = y_axis_order)
  }

  return(combined_data)
}

# create my theme
create_plot_theme <- function() {
  theme_pilot(
    axis_title_size = CONFIG$plot_settings$axis_title_size,
    axis_text_size = CONFIG$plot_settings$axis_text_size
  ) +
    theme(
      legend.position = "none",
      strip.text.x = element_text(size = CONFIG$plot_settings$axis_text_size),
      strip.text.y = element_text(size = CONFIG$plot_settings$axis_text_size, angle = 270, hjust = 0.5),
      plot.title = element_text(
        size = CONFIG$plot_settings$plot_title_size,
        face = "plain",
        hjust = 0.5
      )
    )
}

# different scales for different alpha
# levels (first, second and third orders of magnitude)
apply_ggh4x_scales <- function(p, x_limits_list) {
  if (is.null(x_limits_list)) {
    return(p)
  }

  scale_list <- lapply(names(x_limits_list), function(level_label) {
    limits <- x_limits_list[[level_label]]
    as.formula(
      paste0(
        "heterogeneity_level == '", level_label,
        "' ~ scale_x_continuous(limits = c(", limits[1], ", ", limits[2], "))"
      )
    )
  })

  p + ggh4x::facetted_pos_scales(x = scale_list)
}

# base plotting instructions
build_ridge_panel <- function(data, x_var, x_lab, plot_title, facet_scales = "free_x") {
  p <- ggplot(data, aes(x = .data[[x_var]], y = inf_k)) +
    stat_binline(
      scale = CONFIG$plot_settings$scale,
      alpha = CONFIG$plot_settings$alpha,
      bins = CONFIG$plot_settings$bins,
      draw_baseline = FALSE,
      aes(fill = inf_k)
    ) +
    ggh4x::facet_grid2(
      rows = vars(heterogeneity_level),
      cols = vars(sim_k),
      scales = facet_scales,
      independent = if (facet_scales == "free_x") "x" else "none",
      labeller = labeller(sim_k = function(x) paste("Sim k =", x))
    ) +
    scale_fill_viridis_d() +
    labs(x = x_lab, y = "Inference Rate Categories", title = plot_title) +
    create_plot_theme()

  return(p)
}


# make alpha plot
# separating this from the tree length plot to allow for different X-axis limits and labels
create_alpha_plot <- function(data, x_lab, plot_title, limits_list) {
  p <- build_ridge_panel(
    data = data,
    x_var = "alpha",
    x_lab = x_lab,
    plot_title = plot_title,
    facet_scales = "free_x"
  )

  # Add Alpha-specific vline (uses data column)
  p <- p + geom_vline(
    aes(xintercept = .data[["true_alpha"]]),
    linetype = "dashed",
    color = CONFIG$plot_settings$alpha_line_color,
    linewidth = 0.9
  )

  p <- apply_ggh4x_scales(p, limits_list)

  return(p)
}

# Create Tree Length panels
create_tl_plot <- function(data, x_lab, plot_title, limits_list) {
  p <- build_ridge_panel(
    data = data,
    x_var = "tree_length",
    x_lab = x_lab,
    plot_title = plot_title,
    facet_scales = "fixed"
  )

  # Add TL-specific vline (uses static config value)
  p <- p + geom_vline(
    xintercept = CONFIG$true_tree_length,
    linetype = "dashed",
    color = CONFIG$plot_settings$tl_line_color,
    linewidth = 0.9
  )

  common_limits <- limits_list[[1]]

  p <- p + scale_x_continuous(limits = common_limits)

  return(p)
}


# saving the plot
save_plot_combo <- function(p_top, p_bottom, file_suffix, plot_output_dir, rep_num) {
  # Combine plots
  plot_combo <- p_top / p_bottom

  # Add annotation tags (A, B)
  plot_combo <- plot_combo + plot_annotation(tag_levels = "A") &
    theme(
      plot.tag = element_text(
        size = CONFIG$plot_settings$tag_size,
        face = "bold",
        hjust = 0,
        vjust = 0,
        family = "Montserrat"
      )
    )

  # Save the plot
  filename <- file.path(plot_output_dir, paste0("Gamma_", file_suffix, "rep_", rep_num, ".pdf"))
  ggsave(
    filename,
    plot_combo,
    width = CONFIG$plot_settings$output_width,
    height = CONFIG$plot_settings$output_height,
    device = cairo_pdf
  )
  cat(paste("✔ Plot saved to:", filename, "\n"))
}


main <- function(rep_num = 1, plot_output_dir = "plots") {
  if (!dir.exists(plot_output_dir)) dir.create(plot_output_dir, recursive = TRUE)

  all_data <- map_dfr(CONFIG$heterogeneity_levels, function(level) {
    load_and_parse_data(
      data_path = level$path,
      level_label = level$label,
      true_alpha = level$true_alpha,
      rep_num = rep_num
    )
  })

  if (nrow(all_data) == 0) {
    cat("No data loaded, please check the data paths. Exiting.\n")
    return(invisible(NULL))
  }

  all_data$heterogeneity_level <- factor(
    all_data$heterogeneity_level,
    levels = sapply(CONFIG$heterogeneity_levels, `[[`, "label")
  )

  level_labels <- sapply(CONFIG$heterogeneity_levels, `[[`, "label")

  alpha_limits_list <- sapply(CONFIG$heterogeneity_levels, `[[`, "alpha_limits", simplify = FALSE)
  tl_limits_list <- sapply(CONFIG$heterogeneity_levels, `[[`, "tl_limits", simplify = FALSE)

  names(alpha_limits_list) <- level_labels
  names(tl_limits_list) <- level_labels

  data_A <- all_data %>%
    filter((sim_model == "discreteGammaMean" | sim_model == "continuousGamma") & inf_model == "discreteGammaMean")

  data_B <- all_data %>%
    filter((sim_model == "discreteGammaMean" | sim_model == "continuousGamma") & inf_model == "discreteGammaMedian")

  data_C <- all_data %>%
    filter((sim_model == "discreteGammaMedian" | sim_model == "continuousGamma") & inf_model == "discreteGammaMean")

  data_D <- all_data %>%
    filter((sim_model == "discreteGammaMedian" | sim_model == "continuousGamma") & inf_model == "discreteGammaMedian")

  title_A <- "Simulation: Mean-discretization, Inference: Mean-discretization"
  title_B <- "Simulation: Mean-discretization, Inference: Median-discretization"
  title_C <- "Simulation: Median-discretization, Inference: Mean-discretization"
  title_D <- "Simulation: Median-discretization, Inference: Median-discretization"

  alpha_xlab <- expression("Shape of Gamma (" * alpha * ")")
  tl_xlab <- "Tree Length"

  # Alpha Panels
  pA_alpha <- create_alpha_plot(data_A, x_lab = NULL, plot_title = title_A, limits_list = alpha_limits_list)
  pB_alpha <- create_alpha_plot(data_B, x_lab = NULL, plot_title = title_B, limits_list = alpha_limits_list)
  pC_alpha <- create_alpha_plot(data_C, x_lab = alpha_xlab, plot_title = title_C, limits_list = alpha_limits_list)
  pD_alpha <- create_alpha_plot(data_D, x_lab = alpha_xlab, plot_title = title_D, limits_list = alpha_limits_list)

  # Tree Length Panels
  pA_tl <- create_tl_plot(data_A, x_lab = NULL, plot_title = title_A, limits_list = tl_limits_list)
  pB_tl <- create_tl_plot(data_B, x_lab = NULL, plot_title = title_B, limits_list = tl_limits_list)
  pC_tl <- create_tl_plot(data_C, x_lab = tl_xlab, plot_title = title_C, limits_list = tl_limits_list)
  pD_tl <- create_tl_plot(data_D, x_lab = tl_xlab, plot_title = title_D, limits_list = tl_limits_list)

  save_plot_combo(pA_alpha, pD_alpha,
    file_suffix = "Alpha_matched_",
    plot_output_dir = plot_output_dir, rep_num = rep_num
  )

  save_plot_combo(pB_alpha, pC_alpha,
    file_suffix = "Alpha_mismatched_",
    plot_output_dir = plot_output_dir, rep_num = rep_num
  )

  save_plot_combo(pA_tl, pD_tl,
    file_suffix = "TL_matched_",
    plot_output_dir = plot_output_dir, rep_num = rep_num
  )

  save_plot_combo(pB_tl, pC_tl,
    file_suffix = "TL_mismatched_",
    plot_output_dir = plot_output_dir, rep_num = rep_num
  )
}


args <- commandArgs(trailingOnly = TRUE)
rep_to_process <- if (length(args) > 0) as.numeric(args[1]) else 1

cat("\n--- Starting Plot Generation for Replicate", rep_to_process, "---\n")
main(rep_num = rep_to_process)
cat("--- Script Finished ---\n")
