#!/usr/bin/env Rscript

# Mk + discrete gamma simulator
# Authors: Basanta Khakurel, Alessio Capobianco and Sebastian Höhna
# Date: 2025-06-27
# Usage: Rscript scripts/r_scripts/Simulate_DiscretizedGamma.R -n <number_of_simulation_replicates> -c <number_of_rate_categories_to_simulate_from>

library(optparse, quietly = T)
library(phangorn, quietly = T)
library(Claddis, quietly = T)

# Parse options
option_list <- list(
  make_option(c("-n", "--n_reps"),
    type = "integer", default = 1,
    help = "Number of datasets to simulate",
    metavar = "number"
  ),
  make_option(c("-c", "--num_categories"),
    type = "integer", default = 4,
    help = "Number of categories",
    metavar = "number"
  )
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

N_REPS <- opt$n_reps
NUM_CATEGORIES <- opt$num_categories
OUTPUT_DIR <- file.path("data", paste0("sim_", NUM_CATEGORIES))
RATES_DIR <- file.path(OUTPUT_DIR, "rates")

dir.create(OUTPUT_DIR, showWarnings = F, recursive = T)
dir.create(RATES_DIR, showWarnings = F)

set.seed(33)

cat("Output Directory:", OUTPUT_DIR, "\n")
cat("Number of Datasets:", N_REPS, "\n")
cat("Rate categories: ", NUM_CATEGORIES, "\n")

# load tree
phylo <- read.tree("data/8taxon.tre")

# Constants
NCHAR <- 1000
H <- abs(log(10) / (qnorm(0.975) - qnorm(0.025)))
gammaCats <- discrete.gamma(alpha = H, k = NUM_CATEGORIES)

# computing Q-matrix per rate category
Q_matrices <- lapply(gammaCats, function(r) {
  matrix(c(-r, r, r, -r), 2, 2, byrow = T, dimnames = list(0:1, 0:1))
})

for (sim in 1:N_REPS) {
  cat("Simulating replicate", sim, "...\n")

  # Assign rate categories to sites
  site_rates_idx <- sample(1:NUM_CATEGORIES, NCHAR, replace = T)
  site_rates <- gammaCats[site_rates_idx]

  # simulate characters
  char_matrix <- matrix(NA, nrow = length(phylo$tip.label), ncol = NCHAR, dimnames = list(phylo$tip.label, NULL))

  for (k in 1:NUM_CATEGORIES) {
    idx <- which(site_rates_idx == k)
    if (length(idx) == 0) next
    simdat <- sim.Mk(tree = phylo, Q = Q_matrices[[k]], nsim = length(idx))
    if (length(idx) == 1) {
      char_matrix[, idx] <- matrix(as.character(as.numeric(unlist(simdat)) - 1), nrow = length(phylo$tip.label))
    } else {
      # Convert to 0/1 character labels explicitly
      mapped_simdat <- lapply(simdat, function(x) as.character(as.numeric(x) - 1))
      char_matrix[, idx] <- do.call(cbind, mapped_simdat)
    }
  }

  # saving a histogram to see how many fall into each category
  cairo_pdf(paste0(RATES_DIR, "/sim_", sim, ".pdf"), family = "Montserrat", width = 4, height = 4)
  hist(site_rates, main = "Site Rates Histogram", xlab = "Rate", col = "skyblue")
  dev.off()

  # format matrix for claddis
  char_df <- as.data.frame(char_matrix)
  cladistic_matrix <- build_cladistic_matrix(as.matrix(char_df), header = paste("Simulated Dataset using Discretized Gamma --", NUM_CATEGORIES, "rate categories"))

  # write nexus file
  outfile <- paste0(OUTPUT_DIR, "/sim_", sim, ".nex")
  write_nexus_matrix(cladistic_matrix, file = outfile)

  # trim the assumptions block
  nexusLines <- readLines(outfile)
  assumptionStart <- grep("BEGIN ASSUMPTIONS;", nexusLines, ignore.case = TRUE)
  if (length(assumptionStart) > 0) {
    writeLines(nexusLines[1:(assumptionStart - 1)], outfile)
  }

  # write the rates
  write.csv(site_rates, file = paste0(RATES_DIR, "/sim_", sim, ".rates.txt"), quote = FALSE, row.names = FALSE)

  cat("Replicate", sim, "complete. Mean rate:", mean(site_rates), "\n")
}
