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

# Function for discrete simulations
run_discrete() {
    local categories=$1
    local output_file="${OUTPUT_DIR}/r_${categories}.out"

    Rscript scripts/r_scripts/simulate_discreteGamma.r \
        -n ${N_SAMPLES} -c ${categories} \
        > "${output_file}" 2>&1
}

# function for continuous simulation
run_continuous() {
  local output_file="${OUTPUT_DIR}/r_continuous.out"

  Rscript scripts/r_scripts/simulate_continuousGamma.r \
      -n ${N_SAMPLES} \
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
echo "Screen output can be found in: ${OUTPUT_DIR}"

# Launch all jobs in parallel
for categories in "${CATEGORIES[@]}"; do
    # Wait for available slot and launch R job
    wait_for_slot
    run_discrete $categories &
done

# Launch continuous simulation
wait_for_slot
run_continuous &

# Wait for all jobs to complete
wait

echo "All simulations completed"
echo "Screen Output saved to: ${OUTPUT_DIR}"
