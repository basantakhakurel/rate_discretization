#!/usr/bin/env Rscript

# Mk + continuous lognormal-distributed rates
# Author: Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna
# Date: 2025-06-27
# Usage: Rscript scripts/r_scripts/simulate_continuousLognormal.r -n <n_reps> -s <sigma>
################################################################################
# Orders of Magnitude:  1 | Gamma Alpha:  3.3582 | Lognormal Sigma:  0.5874
# Orders of Magnitude:  2 | Gamma Alpha:  1.1168 | Lognormal Sigma:  1.1748
# Orders of Magnitude:  3 | Gamma Alpha:  0.6490 | Lognormal Sigma:  1.7622
################################################################################

library(optparse, quietly = T)
library(phangorn, quietly = T)
library(Claddis, quietly = T)
library(phytools, quietly = T)

# Default sigma chosen to make the 95% lognormal interval span one order of magnitude
# DEFAULT_SIGMA <- abs(log(10) / (qnorm(0.975) - qnorm(0.025)))
DEFAULT_SIGMA <- 1.1748

# Parse options
option_list <- list(
  make_option(c("-n", "--n_reps"),
    type = "integer", default = 1,
    help = "Number of datasets", metavar = "number"
  ),
  make_option(c("-s", "--sigma"),
    type = "double", default = DEFAULT_SIGMA,
    help = "Sigma parameter (sdlog) for lognormal distribution", metavar = "number"
  ),
  make_option(c("-o", "--output_dir"),
    type = "character", default = "sim_Lognormal_Cont",
    help = "Output directory", metavar = "directory"
  )
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

N_REPS <- opt$n_reps
SIGMA <- opt$sigma
OUTPUT_DIR <- opt$output_dir
RATES_DIR <- file.path(OUTPUT_DIR, "rates")

dir.create(OUTPUT_DIR, recursive = T, showWarnings = F)
dir.create(RATES_DIR, recursive = T, showWarnings = F)

set.seed(33)

cat("Output Directory:", OUTPUT_DIR, "\n")
cat("Simulating", N_REPS, "datasets with continuous lognormal (sigma =", round(SIGMA, 6), ")\n")

phylo <- read.tree("data/8taxon.tre")

# Constants
NCHAR <- 100000
# Ensure mean(site_rates) ~ 1 by setting meanlog accordingly
MEANLOG <- -0.5 * SIGMA * SIGMA

for (sim in 1:N_REPS) {
  cat("Simulating replicate", sim, "...\n")

  # Sample one rate per character from continuous lognormal
  site_rates <- rlnorm(NCHAR, meanlog = MEANLOG, sdlog = SIGMA)

  char_matrix <- matrix(NA, nrow = length(phylo$tip.label), ncol = NCHAR)
  rownames(char_matrix) <- phylo$tip.label

  # Simulate characters
  for (i in 1:NCHAR) {
    r <- site_rates[i]
    Q <- matrix(c(-r, r, r, -r), 2, 2, byrow = TRUE, dimnames = list(0:1, 0:1))
    char <- sim.Mk(tree = phylo, Q = Q)
    char_matrix[, i] <- as.numeric(as.character(char))
  }

  # Save histogram for distribution of rates
  cairo_pdf(paste0(RATES_DIR, "/sim_", sim, ".pdf"), family = "Montserrat", width = 4, height = 4)
  hist(site_rates, main = paste("Sim", sim, "Site Rates (Lognormal)"), xlab = "Rate", col = "skyblue")
  dev.off()

  # format matrix for claddis
  char_df <- apply(char_matrix, c(1, 2), as.character)
  cladistic_matrix <- build_cladistic_matrix(char_df,
    header = paste("Simulated Dataset using Continuous Lognormal -- sigma =", round(SIGMA, 6))
  )

  # write nexus file
  write_nexus_matrix(cladistic_matrix, file = paste0(OUTPUT_DIR, "/sim_", sim, ".nex"))

  # trim assumptions block
  nexusLines <- readLines(paste0(OUTPUT_DIR, "/sim_", sim, ".nex"))
  assumptionStart <- grep("BEGIN ASSUMPTIONS;", nexusLines, ignore.case = TRUE)
  if (length(assumptionStart) > 0) {
    writeLines(nexusLines[1:(assumptionStart - 1)], paste0(OUTPUT_DIR, "/sim_", sim, ".nex"))
  }

  # write the site rates
  write.csv(site_rates,
    file = paste0(RATES_DIR, "/sim_", sim, ".rates.txt"),
    quote = FALSE, row.names = FALSE
  )

  cat("Replicate", sim, "done. Mean rate:", round(mean(site_rates), 4), "\n")
}
