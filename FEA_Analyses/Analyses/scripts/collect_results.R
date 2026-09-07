#!/usr/bin/env Rscript

# Collects all inference results into a single CSV.
# Author: Basanta Khakurel
# Output: results/results_summary.csv
# Date: 2026-01-23
# Last Modified: 2026-09-07
#
# Usage:
#   cd FEA_Analyses/Analyses
#   Rscript scripts/collect_results.R

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
  stop("Could not find analysis_config.R. Run from Analyses/ or Analyses/scripts/.")
}
source(config_candidates[[1]])

if (!requireNamespace("ape", quietly = TRUE)) {
  stop("Package 'ape' is required. Install it with: install.packages('ape')")
}
library(ape)

metadata_file <- file.path(ANALYSIS_DIR, "simulation_metadata.csv")
if (!file.exists(metadata_file)) {
  stop("simulation_metadata.csv not found: ", metadata_file)
}

meta <- read.csv(metadata_file)
message(
  "Collecting results for ", nrow(meta), " replicates across ",
  length(ALPHA_VALUES), " alpha values..."
)
message("Expected scenarios: ", paste(SCENARIOS$scenario, collapse = ", "))

results <- collect_tree_results(meta)
warn_about_missing_files(results)

if (nrow(results) == 0) {
  stop("No results found. Confirm that Stage 3 (inference) is complete.")
}

n_expected <- nrow(meta) * nrow(SCENARIOS) * nrow(ALPHA_RUNS)
message("Collected ", nrow(results), " / ", n_expected, " expected rows.")

missing_count <- length(attr(results, "missing_files"))
if (missing_count > 0) {
  message("Skipped ", missing_count, " missing files (see warnings above).")
}

dir.create("results", recursive = TRUE, showWarnings = FALSE)
out_file <- file.path(ANALYSIS_DIR, "results", "results_summary.csv")
write.csv(results, out_file, row.names = FALSE)
message("Saved: ", out_file)
