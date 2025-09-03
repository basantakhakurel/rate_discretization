#!/bin/bash

# SLURM Submission Script
# This script submits SLURM array jobs fro simulated datasets.
# Author: Basanta Khakurel
# Date: 2025-09-03

set -euo pipefail

# Number of simulation replicates
N_REPS=5
# Path to main RevBayes MCMC script
REV_SCRIPT="scripts/Rev_scripts/mcmc.Rev"

SIM_CATEGORIES=(2 4 8)
INF_CATEGORIES=(2 4 8 16 100)

# Output directory
BASE_OUTPUT_DIR="inference_results"
# slurm log directory
LOG_DIR="slurm_logs"
# slurm scripts directory
SLURM_SCRIPT_DIR="slurm_scripts"
# directory for parameter files for each job
PARAMS_DIR="slurm_params"

echo "Setting up directories ..."
mkdir -p "${BASE_OUTPUT_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${SLURM_SCRIPT_DIR}"
mkdir -p "${PARAMS_DIR}"

# Function to generate and submit a SLURM job
# this function creates a SLUMR script and submits it using sbatch
# name of the job and parameter file passed
generate_and_submit() {
    local job_name="$1"
    local params_content="$2"
    local params_file="${PARAMS_DIR}/params_${job_name}.txt"
    local slurm_script="${SLURM_SCRIPT_DIR}/run_${job_name}.slurm"

    # analysis settings to a file for easier tracking
    echo -e "${params_content}" > "${params_file}"

    # total number of jobs for the array
    local num_jobs=$(wc -l < "${params_file}")

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
output_subdir="on_\${input_subdir}/with_\${inf_model}_k\${inf_k}/sim_\${rep_num}"
output_dir="${BASE_OUTPUT_DIR}/\${output_subdir}"

# output directory
mkdir -p "\${output_dir}"

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

# Actually submiut the jobs now

echo -e "\nGenerating and submitting SLURM jobs..."

# 1. Inferences on the Continuous Gamma Simulations
echo -e "\n[1/5] Processing Continuous Gamma data..."
PARAMS=""
for rep in $(seq 1 "${N_REPS}"); do
    for k in "${INF_CATEGORIES[@]}"; do
        PARAMS+="continuousGamma ${rep} discreteGammaMean ${k}\n"
        PARAMS+="continuousGamma ${rep} discreteGammaMedian ${k}\n"
    done
done
generate_and_submit "continuousGamma" "${PARAMS}"

# 2. Inferences on Mean Discrete Gamma Simulations
echo -e "\n[2/5] Processing Discrete Gamma (Mean) data..."
PARAMS=""
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteGammaMean_${sim_k}"
            PARAMS+="${input_data_dir} ${rep} discreteGammaMean ${inf_k}\n"
            PARAMS+="${input_data_dir} ${rep} discreteGammaMedian ${inf_k}\n"
        done
    done
done
generate_and_submit "discreteGammaMean" "${PARAMS}"

# 3. Inferences on Median Discrete Gamma Simulations
echo -e "\n[3/5] Processing Discrete Gamma (Median) data..."
PARAMS=""
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteGammaMedian_${sim_k}"
            PARAMS+="${input_data_dir} ${rep} discreteGammaMean ${inf_k}\n"
            PARAMS+="${input_data_dir} ${rep} discreteGammaMedian ${inf_k}\n"
        done
    done
done
generate_and_submit "discreteGammaMedian" "${PARAMS}"

# 4. Inferences on Continuous Lognormal Simulations
echo -e "\n[4/5] Processing Continuous Lognormal data..."
PARAMS=""
for rep in $(seq 1 "${N_REPS}"); do
    for k in "${INF_CATEGORIES[@]}"; do
        PARAMS+="continuousLognormal ${rep} discreteLognormalMedian ${k}\n"
    done
done
generate_and_submit "continuousLognormal" "${PARAMS}"

# 5. Inferences on Median Discrete Lognormal Simulations
echo -e "\n[5/5] Processing Discrete Lognormal (Median) data..."
PARAMS=""
for sim_k in "${SIM_CATEGORIES[@]}"; do
    for rep in $(seq 1 "${N_REPS}"); do
        for inf_k in "${INF_CATEGORIES[@]}"; do
            input_data_dir="discreteLognormalMedian_${sim_k}"
            PARAMS+="${input_data_dir} ${rep} discreteLognormalMedian ${inf_k}\n"
        done
    done
done
generate_and_submit "discreteLognormalMedian" "${PARAMS}"

echo -e "\nAll jobs submitted."
