#!/bin/bash
#SBATCH --job-name=ferretti_inf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --qos=normal_prio
#SBATCH --partition=krypton

echo "========================================"
echo "Stage 3: IQ-TREE inference"
echo "Job ID   : ${SLURM_JOB_ID},  Task: ${SLURM_ARRAY_TASK_ID}"
echo "Node     : ${SLURM_NODELIST}"
echo "Started  : $(date)"
echo "========================================"

module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry

PARAMS=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${PARAMS_FILE}")
read -r ALPHA REP <<< "${PARAMS}"

if [[ -z "${ALPHA}" || -z "${REP}" ]]; then
  echo "Error: empty params for task ${SLURM_ARRAY_TASK_ID} in ${PARAMS_FILE}" >&2
  exit 1
fi

echo "Alpha: ${ALPHA},  Replicate: ${REP}"

ALPHA_DIR="${ANALYSES_DIR}/alpha_${ALPHA}"
INF_DIR="${ALPHA_DIR}/inference"
mkdir -p "${INF_DIR}"

run_inference() {
  local alignment="$1"
  local model="$2"
  local prefix="$3"
  local label="${prefix##*/}"

  if [[ ! -s "${alignment}" ]]; then
    echo "  Warning: alignment missing, skipping ${label}: ${alignment}" >&2
    return
  fi

  if [[ -s "${prefix}.treefile" ]]; then
    echo "  ${label}.treefile exists — skipping"
    return
  fi

  echo "  Inferring ${label}  (model: ${model})..."
  iqtree2 -s "${alignment}" -m "${model}" -pre "${prefix}" -nt 1 -quiet -redo
  echo "  Done: ${prefix}.treefile"
}

CONT_ALN="${ALPHA_DIR}/alignments/cont_${REP}.phy"
DISC_ALN="${ALPHA_DIR}/alignments/disc_${REP}.phy"

echo ""
echo "--- Continuous-Gamma alignments ---"
run_inference "${CONT_ALN}" "GTR+F+G4"  "${INF_DIR}/cont_inf_G4_${REP}"
run_inference "${CONT_ALN}" "GTR+F+G16" "${INF_DIR}/cont_inf_G16_${REP}"
run_inference "${CONT_ALN}" "GTR+F+R4"  "${INF_DIR}/cont_inf_R4_${REP}"

echo ""
echo "--- Discrete-Gamma k=4 alignments ---"
run_inference "${DISC_ALN}" "GTR+F+G4"  "${INF_DIR}/disc_inf_G4_${REP}"
run_inference "${DISC_ALN}" "GTR+F+G16" "${INF_DIR}/disc_inf_G16_${REP}"
run_inference "${DISC_ALN}" "GTR+F+R4"  "${INF_DIR}/disc_inf_R4_${REP}"

echo ""
echo "========================================"
echo "Inference task ${SLURM_ARRAY_TASK_ID} completed: $(date)"
echo "========================================"
