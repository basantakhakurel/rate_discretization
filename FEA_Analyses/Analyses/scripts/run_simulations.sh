#!/usr/bin/env bash
# Stages 1 + 2: generate trees (R) then simulate alignments (IQ-TREE alisim).
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

TREE_SCRIPT="${SCRIPT_DIR}/trees_simulate.R"
SLURM_DIR="${ANALYSES_DIR}/slurm"
SLURM_LOGS="${SLURM_DIR}/logs"
PARAMS_FILE="${SLURM_DIR}/params/params.txt"

ALPHAS="0.649 1.117 3.358"
REPLICATES=1000
FORCE_TREES=0
MAX_CONCURRENT=500
SIM_BATCH_SIZE=10
ALIGNMENT_LENGTH=25000
SIM_GAMMA_K=4
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 <compute_resource> [OPTIONS]

  compute_resource  'local' to run directly, 'palmuc' to submit to SLURM

Options:
  --replicates N       Number of replicates [default: 1000]
  --alphas "..."       Space-separated alpha values [default: "0.649 1.117 3.358"]
  --force-trees        Regenerate trees even if they already exist
  --max-concurrent N   Max concurrent SLURM array tasks [default: 100, palmuc only]
  --batch-size N       Background jobs per batch for alisim [default: 10, local only]
  --dry-run            Print what would be done without executing
  -h, --help           Show this message

Examples:
  $0 local --replicates 10 --dry-run
  $0 local --replicates 1000
  $0 palmuc --replicates 1000 --dry-run
  $0 palmuc --replicates 1000 --force-trees
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
        --force-trees) FORCE_TREES=1; shift ;;
        --max-concurrent)
            [[ $# -lt 2 ]] && { echo "Error: --max-concurrent requires a value." >&2; exit 1; }
            MAX_CONCURRENT="$2"; shift 2 ;;
        --batch-size)
            [[ $# -lt 2 ]] && { echo "Error: --batch-size requires a value." >&2; exit 1; }
            SIM_BATCH_SIZE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown option '$1'." >&2; usage; exit 1 ;;
    esac
done

read -r -a ALPHA_VALUES <<< "$ALPHAS"
NUM_TASKS=$(( ${#ALPHA_VALUES[@]} * REPLICATES ))

printf '%s  Ferretti pipeline — Stage 1+2: Simulation\n' "$(date '+%F %T')"
printf '%s  Analyses dir : %s\n' "$(date '+%F %T')" "$ANALYSES_DIR"
printf '%s  Alpha values : %s\n' "$(date '+%F %T')" "$ALPHAS"
printf '%s  Replicates   : %d  (total array tasks: %d)\n' "$(date '+%F %T')" "$REPLICATES" "$NUM_TASKS"
printf '%s  Force trees  : %d\n' "$(date '+%F %T')" "$FORCE_TREES"

if [[ "$COMPUTE_RESOURCE" == "palmuc" ]]; then
    mkdir -p "$SLURM_LOGS" "$(dirname "$PARAMS_FILE")"

    {
        for alpha in "${ALPHA_VALUES[@]}"; do
            for rep in $(seq 1 "$REPLICATES"); do
                echo "${alpha} ${rep}"
            done
        done
    } > "$PARAMS_FILE"
    printf '%s  Params file  : %s  (%d lines)\n' "$(date '+%F %T')" "$PARAMS_FILE" "$NUM_TASKS"

    submit_or_dry() {
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] sbatch $*" >&2
            echo "Submitted batch job DRYRUN_$$"
        else
            sbatch "$@"
        fi
    }
    extract_job_id() { awk '{print $NF}'; }

    printf '%s  Submitting Stage 1: tree simulation...\n' "$(date '+%F %T')"
    JOB1_OUT=$(submit_or_dry -p krypton \
        --export=ALL,ANALYSES_DIR="${ANALYSES_DIR}",FORCE_TREES="${FORCE_TREES}" \
        --output="${SLURM_LOGS}/01_trees_%j.out" \
        --error="${SLURM_LOGS}/01_trees_%j.err" \
        "${SLURM_DIR}/01_simulate_trees.slurm")
    JOB1_ID=$(echo "$JOB1_OUT" | extract_job_id)
    printf '%s    Stage 1 submitted: %s\n' "$(date '+%F %T')" "$JOB1_OUT"

    printf '%s  Submitting Stage 2: alignment simulation (array 1-%d%%%d)...\n' \
        "$(date '+%F %T')" "$NUM_TASKS" "$MAX_CONCURRENT"
    JOB2_OUT=$(submit_or_dry -p krypton \
        --dependency=afterok:"${JOB1_ID}" \
        --array=1-"${NUM_TASKS}"%"${MAX_CONCURRENT}" \
        --export=ALL,ANALYSES_DIR="${ANALYSES_DIR}",PARAMS_FILE="${PARAMS_FILE}" \
        --output="${SLURM_LOGS}/02_sim_%A_%a.out" \
        --error="${SLURM_LOGS}/02_sim_%A_%a.err" \
        "${SLURM_DIR}/02_simulate_alignments.slurm")
    JOB2_ID=$(echo "$JOB2_OUT" | extract_job_id)
    printf '%s    Stage 2 submitted: %s  (depends on %s)\n' "$(date '+%F %T')" "$JOB2_OUT" "$JOB1_ID"

    printf '%s  Monitor: squeue -u $USER\n' "$(date '+%F %T')"
    printf '%s  Logs   : %s/\n' "$(date '+%F %T')" "$SLURM_LOGS"
    printf '%s  Next   : bash scripts/run_inference.sh palmuc  (after Stage 2 completes)\n' "$(date '+%F %T')"

else
    if [[ "$DRY_RUN" != "true" ]]; then
        command -v iqtree2 >/dev/null 2>&1 || { echo "Error: iqtree2 not found." >&2; exit 1; }
        command -v Rscript >/dev/null 2>&1 || { echo "Error: Rscript not found." >&2; exit 1; }
    fi

    # generate trees
    printf '%s  Stage 1: Generating trees...\n' "$(date '+%F %T')"
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [DRY RUN] Would run: FORCE_TREES=%d Rscript %s\n' "$FORCE_TREES" "$TREE_SCRIPT"
    else
        FORCE_TREES=$FORCE_TREES Rscript "$TREE_SCRIPT"
        printf '%s  Trees generated.\n' "$(date '+%F %T')"
    fi

    # simulate alignments
    for alpha in "${ALPHA_VALUES[@]}"; do
        ALN_DIR="${ANALYSES_DIR}/alpha_${alpha}/alignments"
        TREE_DIR="${ANALYSES_DIR}/trees"

        printf '%s  Stage 2: Simulating alignments for alpha=%s...\n' "$(date '+%F %T')" "$alpha"

        [[ "$DRY_RUN" != "true" ]] && mkdir -p "$ALN_DIR"

        n_jobs=0
        for rep in $(seq 1 "$REPLICATES"); do
            TREE_FILE="${TREE_DIR}/tree_${rep}.nwk"
            CONT_PREFIX="${ALN_DIR}/cont_${rep}"
            DISC_PREFIX="${ALN_DIR}/disc_${rep}"

            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY RUN] alpha=${alpha} rep=${rep}: alisim cont + disc"
                continue
            fi

            if [[ ! -s "$TREE_FILE" ]]; then
                printf 'Error: tree file missing: %s\n' "$TREE_FILE" >&2; exit 1
            fi

            if [[ ! -s "${CONT_PREFIX}.phy" ]]; then
                iqtree2 --alisim "$CONT_PREFIX" \
                    -t "$TREE_FILE" \
                    -m "GTR+F{0.25,0.25,0.25,0.25}+GC{${alpha}}" \
                    --length "$ALIGNMENT_LENGTH" --quiet -redo &
                ((n_jobs++)) || true
            fi

            if [[ ! -s "${DISC_PREFIX}.phy" ]]; then
                iqtree2 --alisim "$DISC_PREFIX" \
                    -t "$TREE_FILE" \
                    -m "GTR+F{0.25,0.25,0.25,0.25}+G${SIM_GAMMA_K}{${alpha}}" \
                    --length "$ALIGNMENT_LENGTH" --quiet -redo &
                ((n_jobs++)) || true
            fi

            if ((n_jobs > 0 && n_jobs % SIM_BATCH_SIZE == 0)); then wait; fi
        done
        [[ "$DRY_RUN" != "true" ]] && wait
        printf '%s  Alignments done for alpha=%s.\n' "$(date '+%F %T')" "$alpha"
    done

    printf '%s  Simulation complete. Next: bash scripts/run_inference.sh local\n' "$(date '+%F %T')"
fi
