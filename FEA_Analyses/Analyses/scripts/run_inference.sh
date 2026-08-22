#!/usr/bin/env bash
# Stage 3: IQ-TREE maximum likelihood inference on all simulated alignments.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <compute_resource> [OPTIONS]"
    echo "Example: $0 local"
    echo "         $0 palmuc"
    exit 1
fi

COMPUTE_RESOURCE=$1
shift

if [[ "$COMPUTE_RESOURCE" != "local" && "$COMPUTE_RESOURCE" != "palmuc" ]]; then
    echo "Compute resource must be 'local' or 'palmuc'!"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYSES_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SLURM_DIR="${ANALYSES_DIR}/slurm"
SLURM_LOGS="${SLURM_DIR}/logs"
PARAMS_FILE="${SLURM_DIR}/params/params.txt"

# Defaults (match analysis_config.R)
ALPHAS="0.649 1.117 3.358"
REPLICATES=1000
INFER_GAMMA_KS="4 16"
FREE_RATE_K=4
MAX_CONCURRENT=500
JOBS_IN_PARALLEL=4
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 <compute_resource> [OPTIONS]

  compute_resource  'local' to run directly, 'palmuc' to submit to SLURM

Options:
  --replicates N       Number of replicates [default: 1000]
  --alphas "..."       Space-separated alpha values [default: "0.649 1.117 3.358"]
  --max-concurrent N   Max concurrent SLURM array tasks [default: 100, palmuc only]
  --parallel N         Parallel jobs for local run (requires GNU parallel) [default: 4]
  --dry-run            Print what would be done without executing
  -h, --help           Show this message

Examples:
  $0 local --replicates 10 --dry-run
  $0 local --replicates 1000 --parallel 8
  $0 palmuc --dry-run
  $0 palmuc --replicates 1000
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --replicates)
            [[ $# -lt 2 ]] && { echo "Error: --replicates requires a value." >&2; exit 1; }
            REPLICATES="$2"; shift 2 ;;
        --alphas)
            [[ $# -lt 2 ]] && { echo "Error: --alphas requires a value." >&2; exit 1; }
            ALPHAS="$2"; shift 2 ;;
        --max-concurrent)
            [[ $# -lt 2 ]] && { echo "Error: --max-concurrent requires a value." >&2; exit 1; }
            MAX_CONCURRENT="$2"; shift 2 ;;
        --parallel)
            [[ $# -lt 2 ]] && { echo "Error: --parallel requires a value." >&2; exit 1; }
            JOBS_IN_PARALLEL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown option '$1'." >&2; usage; exit 1 ;;
    esac
done

read -r -a ALPHA_VALUES <<< "$ALPHAS"
read -r -a GAMMA_K_VALUES <<< "$INFER_GAMMA_KS"
NUM_TASKS=$(( ${#ALPHA_VALUES[@]} * REPLICATES ))

printf '%s  Ferretti pipeline — Stage 3: Inference\n' "$(date '+%F %T')"
printf '%s  Analyses dir : %s\n' "$(date '+%F %T')" "$ANALYSES_DIR"
printf '%s  Alpha values : %s\n' "$(date '+%F %T')" "$ALPHAS"
printf '%s  Replicates   : %d  (total array tasks: %d)\n' "$(date '+%F %T')" "$REPLICATES" "$NUM_TASKS"

if [[ "$COMPUTE_RESOURCE" == "palmuc" ]]; then
    mkdir -p "$SLURM_LOGS" "$(dirname "$PARAMS_FILE")"

    {
        for alpha in "${ALPHA_VALUES[@]}"; do
            for rep in $(seq 1 "$REPLICATES"); do
                echo "${alpha} ${rep}"
            done
        done
    } > "$PARAMS_FILE"

    submit_or_dry() {
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] sbatch $*" >&2
            echo "Submitted batch job DRYRUN_$$"
        else
            sbatch "$@"
        fi
    }

    printf '%s  Submitting Stage 3: IQ-TREE inference (array 1-%d%%%d)...\n' \
        "$(date '+%F %T')" "$NUM_TASKS" "$MAX_CONCURRENT"

    JOB3_OUT=$(submit_or_dry -p krypton \
        --array=1-"${NUM_TASKS}"%"${MAX_CONCURRENT}" \
        --export=ALL,ANALYSES_DIR="${ANALYSES_DIR}",PARAMS_FILE="${PARAMS_FILE}" \
        --output="${SLURM_LOGS}/03_inf_%A_%a.out" \
        --error="${SLURM_LOGS}/03_inf_%A_%a.err" \
        "${SLURM_DIR}/03_run_inference.slurm")
    printf '%s    Stage 3 submitted: %s\n' "$(date '+%F %T')" "$JOB3_OUT"

    printf '%s  Monitor: squeue -u $USER\n' "$(date '+%F %T')"
    printf '%s  Logs   : %s/\n' "$(date '+%F %T')" "$SLURM_LOGS"
    printf '%s  Next   : bash scripts/run_analysis.sh  (after Stage 3 completes)\n' "$(date '+%F %T')"

else
    if [[ "$DRY_RUN" != "true" ]]; then
        command -v iqtree3 >/dev/null 2>&1 || { echo "Error: iqtree3 not found." >&2; exit 1; }
    fi

    JOB_LIST_FILE="${ANALYSES_DIR}/slurm/params/local_inference_jobs.txt"
    mkdir -p "$(dirname "$JOB_LIST_FILE")"
    : > "$JOB_LIST_FILE"

    for alpha in "${ALPHA_VALUES[@]}"; do
        ALN_DIR="${ANALYSES_DIR}/alpha_${alpha}/alignments"
        INF_DIR="${ANALYSES_DIR}/alpha_${alpha}/inference"
        [[ "$DRY_RUN" != "true" ]] && mkdir -p "$INF_DIR"

        for rep in $(seq 1 "$REPLICATES"); do
            CONT_ALN="${ALN_DIR}/cont_${rep}.phy"
            DISC_ALN="${ALN_DIR}/disc_${rep}.phy"

            for gk in "${GAMMA_K_VALUES[@]}"; do
                echo "[[ -s ${INF_DIR}/cont_inf_G${gk}_${rep}.treefile ]] || iqtree3 -s ${CONT_ALN} -m GTR+F+G${gk} -pre ${INF_DIR}/cont_inf_G${gk}_${rep} -nt 1 -quiet -redo" >> "$JOB_LIST_FILE"
                echo "[[ -s ${INF_DIR}/disc_inf_G${gk}_${rep}.treefile ]] || iqtree3 -s ${DISC_ALN} -m GTR+F+G${gk} -pre ${INF_DIR}/disc_inf_G${gk}_${rep} -nt 1 -quiet -redo" >> "$JOB_LIST_FILE"
            done
            echo "[[ -s ${INF_DIR}/cont_inf_R${FREE_RATE_K}_${rep}.treefile ]] || iqtree3 -s ${CONT_ALN} -m GTR+F+R${FREE_RATE_K} -pre ${INF_DIR}/cont_inf_R${FREE_RATE_K}_${rep} -nt 1 -quiet -redo" >> "$JOB_LIST_FILE"
            echo "[[ -s ${INF_DIR}/disc_inf_R${FREE_RATE_K}_${rep}.treefile ]] || iqtree3 -s ${DISC_ALN} -m GTR+F+R${FREE_RATE_K} -pre ${INF_DIR}/disc_inf_R${FREE_RATE_K}_${rep} -nt 1 -quiet -redo" >> "$JOB_LIST_FILE"
        done
    done

    TOTAL_JOBS=$(wc -l < "$JOB_LIST_FILE")
    printf '%s  Total inference jobs: %d\n' "$(date '+%F %T')" "$TOTAL_JOBS"

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY RUN] Would run %d IQ-TREE jobs (%d in parallel)\n' "$TOTAL_JOBS" "$JOBS_IN_PARALLEL"
        printf '  First 3 jobs:\n'
        head -3 "$JOB_LIST_FILE"
    elif command -v parallel >/dev/null 2>&1; then
        printf '%s  Running with GNU parallel (%d jobs)...\n' "$(date '+%F %T')" "$JOBS_IN_PARALLEL"
        parallel --bar -j "$JOBS_IN_PARALLEL" < "$JOB_LIST_FILE"
    else
        printf '%s  GNU parallel not found — running sequentially...\n' "$(date '+%F %T')"
        while IFS= read -r cmd; do
            eval "$cmd"
        done < "$JOB_LIST_FILE"
    fi

    printf '%s  Inference complete. Next: bash scripts/run_analysis.sh\n' "$(date '+%F %T')"
fi
