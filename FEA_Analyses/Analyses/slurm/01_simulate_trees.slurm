#!/bin/bash
#SBATCH --job-name=ferretti_trees
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --qos=normal_prio
#SBATCH --partition=krypton

echo "========================================"
echo "Stage 1: Tree simulation"
echo "Job ID     : ${SLURM_JOB_ID}"
echo "Node       : ${SLURM_NODELIST}"
echo "Started    : $(date)"
echo "ANALYSES_DIR : ${ANALYSES_DIR:-[not set]}"
echo "FORCE_TREES  : ${FORCE_TREES:-0}"
echo "========================================"

module purge
module load gnu/12
module load prebin/kry
module load R/4.4.2

export R_LIBS_USER=\$HOME/R_libs

TREE_SCRIPT="${ANALYSES_DIR}/scripts/trees_simulate.R"
export FORCE_TREES="${FORCE_TREES:-0}"

echo ""
echo "Running: Rscript ${TREE_SCRIPT}"
Rscript "${TREE_SCRIPT}"

echo ""
echo "========================================"
echo "Tree simulation completed: $(date)"
echo "========================================"
