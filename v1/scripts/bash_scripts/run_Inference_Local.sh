#!/bin/bash

# Inference Script
# This script runs inferences on the simulated datasets
# Author: Basanta Khakurel
# Date: 2025-09-03

set -euo pipefail

# Number of simulation replicates
N_REPS=2
MAX_JOBS=6
# Path to main RevBayes MCMC script
REV_SCRIPT="scripts/Rev_scripts/mcmc.Rev"

SIM_CATEGORIES=(2 4 8)
INF_CATEGORIES=(2 4 8 16 100)

# Where inference results will be saved
BASE_OUTPUT_DIR="inference_results"
# Where screen logs will be saved
LOG_DIR="inference_screen_outputs"


echo "Setting up output and log directories..."
mkdir -p "${BASE_OUTPUT_DIR}"
mkdir -p "${LOG_DIR}"
echo "Output will be saved in: ${BASE_OUTPUT_DIR}"
echo "Logs will be saved in:   ${LOG_DIR}"

# Waits for a free slot before starting a new job.
wait_for_slot() {
    while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
        sleep 1
    done
}

# function to start an inference
# arguments:
#   $1: Input subdirectory within 'data/' (e.g., "continuousGamma")
#   $2: Replicate number (e.g., 1, 2, ...)
#   $3: Inference model name (e.g., "discreteGammaMean")
#   $4: Number of categories for the inference model (e.g., 8)
run_inference() {
    local input_subdir="$1"
    local rep_num="$2"
    local inf_model="$3"
    local inf_k="$4"

    local data_name="sim_${rep_num}"
    local output_subdir="on_${input_subdir}/with_${inf_model}_k${inf_k}/sim_${rep_num}"
    local output_dir="${BASE_OUTPUT_DIR}/${output_subdir}"
    local log_file="${LOG_DIR}/${output_subdir//\//_}.log"

    mkdir -p "${output_dir}"

    echo "-> Starting inference on data/${input_subdir}/${data_name} | Model: ${inf_model} (k=${inf_k})"

    rb --file "${REV_SCRIPT}" \
        --args "${data_name}" "${input_subdir}" "${inf_model}" "${output_dir}" 1 "${inf_k}" \
        > "${log_file}" 2>&1 &
}

echo -e "\nStarting inferences..."

# Inferences on Continuous Gamma Data ---
echo -e "\n[1/5] Inferences on Continuous Gamma data..."
for rep in $(seq 1 "${N_REPS}"); do
    for k in "${INF_CATEGORIES[@]}"; do
        wait_for_slot

        run_inference "continuousGamma" "${rep}" "discreteGammaMean" "${k}"
        wait_for_slot
        run_inference "continuousGamma" "${rep}" "discreteGammaMedian" "${k}"
    done
done

# Inferences on Discrete Gamma (Mean) Data ---
echo -e "\n[2/5] Inferences on Discrete Gamma (Mean) data..."
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteGammaMean_${sim_k}"
            wait_for_slot
            run_inference "${input_data_dir}" "${rep}" "discreteGammaMean" "${inf_k}"
            wait_for_slot
            run_inference "${input_data_dir}" "${rep}" "discreteGammaMedian" "${inf_k}"
        done
    done
done

# Inferences on Discrete Gamma (Median) Data ---
echo -e "\n[3/5] Inferences on Discrete Gamma (Median) data..."
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteGammaMedian_${sim_k}"
            wait_for_slot
            run_inference "${input_data_dir}" "${rep}" "discreteGammaMean" "${inf_k}"
            wait_for_slot
            run_inference "${input_data_dir}" "${rep}" "discreteGammaMedian" "${inf_k}"
        done
    done
done

# Inferences on Continuous Lognormal Data ---
echo -e "\n[4/5] Inferences on Continuous Lognormal data..."
for rep in $(seq 1 "${N_REPS}"); do
    for k in "${INF_CATEGORIES[@]}"; do
        wait_for_slot
        run_inference "continuousLognormal" "${rep}" "discreteLognormalMedian" "${k}"
    done
done

# Inferences on Discrete Lognormal (Median) Data ---
echo -e "\n[5/5] Inferences on Discrete Lognormal (Median) data..."
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteLognormalMedian_${sim_k}"
            wait_for_slot
            run_inference "${input_data_dir}" "${rep}" "discreteLognormalMedian" "${inf_k}"
        done
    done
done

wait

echo -e "\n✅ All inferences completed successfully."
