#!/bin/bash

# SLURM Submission Script - Lognormal Inference
# This script submits SLURM array jobs for Lognormal simulated datasets only,
# with the folders structure (one_order, two_order, three_order).
# Author: Basanta Khakurel
# Date: 2025-11-10

set -euo pipefail

# --- Configuration ---

# Number of simulation replicates
N_REPS=2
# Path to main RevBayes MCMC script
REV_SCRIPT="scripts/Rev_scripts/mcmc.Rev"

# Categories used IN THE SIMULATION (sim_k)
SIM_CATEGORIES=(2 4 8)
# Categories to use FOR INFERENCE (inf_k)
INF_CATEGORIES=(2 4 8 16 100)
# Orders of magnitude (matching the folders created by simulation scripts)
ORDERS_OF_MAGNITUDE=(one_order two_order three_order)

# --- SLURM & Output Directories ---
BASE_OUTPUT_DIR="Lognormal_Test"
LOG_DIR="slurm_logs"
SLURM_SCRIPT_DIR="slurm_scripts"
PARAMS_DIR="slurm_params"

echo "Setting up directories ..."
mkdir -p "${BASE_OUTPUT_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${SLURM_SCRIPT_DIR}"
mkdir -p "${PARAMS_DIR}"

# --- Function to generate and submit a SLURM job ---
# this function creates a SLURM script and submits it using sbatch
# name of the job and parameter file passed
generate_and_submit() {
    local job_name="$1"
    local params_content="$2"
    local params_file="${PARAMS_DIR}/params_${job_name}.txt"
    local slurm_script="${SLURM_SCRIPT_DIR}/run_${job_name}.slurm"

    # analysis settings to a file for easier tracking
    echo -e "${params_content}" > "${params_file}"

    # total number of jobs for the array
    local num_jobs=$(grep -c . "${params_file}")

    if [ "${num_jobs}" -eq 0 ]; then
        echo "--> No jobs to generate for ${job_name}. Skipping."
        return
    fi

    echo "--> Generating SLURM script for '${job_name}' with ${num_jobs} tasks: ${slurm_script}"

    # make the SLURM script
    cat <<EOT > "${slurm_script}"
#!/bin/bash
#SBATCH --job-name=${job_name}
#SBATCH --output=${LOG_DIR}/${job_name}_%A_%a.out
#SBATCH --error=${LOG_DIR}/${job_name}_%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=8G
#SBATCH --qos=normal_prio
#SBATCH --partition=krypton
#SBATCH --array=1-${num_jobs}

echo "Starting SLURM task \${SLURM_ARRAY_TASK_ID} for job \${SLURM_JOB_NAME} (\${SLURM_JOB_ID})."

# Load necessary modules
module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry

# Read lines of the parameter file for analysis combinations
PARAMS=\$(sed -n "\${SLURM_ARRAY_TASK_ID}p" "${params_file}")
read -r input_subdir rep_num inf_model inf_k <<< "\$PARAMS"

echo "Running with parameters: \$PARAMS"

# variables and path
data_name="sim_\${rep_num}"
# The '/' in input_subdir is handled correctly here
output_subdir="on_\${input_subdir}/with_\${inf_model}_k\${inf_k}/sim_\${rep_num}"
output_dir="${BASE_OUTPUT_DIR}/\${output_subdir}"

# output directory
mkdir -p "\${output_dir}"

# The input_subdir will be e.g. "one_order/continuousLognormal"
echo "-> Inference on: data/\${input_subdir}/\${data_name}"
echo "-> Model: \${inf_model} (k=\${inf_k})"
echo "-> Output Dir: \${output_dir}"

srun rb-mpi --file "${REV_SCRIPT}" \
    --args "\${data_name}" "\${input_subdir}" "\${inf_model}" "\${output_dir}" 4 "\${inf_k}"

echo "Analysis \${SLURM_ARRAY_TASK_ID} completed."
EOT

    # Submit the job
    sbatch "${slurm_script}"
}

# --- Job Generation and Submission ---

echo -e "\nGenerating and submitting SLURM jobs for Lognormal models..."

# 1. Inferences on Continuous Lognormal Simulations
echo -e "\n[1/2] Processing Continuous Lognormal data (all orders)..."
PARAMS=""
for order_name in "${ORDERS_OF_MAGNITUDE[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for k in "${INF_CATEGORIES[@]}"; do
            input_subdir="${order_name}/continuousLognormal"
            PARAMS+="${input_subdir} ${rep} discreteLognormalMedian ${k}\n"
        done
    done
done
generate_and_submit "continuousLognormal" "${PARAMS}"

# 2. Inferences on Median Discrete Lognormal Simulations
echo -e "\n[2/2] Processing Discrete Lognormal (Median) data (all orders)..."
PARAMS=""
for order_name in "${ORDERS_OF_MAGNITUDE[@]}"; do
    for sim_k in "${SIM_CATEGORIES[@]}"; do
        for rep in $(seq 1 "${N_REPS}"); do
            for inf_k in "${INF_CATEGORIES[@]}"; do
                input_subdir="${order_name}/discreteLognormalMedian_${sim_k}"
                PARAMS+="${input_subdir} ${rep} discreteLognormalMedian ${inf_k}\n"
            done
        done
    done
done
generate_and_submit "discreteLognormalMedian" "${PARAMS}"

echo -e "\nAll Lognormal jobs submitted."
