#!/bin/bash

# Simulation Script
# This script runs calls appropriate R and Rev scripts to simulate datasets
# Author: Basanta Khakurel
# Date: 2025-09-03
# Warning: The continuous gamma simulations take a bit longer to run.

set -euo pipefail

# Number of repetitions for each simulation
N_REPS=2
# Number of categories for discrete simulations
CATEGORIES=(2 4 8)
# Maximum number of simulations to run at once
MAX_JOBS=6
# Base data directory
BASE_DATA_DIR="data"
# screen output directory
LOG_DIR="simulation_screen_outputs"

echo "Setting up output directories..."
mkdir -p "${LOG_DIR}"

# Create all data subdirectories
for cats in "${CATEGORIES[@]}"; do
    mkdir -p "${BASE_DATA_DIR}/discreteGammaMean_${cats}"
    mkdir -p "${BASE_DATA_DIR}/discreteGammaMedian_${cats}"
    mkdir -p "${BASE_DATA_DIR}/discreteLognormalMedian_${cats}"
done

mkdir -p "${BASE_DATA_DIR}/continuousGamma"
mkdir -p "${BASE_DATA_DIR}/continuousLognormal"
echo "Data directories created in: ${BASE_DATA_DIR}"


# Waits for a free slot before starting a new job.
wait_for_slot() {
    while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
        sleep 0.5
    done
}

# function to run a discrete simulation using RevBayes
run_discrete_simulation() {
    local sim_name="$1"
    local script_path="$2"
    local categories="$3"
    local rb_output_arg="${sim_name}_${categories}"
    local log_file="${LOG_DIR}/${sim_name}_${categories}cat.log"

    echo "-> Starting: ${sim_name} with ${categories} categories. Log: ${log_file}"

    rb "${script_path}" --args "${N_REPS}" "${categories}" "${rb_output_arg}" > "${log_file}" 2>&1
}

# function to run the continuous Gamma simulation using R
run_continuous_gamma() {
    local sim_name="continuousGamma"
    local script_path="scripts/r_scripts/simulate_continuousGamma.r"
    local data_dir="${BASE_DATA_DIR}/${sim_name}"
    local log_file="${LOG_DIR}/${sim_name}.log"

    echo "-> Starting: ${sim_name} simulations. Log: ${log_file}"

    Rscript "${script_path}" --n_reps "${N_REPS}" --output_dir "${data_dir}" > "${log_file}" 2>&1
}

# function to run the continuous Lognormal simulation using R
run_continuous_lognormal() {
    local sim_name="continuousLognormal"
    local script_path="scripts/r_scripts/simulate_continuousLognormal.r"
    local data_dir="${BASE_DATA_DIR}/${sim_name}"
    local log_file="${LOG_DIR}/${sim_name}.log"

    echo "-> Starting: ${sim_name} simulations. Log: ${log_file}"

    Rscript "${script_path}" --n_reps "${N_REPS}" --output_dir "${data_dir}" > "${log_file}" 2>&1
}


echo -e "\nStarting parallel simulations with a maximum of ${MAX_JOBS} jobs."
echo "Screen output is stored in: ${LOG_DIR}"

# Discrete Simulations
for cats in "${CATEGORIES[@]}"; do
    wait_for_slot
    run_discrete_simulation "discreteGammaMean" "scripts/Rev_scripts/simulate_discreteGammaMean.Rev" "${cats}" &

    wait_for_slot
    run_discrete_simulation "discreteGammaMedian" "scripts/Rev_scripts/simulate_discreteGammaMedian.Rev" "${cats}" &

    wait_for_slot
    run_discrete_simulation "discreteLognormalMedian" "scripts/Rev_scripts/simulate_discreteLognormalMedian.Rev" "${cats}" &
done

# Continuous Simulations
wait_for_slot
run_continuous_gamma &

wait_for_slot
run_continuous_lognormal &

wait

echo -e "\n✅ All simulations completed successfully."
echo "Results saved to: ${BASE_DATA_DIR}"
