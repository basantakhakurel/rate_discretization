#!/usr/bin/env Rscript

# Plotting script for comparing simulation scenarios
# Author: Basanta Khakurel
# Date: 2026-06-26
# Last Modified: 2026-09-07
# Recreates plots from FEA.

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
config_candidates <- c(
  if (length(file_arg) > 0) {
    file.path(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))), "analysis_config.R")
  },
  "analysis_config.R",
  file.path("scripts", "analysis_config.R")
)
config_candidates <- config_candidates[file.exists(config_candidates)]

if (length(config_candidates) == 0) {
  stop("Could not find analysis_config.R")
}

config_file <- config_candidates[[1]]
source(config_file)

required_pkgs <- c("ape", "patchwork", "ggplot2", "dplyr", "pilot", "extrafont")

for (pkg in required_pkgs) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    stop(paste("Package", pkg, "not found. Please install it."))
  }
}

set_pilot_family(family = "Fira Sans")

# Load results: prefer the pre-collected CSV (produced by collect_results.R on
# the cluster) to avoid re-reading thousands of treefiles locally.
results_csv <- file.path("results", "results_summary.csv")

if (file.exists(results_csv)) {
  print(paste("Reading pre-collected results from", results_csv))
  results <- read.csv(results_csv, stringsAsFactors = FALSE)
  results$Alpha <- factor(results$Alpha, levels = ALPHA_VALUES)
  results$scenario <- factor(results$scenario, levels = SCENARIOS$scenario)
  results$gen_method <- factor(results$gen_method, levels = GEN_METHOD_LEVELS)
  results$inf_method <- factor(results$inf_method, levels = INF_METHOD_LEVELS)
} else {
  print("results_summary.csv not found — reading treefiles directly...")
  meta <- read.csv(file.path(ANALYSIS_DIR, "simulation_metadata.csv"))
  results <- collect_tree_results(meta)
  warn_about_missing_files(results)
}

if (nrow(results) == 0) {
  stop("No results data found. Check file paths and metadata.")
}

print(paste("Processed", nrow(results), "simulation results."))

print("Generating Figure 1: True vs Inferred...")

shape_values <- c(16, 17, 15, 18, 3, 7, 8, 4)
shape_values <- shape_values[seq_along(ALPHA_VALUES)]
names(shape_values) <- ALPHA_VALUES

# Figure 1: True vs Inferred Mean Branch Length
# Facet Grid: Rows = Inference Method, Cols = Generating Distribution
p1 <- ggplot(results, aes(x = true_mean, y = inferred_mean, color = Alpha, shape = Alpha)) +
  geom_abline(intercept = 0, slope = 1, linetype = "solid", color = "black") +
  geom_point(alpha = 0.9, size = 2.5) +
  # geom_point(alpha = 0.8, size = 1.5, position = position_jitter(width = 0.001, height = 0.001)) +
  facet_grid(inf_method ~ gen_method) +
  labs(
    title = "Mean Branch Length",
    x = "True mean branch length (subs/site)",
    y = "Reconstructed mean branch length (subs/site)",
    shape = "Alpha",
    color = "Alpha"
  ) +
  scale_shape_manual(values = shape_values) +
  theme_pilot() +
  theme(
    legend.position = "bottom",
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.5),
    plot.title = element_text(hjust = 0.5)
  )

figure_1_file <- file.path("Plots", "Figure_1_True_vs_Inferred.pdf")
ggsave(
  figure_1_file,
  plot = p1,
  width = 8,
  height = 8,
  device = cairo_pdf,
  create.dir = TRUE
)
print(paste("Saved", figure_1_file))

print("Generating Figure 2: Bias Ratio...")

# Figure 2: Bias Ratio
p2 <- ggplot(
  results,
  aes(x = true_mean, y = inferred_mean / true_mean, color = Alpha, shape = Alpha)
) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray") +
  geom_point(alpha = 0.9, size = 2) +
  facet_grid(inf_method ~ gen_method) +
  scale_x_log10() +
  labs(
    title = "Bias Ratio (Inferred / True)",
    x = "True mean branch length (subs/site, log scale)",
    y = "Ratio of inferred mean to true mean",
    shape = "Alpha",
    color = "Alpha"
  ) +
  scale_shape_manual(values = shape_values) +
  theme_pilot() +
  theme(
    legend.position = "bottom",
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.5),
    plot.title = element_text(hjust = 0.5)
  )

figure_2_file <- file.path("Plots", "Figure_2_Bias_Ratio.pdf")
ggsave(
  figure_2_file,
  plot = p2,
  width = 8,
  height = 8,
  device = cairo_pdf,
  create.dir = TRUE
)
print(paste("Saved", figure_2_file))

print("Plotting complete.")
