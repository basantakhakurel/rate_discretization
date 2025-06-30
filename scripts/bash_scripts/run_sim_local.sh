#!/bin/bash

# Parallel simulation script
# Usage: ./simulate_parallel.sh [max_parallel_jobs]

set -euo pipefail

# Configuration
CATEGORIES=(2 4 6 8 16 100)
N_SAMPLES=20
MAX_JOBS=${1:-$(nproc)}
OUTPUT_DIR="simulation_screen_outputs"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Function to run R simulation
run_r() {
    local categories=$1
    local output_file="${OUTPUT_DIR}/r_${categories}.out"

    Rscript scripts/r_scripts/simulate_discreteGamma.r \
        -n ${N_SAMPLES} -c ${categories} \
        > "${output_file}" 2>&1
}

# Function to wait for available job slot
wait_for_slot() {
    while [ $(jobs -r | wc -l) -ge $MAX_JOBS ]; do
        sleep 0.1
    done
}

# Main execution
echo "Starting parallel simulations with ${MAX_JOBS} max parallel jobs"
echo "Output directory: ${OUTPUT_DIR}"

# Launch all jobs in parallel
for categories in "${CATEGORIES[@]}"; do
    # Wait for available slot and launch R job
    wait_for_slot
    run_r $categories &
done

# Wait for all jobs to complete
wait

echo "All simulations completed"
echo "Output files saved to: ${OUTPUT_DIR}"
