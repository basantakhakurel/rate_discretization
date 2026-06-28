#!/bin/bash

# =============================================================================
# Shows job counts and estimates for simulations and inference.
#
# Usage:
#   bash slurm/check_status.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCENARIOS_FILE="${REPO_ROOT}/simConfigs.tsv"
OUTPUT_ROOT="${REPO_ROOT}/SimData"
INFERENCE_ROOT="${REPO_ROOT}/inference_output"

INF_CATEGORIES=(2 4 8 16 100)

echo "=============================================="
echo "Pipeline Status Check"
echo "=============================================="
echo ""

# Count scenarios
total_scenarios=0
gamma_scenarios=0
lognormal_scenarios=0
total_reps=0

while IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma n_reps; do
  [[ -z "${scenario_id}" ]] && continue
  [[ "${scenario_id}" =~ ^# ]] && continue

  ((total_scenarios++)) || true
  ((total_reps += n_reps)) || true

  case "${rate_model}" in
    continuousGamma|discreteGammaMean|discreteGammaMedian)
      ((gamma_scenarios++)) || true
      ;;
    continuousLognormal|discreteLognormalMedian)
      ((lognormal_scenarios++)) || true
      ;;
  esac
done < "${SCENARIOS_FILE}"

echo "SCENARIOS CONFIGURATION"
echo "-----------------------"
echo "Total scenarios: ${total_scenarios}"
echo "  - Gamma-based: ${gamma_scenarios}"
echo "  - Lognormal-based: ${lognormal_scenarios}"
echo "Total simulation jobs (scenarios × reps): ${total_reps}"
echo ""

# Calculate inference jobs
# Gamma scenarios: 2 inference models × 5 k values = 10 per rep
# Lognormal scenarios: 1 inference model × 5 k values = 5 per rep
gamma_inf_per_rep=$((2 * ${#INF_CATEGORIES[@]}))
lognormal_inf_per_rep=$((1 * ${#INF_CATEGORIES[@]}))

# Need to count actual reps per model type
gamma_reps=0
lognormal_reps=0

while IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma n_reps; do
  [[ -z "${scenario_id}" ]] && continue
  [[ "${scenario_id}" =~ ^# ]] && continue

  case "${rate_model}" in
    continuousGamma|discreteGammaMean|discreteGammaMedian)
      ((gamma_reps += n_reps)) || true
      ;;
    continuousLognormal|discreteLognormalMedian)
      ((lognormal_reps += n_reps)) || true
      ;;
  esac
done < "${SCENARIOS_FILE}"

total_inference_jobs=$((gamma_reps * gamma_inf_per_rep + lognormal_reps * lognormal_inf_per_rep))

echo "INFERENCE JOB ESTIMATES"
echo "-----------------------"
echo "Inference categories: ${INF_CATEGORIES[*]}"
echo "Gamma scenario reps: ${gamma_reps} × ${gamma_inf_per_rep} models = $((gamma_reps * gamma_inf_per_rep)) jobs"
echo "Lognormal scenario reps: ${lognormal_reps} × ${lognormal_inf_per_rep} models = $((lognormal_reps * lognormal_inf_per_rep)) jobs"
echo "Total inference jobs: ${total_inference_jobs}"
echo ""

# Check existing output
echo "EXISTING OUTPUT"
echo "---------------"

if [[ -d "${OUTPUT_ROOT}" ]]; then
  sim_completed=$(find "${OUTPUT_ROOT}" -name "sim_1.nex" 2>/dev/null | wc -l)
  echo "Simulated datasets found: ${sim_completed} / ${total_reps}"
else
  echo "Simulated datasets found: 0 / ${total_reps}"
fi

if [[ -d "${INFERENCE_ROOT}" ]]; then
  inf_completed=$(find "${INFERENCE_ROOT}" -name "*.log" 2>/dev/null | wc -l)
  echo "Inference runs completed: ${inf_completed} / ${total_inference_jobs}"
else
  echo "Inference runs completed: 0 / ${total_inference_jobs}"
fi

echo ""
echo "RESOURCE ESTIMATES"
echo "------------------"
echo "Simulation jobs:"
echo "  - Resources: 1 core, 4GB memory per job"
echo "  - Estimated time: ~30-60 min per job"
echo ""
echo "Inference jobs:"
echo "  - Resources: 2 cores, 16GB memory per job"
echo "  - Estimated time: ~2-6 hours per job"
echo "  - Total core-hours: ~$((total_inference_jobs * 2 * 4)) - $((total_inference_jobs * 2 * 6)) hours"
echo ""
echo "=============================================="
