#!/bin/bash
#SBATCH --job-name=ferretti_sim
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --qos=normal_prio
#SBATCH --partition=krypton

echo "========================================"
echo "Stage 2: Alignment simulation"
echo "Job ID   : ${SLURM_JOB_ID},  Task: ${SLURM_ARRAY_TASK_ID}"
echo "Node     : ${SLURM_NODELIST}"
echo "Started  : $(date)"
echo "========================================"

module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry

if ! command -v iqtree2 >/dev/null 2>&1; then
  echo "Error: iqtree2 not found after module load." >&2
  exit 1
fi

if [[ -z "${ANALYSES_DIR:-}" || -z "${PARAMS_FILE:-}" ]]; then
  echo "Error: ANALYSES_DIR and PARAMS_FILE must be set. Submit via run_simulations.sh palmuc." >&2
  exit 1
fi

PARAMS=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${PARAMS_FILE}")
read -r ALPHA REP <<< "${PARAMS}"

if [[ -z "${ALPHA}" || -z "${REP}" ]]; then
  echo "Error: empty params for task ${SLURM_ARRAY_TASK_ID} in ${PARAMS_FILE}" >&2
  exit 1
fi

echo "Alpha: ${ALPHA},  Replicate: ${REP}"

ALPHA_DIR="${ANALYSES_DIR}/alpha_${ALPHA}"
TREE_FILE="${ANALYSES_DIR}/trees/tree_${REP}.nwk"
ALN_DIR="${ALPHA_DIR}/alignments"
mkdir -p "${ALN_DIR}"

CONT_PREFIX="${ALN_DIR}/cont_${REP}"
DISC_PREFIX="${ALN_DIR}/disc_${REP}"

if [[ ! -s "${TREE_FILE}" ]]; then
  echo "Error: tree file not found or empty: ${TREE_FILE}" >&2
  exit 1
fi

if [[ -s "${CONT_PREFIX}.phy" ]]; then
  echo "  cont_${REP}.phy already exists — skipping"
else
  echo "  Simulating continuous-Gamma alignment (alpha=${ALPHA}, rep=${REP})..."
  iqtree2 --alisim "${CONT_PREFIX}" \
    -t "${TREE_FILE}" \
    -m "GTR+F{0.25,0.25,0.25,0.25}+GC{${ALPHA}}" \
    --length 2500 \
    --quiet -redo
  echo "  Done: ${CONT_PREFIX}.phy"
fi

if [[ -s "${DISC_PREFIX}.phy" ]]; then
  echo "  disc_${REP}.phy already exists — skipping"
else
  echo "  Simulating discrete-Gamma k=4 alignment (alpha=${ALPHA}, rep=${REP})..."
  iqtree2 --alisim "${DISC_PREFIX}" \
    -t "${TREE_FILE}" \
    -m "GTR+F{0.25,0.25,0.25,0.25}+G4{${ALPHA}}" \
    --length 2500 \
    --quiet -redo
  echo "  Done: ${DISC_PREFIX}.phy"
fi

echo ""
echo "========================================"
echo "Simulation task ${SLURM_ARRAY_TASK_ID} completed: $(date)"
echo "========================================"
