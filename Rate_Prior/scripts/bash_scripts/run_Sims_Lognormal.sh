#!/bin/bash

# Simulation Script - Lognormal (Specified Orders of Magnitude)
# This script runs all 12 specified R and RevBayes simulations
# in parallel, grouped by order of magnitude.

set -euo pipefail

# --- Configuration ---
N_REPS=2
CATEGORIES=(2 4 8)
MAX_JOBS=6 # Max parallel jobs to run at once
LOG_DIR="simulation_screen_outputs"
BASE_DATA_DIR="data" # Base for all output

# Define the orders of magnitude and their corresponding 's' values
# This uses a bash associative array (hash map)
declare -A ORDERS_OF_MAGNITUDE
ORDERS_OF_MAGNITUDE[one_order]="0.5874"
ORDERS_OF_MAGNITUDE[two_order]="1.1748"
ORDERS_OF_MAGNITUDE[three_order]="1.7622"

# --- Setup ---
echo "Setting up output directories..."
mkdir -p "${LOG_DIR}"

# Create directories for each order of magnitude
for order_name in "${!ORDERS_OF_MAGNITUDE[@]}"; do
    # Create the full path required by the R script
    mkdir -p "${BASE_DATA_DIR}/${order_name}/continuousLognormal"

    # Create the base path required by the Rev script's output argument
    mkdir -p "${BASE_DATA_DIR}/${order_name}"
done
echo "Data directories created in: ${BASE_DATA_DIR}"

# --- Helper Functions ---

# Waits for a free slot before starting a new job.
wait_for_slot() {
    # Counts the number of running jobs (jobs -r)
    while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
        sleep 0.5
    done
}

# function to run a single continuous Lognormal R simulation
run_continuous_lognormal() {
    local order_name="$1"
    local s_value="$2"

    local output_dir="${BASE_DATA_DIR}/${order_name}/continuousLognormal"
    local log_file="${LOG_DIR}/continuous_${order_name}.log"

    echo "-> Starting: Continuous ${order_name}. Log: ${log_file}"

    # Runs the R script with the specified arguments
    Rscript scripts/r_scripts/simulate_continuousLognormal.r \
        -n "${N_REPS}" \
        -s "${s_value}" \
        -o "${output_dir}" > "${log_file}" 2>&1
}

# function to run a single discrete Lognormal RevBayes simulation
run_discrete_lognormal() {
    local order_name="$1"
    local s_value="$2"
    local categories="$3"

    # This matches the output argument like "one_order/discreteLognormalMedian_2"
    local rb_output_arg="${order_name}/discreteLognormalMedian_${categories}"
    local log_file="${LOG_DIR}/discrete_${order_name}_${categories}cat.log"

    echo "-> Starting: Discrete ${order_name} with ${categories} categories. Log: ${log_file}"

    # Runs the RevBayes script with the specified arguments
    rb scripts/Rev_scripts/simulate_discreteLognormalMedian.Rev \
        "${N_REPS}" \
        "${categories}" \
        "${rb_output_arg}" \
        "${s_value}" > "${log_file}" 2>&1
}

# --- Main Execution ---
echo -e "\n Starting Lognormal simulations with a maximum of ${MAX_JOBS} jobs."
echo "Screen output is stored in: ${LOG_DIR}"

# Loop through each defined order of magnitude (one_order, two_order, etc.)
for order_name in "${!ORDERS_OF_MAGNITUDE[@]}"; do
    s_value=${ORDERS_OF_MAGNITUDE[$order_name]}
    echo -e "\n--- Processing: ${order_name} (s_value = ${s_value}) ---"

    # 1. Start continuous simulation for this order
    wait_for_slot
    run_continuous_lognormal "${order_name}" "${s_value}" &

    # 2. Start all discrete simulations for this order
    for cats in "${CATEGORIES[@]}"; do
        wait_for_slot
        run_discrete_lognormal "${order_name}" "${s_value}" "${cats}" &
    done
done

# Wait for all background jobs (&) to finish
wait

echo -e "\n All Lognormal simulations completed successfully."
echo "Results saved to: ${BASE_DATA_DIR}"
