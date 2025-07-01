#!/bin/bash

# Parallel inference script
# Usage: ./run_infer_local.sh [max_parallel_jobs]

set -euo pipefail

# Configuration
TRUE_CATEGORIES=(2 4 6 8 16 100 cont)
INFERRED_CATEGORIES=(0 2 4 6 8 16 100)
N_REPS=20
N_CHAINS=2
MAX_JOBS=${1:-$(nproc)}
SCRIPT="scripts/rev_scripts/mcmc.Rev"
OUTPUT_DIR="inference_screen_outputs"

# create the screen output directory
mkdir -p "${OUTPUT_DIR}"

# function to run mcmc
run_mcmc() {
    local sim=$1
    local true_cat=$2
    local inf_cat=$3

    if [[ $true_cat == "cont" && $inf_cat -eq 0 ]]; then
        local model="ContinuousGamma"
    elif [[ $inf_cat -ne 0 ]]; then
        local model="DiscreteGamma"
    else
        return 0  # skip invalid combination
    fi

    local output_name="output_sim_${true_cat}cats_inf_${inf_cat}cats"
    local log_file="${OUTPUT_DIR}/${output_name}_sim${sim}.log"

    echo "Launching sim ${sim} | true=${true_cat}, inf=${inf_cat}"

    # mpirun -np <NUM_PROCESSORS> rb-mpi --file scripts/rev_scripts/mcmc.Rev --args <DATA_NAAME> <DATA_DIRECTORY> <MODEL> <OUTPUT_DIRECTORY> <NUM_MCMC_CHAINS> <NUMBER_OF_CATEGORIES>

    mpirun -np $N_CHAINS rb-mpi \
        --file "${SCRIPT}" \
        --args "sim_${sim}" "sim_${true_cat}" "${model}" "${output_name}" "${N_CHAINS}" "${inf_cat}" \
        > "${log_file}" 2>&1
}

# Function to wait for available job slot
wait_for_slot() {
    while [ "$(jobs -r | wc -l)" -ge "${MAX_JOBS}" ]; do
        sleep 0.1
    done
}

# Main execution
echo "Starting RevBayes MCMC runs with max ${MAX_JOBS} parallel jobs"
echo "Screen output is saved to: ${OUTPUT_DIR}"

# Loop over reps and category combinations
for sim in $(seq 1 ${N_REPS}); do
    for true_cat in "${TRUE_CATEGORIES[@]}"; do
        for inf_cat in "${INFERRED_CATEGORIES[@]}"; do
            wait_for_slot
            run_mcmc "$sim" "$true_cat" "$inf_cat" &
        done
    done
done

# Wait for all jobs to complete
wait

echo "All MCMC jobs completed"
echo "Screen output saved to: ${OUTPUT_DIR}"
