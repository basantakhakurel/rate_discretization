#!/usr/bin/env Rscript

# Mk + continuous lognormal-distributed rates
# Author: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# Date: 2025-06-27
# Last Modified: 2026-06-28
# This script simulates morphological characters under continuous Lognormal-distributed
# rates.
#
# Usage: Rscript simulateContinuousLognormal.r <tree_file> <n_sites> <sigma> <output_dir> <seed>
#
################################################################################
# Reference:
# Orders of Magnitude:  1 | Gamma Alpha:  3.358 | Lognormal Sigma:  0.587
# Orders of Magnitude:  2 | Gamma Alpha:  1.117 | Lognormal Sigma:  1.175
# Orders of Magnitude:  3 | Gamma Alpha:  0.649 | Lognormal Sigma:  1.762
################################################################################

suppressPackageStartupMessages({
  library(phangorn)
  library(Claddis)
  library(phytools)
  library(ape)
})

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 5) {
  cat("Usage: Rscript simulateContinuousLognormal.r <tree_file> <n_sites> <sigma> <output_dir> <seed>\n")
  cat("\nArguments:\n")
  cat("  tree_file   : Path to Newick tree file\n")
  cat("  n_sites     : Number of characters to simulate\n")
  cat("  sigma       : Lognormal standard deviation (sdlog)\n")
  cat("  output_dir  : Output directory for NEXUS file\n")
  cat("  seed        : Random seed for reproducibility\n")
  quit(status = 1)
}

TREE_FILE <- args[1]
N_SITES <- as.integer(args[2])
SIGMA <- as.numeric(args[3])
OUTPUT_DIR <- args[4]
SEED <- as.integer(args[5])

set.seed(SEED)

# Create output directory
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
RATES_DIR <- file.path(OUTPUT_DIR, "rates")
dir.create(RATES_DIR, recursive = TRUE, showWarnings = FALSE)

cat("Continuous Lognormal Simulation \n")
cat("Tree file:", TREE_FILE, "\n")
cat("Number of sites:", N_SITES, "\n")
cat("Sigma:", SIGMA, "\n")
cat("Output directory:", OUTPUT_DIR, "\n")
cat("Seed:", SEED, "\n")

# Read tree
if (!file.exists(TREE_FILE)) {
  stop(paste("Error: Tree file not found:", TREE_FILE))
}
phylo <- read.tree(TREE_FILE)
cat("Tree loaded with", length(phylo$tip.label), "taxa\n")
cat("Tree length:", sum(phylo$edge.length), "\n")

# Set meanlog so that E[X] = 1
# For lognormal: E[X] = exp(mu + sigma^2/2) = 1
# Thus, mu = -sigma^2/2
MEANLOG <- -0.5 * SIGMA * SIGMA
cat("Meanlog (computed):", MEANLOG, "\n")

# Sample one rate per character from continuous lognormal
site_rates <- rlnorm(N_SITES, meanlog = MEANLOG, sdlog = SIGMA)

cat("Simulating", N_SITES, "characters...\n")

# Initialize character matrix
char_matrix <- matrix(NA, nrow = length(phylo$tip.label), ncol = N_SITES)
rownames(char_matrix) <- phylo$tip.label

# Simulate characters one at a time with site-specific rates
# Show progress every 10%
progress_interval <- max(1, floor(N_SITES / 10))

for (i in 1:N_SITES) {
  r <- site_rates[i]
  # Q matrix for binary Mk model scaled by rate r
  Q <- matrix(c(-r, r, r, -r), 2, 2, byrow = TRUE, dimnames = list(0:1, 0:1))
  char <- sim.Mk(tree = phylo, Q = Q)
  char_matrix[, i] <- as.numeric(as.character(char))

  if (i %% progress_interval == 0) {
    cat(sprintf(
      "  Progress: %d%% (%d/%d characters)\n",
      round(100 * i / N_SITES), i, N_SITES
    ))
  }
}

cat("Simulation complete.\n")

# Format matrix for Claddis
char_df <- apply(char_matrix, c(1, 2), as.character)
cladistic_matrix <- build_cladistic_matrix(char_df,
  header = paste("Simulated Dataset using Continuous Lognormal -- sigma =", SIGMA, "-- seed =", SEED)
)

# Write NEXUS file
nexus_file <- file.path(OUTPUT_DIR, "sim_1.nex")
write_nexus_matrix(cladistic_matrix, file = nexus_file)

# Trim ASSUMPTIONS block (not used by RevBayes)
nexus_lines <- readLines(nexus_file)
assumption_start <- grep("BEGIN ASSUMPTIONS;", nexus_lines, ignore.case = TRUE)
if (length(assumption_start) > 0) {
  writeLines(nexus_lines[1:(assumption_start - 1)], nexus_file)
}

# Write the site rates for verification
rates_file <- file.path(RATES_DIR, "sim_1.rates.csv")
write.csv(data.frame(site = 1:N_SITES, rate = site_rates),
  file = rates_file,
  quote = FALSE, row.names = FALSE
)

cat("\n Summary \n")
cat("Output NEXUS file:", nexus_file, "\n")
cat("Rates file:", rates_file, "\n")
cat("Mean site rate:", round(mean(site_rates), 6), "(expected: 1.0)\n")
cat("Rate std dev:", round(sd(site_rates), 6), "\n")
cat("Rate range: [", round(min(site_rates), 6), ",", round(max(site_rates), 6), "]\n")
cat("Done.\n")
