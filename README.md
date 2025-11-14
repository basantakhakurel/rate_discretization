# The hidden cost of discretization: How the number of rate categories affect phylogentic inference

## Authors
Basanta Khakurel, Alessio Capobianco, and Sebastian Höhna

## Overview

This repository contains data, scripts, and results from a simulation study evaluating the effects of rate discretization and normalization on phylogenetic inference. The study investigates how discretizing continuous rate distributions (Gamma and Lognormal) and normalizing them to have mean 1 affects parameter estimation in phylogenetic models with among-character rate variation (ACRV).

## Repository Structure

```
rate_discretization/
├── data/                          # Simulated datasets
│   ├── 8taxon.tre                # Starting tree topology
│   ├── one_order/                # Data simulated with 1 order of magnitude rate variation
│   ├── two_order/                # Data simulated with 2 orders of magnitude rate variation
│   ├── three_order/              # Data simulated with 3 orders of magnitude rate variation
│   └── data_lognormal_median_1/  # Additional lognormal simulation data (for median=1 parameterization)
├── scripts/
│   ├── bash_scripts/             # Shell scripts for running simulations and inference
│   ├── r_scripts/                # R scripts for simulation and analysis
│   │   ├── plotting/             # R scripts for generating figures
│   │   ├── simulate_continuousGamma.r
│   │   ├── simulate_continuousLognormal.r
│   │   ├── find_orders_of_magnitude.r
│   │   └── convergenceCheckParallel.r
│   └── Rev_scripts/              # RevBayes scripts for Bayesian inference
│       ├── mcmc.Rev              # Main MCMC inference script
│       ├── model_*.Rev           # Model specification scripts
│       └── simulate_*.Rev        # Simulation scripts
```

## Data Description

### Simulated Datasets

The repository contains morphological character data simulated under various rate variation models:

1. **Continuous Models:**
   - `continuousGamma/`: Data simulated with continuous Gamma-distributed rates
   - `continuousLognormal/`: Data simulated with continuous Lognormal-distributed rates

2. **Discrete Models:**
   - `discreteGammaMean_k/`: Data simulated with discrete Gamma rates using mean discretization (k = 2, 4, 8)
   - `discreteGammaMedian_k/`: Data simulated with discrete Gamma rates using median discretization (k = 2, 4, 8)
   - `discreteLognormalMedian_k/`: Data simulated with discrete Lognormal rates using median discretization (k = 2, 4, 8)

3. **Rate Variation Levels:**
   - **One order of magnitude:** 95% interval spans 10× (Gamma α = 3.3582, Lognormal σ = 0.5874)
   - **Two orders of magnitude:** 95% interval spans 100× (Gamma α = 1.1168, Lognormal σ = 1.1748)
   - **Three orders of magnitude:** 95% interval spans 1000× (Gamma α = 0.6490, Lognormal σ = 1.7622)

### Data Format

- **NEXUS files** (`.nex`): Morphological character matrices in NEXUS format
- **Tree files** (`.tre`): Phylogenetic tree in Newick format
- **Rate files** (`.rates.txt`): Site-specific rate values for continuous simulations

### Inference Results

MCMC output files from RevBayes analyses:
- `.log` files: Parameter traces and log-likelihood values
- `.trees` files: Posterior tree samples
- `.map.tre` files: Maximum a posteriori trees
- `.mcc.tre` files: Maximum clade credibility trees

## Software Requirements

### Required Software

1. **RevBayes** (v1.2.1 or later)
   - Available at: https://revbayes.github.io/
   - Required for Bayesian phylogenetic inference

2. **R** (v4.0 or later)
   - Required R packages:
     - `phangorn`
     - `Claddis`
     - `phytools`
     - `ggplot2`
     - `dplyr`
     - `ggridges`
     - `pilot`
     - `patchwork`
     - `purrr`
     - `ggh4x`
     - `optparse`
     - `extrafont`

3. **Bash** (for running simulation and inference scripts)

## Usage

### 1. Running Simulations

To simulate datasets:

```bash
bash scripts/bash_scripts/run_Simulations.sh
```

This script will:
- Generate continuous Gamma and Lognormal datasets
- Generate discrete datasets with k = 2, 4, 8 categories
- Use both mean and median discretization methods
- Save outputs to `data/` directory

### 2. Running Inference

To run inference on a specific dataset:

```bash
rb --file scripts/Rev_scripts/mcmc.Rev \
   --args <DATASET_NAME> <DATA_DIRECTORY> <MODEL> <OUTPUT_DIRECTORY> <NUM_MCMC_CHAINS> <NUM_RATE_CATEGORIES>
```

Example:
```bash
rb --file scripts/Rev_scripts/mcmc.Rev \
   --args sim_1 continuousGamma discreteGammaMean output_dir 2 8
```

### 3. Generating Figures

Plotting scripts are available in `scripts/r_scripts/plotting`.

### 4. Finding Rate Distribution Parameters

To calculate Gamma and Lognormal parameters for different orders of magnitude:

```bash
Rscript scripts/r_scripts/find_orders_of_magnitude.r
```

## Key Scripts

### Simulation Scripts

- `scripts/r_scripts/simulate_continuousGamma.r`: Simulates continuous Gamma-distributed rates
- `scripts/r_scripts/simulate_continuousLognormal.r`: Simulates continuous Lognormal-distributed rates
- `scripts/Rev_scripts/simulate_discreteGammaMean.Rev`: Simulates discrete Gamma (mean method)
- `scripts/Rev_scripts/simulate_discreteGammaMedian.Rev`: Simulates discrete Gamma (median method)
- `scripts/Rev_scripts/simulate_discreteLognormalMedian.Rev`: Simulates discrete Lognormal (median method)

### Inference Scripts

- `scripts/Rev_scripts/mcmc.Rev`: Main MCMC inference script
- `scripts/Rev_scripts/model_discreteGammaMean.Rev`: Discrete Gamma model (mean)
- `scripts/Rev_scripts/model_discreteGammaMedian.Rev`: Discrete Gamma model (median)
- `scripts/Rev_scripts/model_discreteLognormalMedian.Rev`: Discrete Lognormal model (median)

### Other Scripts

- `scripts/r_scripts/plotting/*.r`: Generate publication figures

## Methodology

### Discretization Methods

1. **Mean Method**: Rate categories are computed as the mean rate within each quantile interval
2. **Median Method**: Rate categories are computed as the median (quantile midpoint) of each interval

### Normalization

All discrete rate categories are normalized to have mean = 1, which is standard practice in phylogenetic inference.

## Citation

If you use this data or code, please cite:

[Citation information to be added upon publication]

## Contact

For questions about this dataset or code, please contact:
- Basanta Khakurel: [basantakhakurel@gmail.com]

## Additional Notes

- The starting tree (`data/8taxon.tre`) was simulated using the script `scripts/Rev_scripts/simulate_tree.Rev`.
- Binary character states (Mk model) are used throughout.
- Seed value: 33 (for reproducibility in R scripts).
