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
INFERENCE_ROOT="${REPO_ROOT}/InferenceOutput"
SLURM_LOGS="${REPO_ROOT}/slurm/logs"

[[ -d "${OUTPUT_ROOT}/SimData" ]] && OUTPUT_ROOT="${OUTPUT_ROOT}/SimData"

INF_CATEGORIES=(2 4 8 16 100)

get_inference_models() {
    case "$1" in
        continuousGamma|discreteGammaMean|discreteGammaMedian)
            echo "discreteGammaMean discreteGammaMedian" ;;
        continuousLognormal|discreteLognormalMedian)
            echo "discreteLognormalMedian" ;;
        *) echo "" ;;
    esac
}

get_tier_for_k() {
    local n_taxa="$1" inf_k="$2"
    if [[ "$n_taxa" == "8" ]]; then
        echo "krypton_8G"
        return
    fi
    case "$inf_k" in
        2|4|8)  echo "krypton_24G" ;;
        16|100) echo "lemmium_48G" ;;
        *)      echo "krypton_24G" ;;
    esac
}

echo "=============================================="
echo "Pipeline Status Check"
echo "=============================================="
echo ""

total_scenarios=0
gamma_scenarios=0
lognormal_scenarios=0
total_reps=0
total_inference_jobs=0
sim_completed=0
inf_completed=0
declare -A TIER_TARGET=() TIER_DONE=()

while IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma n_reps; do
  [[ -z "${scenario_id}" ]] && continue
  [[ "${scenario_id}" =~ ^# ]] && continue

  ((total_scenarios++)) || true
  ((total_reps += n_reps)) || true

  models_str=$(get_inference_models "${rate_model}")
  read -ra models <<< "${models_str}"

  case "${rate_model}" in
    continuousGamma|discreteGammaMean|discreteGammaMedian)
      ((gamma_scenarios++)) || true
      ;;
    continuousLognormal|discreteLognormalMedian)
      ((lognormal_scenarios++)) || true
      ;;
  esac

  ((total_inference_jobs += n_reps * ${#models[@]} * ${#INF_CATEGORIES[@]})) || true

  for (( rep=1; rep<=n_reps; rep++ )); do
    [[ -f "${OUTPUT_ROOT}/${scenario_id}/data/rep_${rep}/sim_1.nex" ]] && { ((sim_completed++)) || true; }
    for inf_model in "${models[@]}"; do
      for inf_k in "${INF_CATEGORIES[@]}"; do
        tier=$(get_tier_for_k "${n_taxa}" "${inf_k}")
        TIER_TARGET[$tier]=$(( ${TIER_TARGET[$tier]:-0} + 1 ))
        map_tre="${INFERENCE_ROOT}/${scenario_id}/with_${inf_model}_k${inf_k}/rep_${rep}/${scenario_id}_rep_${rep}_${inf_model}_${inf_k}_Cats.map.tre"
        if [[ -f "$map_tre" ]]; then
          ((inf_completed++)) || true
          TIER_DONE[$tier]=$(( ${TIER_DONE[$tier]:-0} + 1 ))
        fi
      done
    done
  done
done < "${SCENARIOS_FILE}"

echo "SCENARIOS CONFIGURATION"
echo "-----------------------"
echo "Total scenarios: ${total_scenarios}"
echo "  - Gamma-based: ${gamma_scenarios}"
echo "  - Lognormal-based: ${lognormal_scenarios}"
echo "Total simulation jobs (scenarios × reps): ${total_reps}"
echo ""

echo "INFERENCE JOB TARGET (at each scenario's current n_reps)"
echo "----------------------------------------------------------"
echo "Inference categories: ${INF_CATEGORIES[*]}"
echo "Gamma scenarios: 2 inference models × ${#INF_CATEGORIES[@]} k-values per rep"
echo "Lognormal scenarios: 1 inference model × ${#INF_CATEGORIES[@]} k-values per rep"
echo "Total inference jobs: ${total_inference_jobs}"
echo ""

echo "EXISTING OUTPUT (capped to current n_reps per scenario)"
echo "---------------------------------------------------------"
echo "Simulated datasets found: ${sim_completed} / ${total_reps}"
echo "Inference runs completed: ${inf_completed} / ${total_inference_jobs}"
echo ""

echo "RESOURCE ESTIMATES"
echo "------------------"
echo "Simulation jobs:"
echo "  - Resources: 1 core, 4GB memory per job"
echo "  - Estimated time: ~30-60 min per job"
echo ""
echo "Inference jobs:"
echo "  - Resources: 4 cores per job; memory by tier: krypton_8G (8-taxa),"
echo "               krypton_24G (64-taxa, k<=8), lemmium_48G (64-taxa, k=16/100)"

if [[ -d "${SLURM_LOGS}" ]] && compgen -G "${SLURM_LOGS}/inf_*.out" > /dev/null; then
  declare -A TIER_SUM=() TIER_COUNT=() TIER_MIN=() TIER_MAX=()
  for f in "${SLURM_LOGS}"/inf_*.out; do
    start_line=$(grep -m1 'Scenario:' "$f" 2>/dev/null) || continue
    end_line=$(grep -m1 'Done:' "$f" 2>/dev/null) || continue
    [[ -z "$start_line" || -z "$end_line" ]] && continue
    start_epoch=$(date -d "${start_line%%  *}" +%s 2>/dev/null) || continue
    end_epoch=$(date -d "${end_line%%  *}" +%s 2>/dev/null) || continue
    elapsed=$(( end_epoch - start_epoch ))
    (( elapsed <= 0 )) && continue

    tier=$(basename "$f" | sed -E 's/^inf_(.+)_[0-9]+_[0-9]+\.out$/\1/')
    TIER_SUM[$tier]=$(( ${TIER_SUM[$tier]:-0} + elapsed ))
    TIER_COUNT[$tier]=$(( ${TIER_COUNT[$tier]:-0} + 1 ))
    if [[ -z "${TIER_MIN[$tier]:-}" ]] || (( elapsed < TIER_MIN[$tier] )); then TIER_MIN[$tier]=$elapsed; fi
    if [[ -z "${TIER_MAX[$tier]:-}" ]] || (( elapsed > TIER_MAX[$tier] )); then TIER_MAX[$tier]=$elapsed; fi
  done

  if [[ "${#TIER_COUNT[@]}" -eq 0 ]]; then
    echo "  - Estimated time: no completed job has both a start and end log line yet - no estimate available."
  else
    echo "  - Estimated time (from completed jobs' own logs):"
    for tier in "${!TIER_COUNT[@]}"; do
      n="${TIER_COUNT[$tier]}"
      mean_h=$(awk -v s="${TIER_SUM[$tier]}" -v n="$n" 'BEGIN{printf "%.1f", s/n/3600}')
      min_h=$(awk -v s="${TIER_MIN[$tier]}" 'BEGIN{printf "%.1f", s/3600}')
      max_h=$(awk -v s="${TIER_MAX[$tier]}" 'BEGIN{printf "%.1f", s/3600}')
      remaining=$(( ${TIER_TARGET[$tier]:-0} - ${TIER_DONE[$tier]:-0} ))
      (( remaining < 0 )) && remaining=0
      remaining_core_h=$(awk -v r="$remaining" -v m="$mean_h" 'BEGIN{printf "%.0f", r*m*4}')
      printf '      %-14s  observed n=%-5d  mean=%sh  min=%sh  max=%sh  |  %d jobs remaining ~= %s core-hours\n' \
        "$tier" "$n" "$mean_h" "$min_h" "$max_h" "$remaining" "$remaining_core_h"
    done
  fi
else
  echo "  - Estimated time: no job logs found at ${SLURM_LOGS} - run this on palmuc where the logs live."
fi

echo ""
echo "=============================================="
