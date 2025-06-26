# Rate Discretization Simulation Study

This repository contains a simulation framework to evaluate the effects of rate discretization and normalization on phylogenetic inference.
The study is motivated by ACRV models where continuous rate distributions (e.g., Gamma, Lognormal) are discretized and normalized to have mean 1.

We investigate how:
- The number of rate categories (`k`) affects inference
- The normalization process alters the effective rate distribution
- These factors impact parameter estimates, especially the shape parameter (e.g., `α` in Gamma)
- Inference of branch lengths and rate categories is biased or distorted

---

## Usage

### 1. Run Simulation Locally

```bash
bash scripts/run_sim_local.sh
```

### 2. Run Inference Locally

```bash
bash scripts/run_infer_local.sh
```

### 3. Run Simulation on SLURM

```bash
bash scripts/submit_sim_slurm.sh
```
### 4. Run Inference on SLURM
```bash
bash scripts/submit_infer_slurm.sh
```

---

## Goals of the Study
- Examine how normalization of discretized rates biases the shape of the original distribution.

- Evaluate whether parameters like `α` can be reliably estimated.

- Measure the stability of inferred rate scalars across different `k`.

- Determine the sensitivity of branch length estimates to discretization and normalization.
