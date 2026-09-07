# Ferretti et al. 2026 Re-analyses — Is the Branch-Length Bias the paper demonstrates really that severe?

A reanalysis of Ferretti et al. (2026) simulations with varying alpha values. The paper argues that the discretized Gamma model (DGM) systematically biases branch-length estimate. This pipeline tests whether the bias is general or limited to specific conditions (few categories, high rate heterogeneity). Reference paper: `https://doi.org/10.1093/sysbio/syag037`

---

## Simulation Design

| Dimension | Values |
|-----------|--------|
| Gamma shape α | 0.649, 1.117, 3.358 |
| Tips per tree | 250 |
| Alignment length | 25000 sites |
| Branch lengths | mean ~ 10^Uniform(−5, −2) per tree |
| Generating models | Continuous Gamma (+GC{α}), Discrete Gamma k=4 (+G4{α}) |
| Inference models | GTR+F+G4, GTR+F+G16, GTR+F+R4 |
| Scenarios per replicate | 6 (2 generating × 3 inference models) |
| Replicates | 1000 |
| Total inference jobs | 18,000 |

All 1000 trees are shared across alpha values.

**Figures (re)produced:**
- **Figure 1** — True vs. inferred mean branch length (faceted by inference
  model × generating model, coloured by α)
- **Figure 2** — Ratio of inferred to true mean branch length

---

## Software Used

- **IQ-TREE 2** (Version 2.2.0)
- **R** v4.6.1

---

### Quick start

```bash
# Dry run to verify job counts
bash scripts/run_simulations.sh palmuc --dry-run
bash scripts/run_inference.sh   palmuc --dry-run

# Stage 1+2: generate trees and simulate alignments
bash scripts/run_simulations.sh palmuc

# Stage 3: run IQ-TREE inference (submit only after Stage 2 completes)
bash scripts/run_inference.sh palmuc

# Stage 4: collect results and plot (run locally after transfer)
bash scripts/run_analysis.sh
```
---

## Stage-by-Stage Reference

### Stage 1+2 — Simulation (`run_simulations.sh`)

Generates 1000 shared trees, then simulates 2 alignments per (alpha, replicate):
- `cont_N.phy` — continuous-Gamma generating model (`GTR+F+GC{α}`)
- `disc_N.phy` — discrete-Gamma k=4 generating model (`GTR+F+G4{α}`)

### Stage 3 — Inference (`run_inference.sh`)

Runs 6 ML inference jobs per replicate:

| Alignment | Model | Output prefix |
|-----------|-------|---------------|
| cont_N.phy | GTR+F+G4 | cont_inf_G4_N |
| cont_N.phy | GTR+F+G16 | cont_inf_G16_N |
| cont_N.phy | GTR+F+R4 | cont_inf_R4_N |
| disc_N.phy | GTR+F+G4 | disc_inf_G4_N |
| disc_N.phy | GTR+F+G16 | disc_inf_G16_N |
| disc_N.phy | GTR+F+R4 | disc_inf_R4_N |

---