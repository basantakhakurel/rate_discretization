#!/usr/bin/env bash
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SCENARIOS_FILE="${REPO_ROOT}/simConfigs.tsv"
MCMC_SCRIPT="${REPO_ROOT}/scripts/rev/mcmc.Rev"
MODELS_DIR="${REPO_ROOT}/scripts/rev/models"
INPUT_ROOT="${REPO_ROOT}/SimData"
OUTPUT_ROOT="${REPO_ROOT}/InferenceOutput"
LOG_ROOT="${REPO_ROOT}/inference_logs"
SLURM_LOGS="${REPO_ROOT}/slurm/logs"
SLURM_SCRIPTS="${REPO_ROOT}/slurm/scripts"
PARAMS_DIR="${REPO_ROOT}/slurm/params"

GLOBAL_N_REPS=""
DRY_RUN=false
declare -a SELECTED_SCENARIOS=()
INF_CATEGORIES=(2 4 8 16 100)

usage() {
    cat <<EOF
Usage: $0 <compute_resource> [OPTIONS]

  compute_resource  'local' to run directly, 'palmuc' to submit to SLURM

Options:
  --n-reps N       Limit to first N replicates per scenario
  --scenario ID    Run only the specified scenario (repeatable)
  --inf-k K        Comma-separated inference categories [default: 2,4,8,16,100]
  --dry-run        Print what would be done without executing
  -h, --help       Show this message

Examples:
  $0 local --dry-run --n-reps 2
  $0 local --scenario 8taxa_1order_continuousGamma --inf-k 4,8
  $0 palmuc --n-reps 25
  $0 palmuc --inf-k 4,8,16 --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --n-reps)
            [[ $# -lt 2 ]] && { echo "Error: --n-reps requires a value." >&2; exit 1; }
            GLOBAL_N_REPS="$2"; shift 2 ;;
        --scenario)
            [[ $# -lt 2 ]] && { echo "Error: --scenario requires a value." >&2; exit 1; }
            SELECTED_SCENARIOS+=("$2"); shift 2 ;;
        --inf-k)
            [[ $# -lt 2 ]] && { echo "Error: --inf-k requires a value." >&2; exit 1; }
            IFS=',' read -ra INF_CATEGORIES <<< "$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown option '$1'." >&2; usage; exit 1 ;;
    esac
done

if [[ ! -f "$SCENARIOS_FILE" ]]; then
    printf '%s  ERROR: Config file not found: %s\n' "$(date '+%F %T')" "$SCENARIOS_FILE" >&2
    exit 1
fi

should_run_scenario() {
    local id="$1"
    [[ ${#SELECTED_SCENARIOS[@]} -eq 0 ]] && return 0
    for s in "${SELECTED_SCENARIOS[@]}"; do [[ "$id" == "$s" ]] && return 0; done
    return 1
}

get_inference_models() {
    case "$1" in
        continuousGamma|discreteGammaMean|discreteGammaMedian)
            echo "discreteGammaMean discreteGammaMedian" ;;
        continuousLognormal|discreteLognormalMedian)
            echo "discreteLognormalMedian" ;;
        *) echo "" ;;
    esac
}

declare -a ALL_PARAMS=()
MISSING_DATA=0

while IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma n_reps; do
    [[ -z "$scenario_id" || "$scenario_id" =~ ^# ]] && continue
    should_run_scenario "$scenario_id" || continue
    [[ -n "$GLOBAL_N_REPS" ]] && n_reps="$GLOBAL_N_REPS"

    models_str=$(get_inference_models "$rate_model")
    [[ -z "$models_str" ]] && { echo "Warning: unknown rate_model '$rate_model' for '$scenario_id', skipping." >&2; continue; }
    read -ra models <<< "$models_str"

    for rep in $(seq 1 "$n_reps"); do
        dataset_file="${INPUT_ROOT}/${scenario_id}/data/rep_${rep}/sim_1.nex"
        if [[ ! -f "$dataset_file" ]] && [[ "$DRY_RUN" != "true" ]]; then
            ((MISSING_DATA++)) || true
            continue
        fi
        for inf_model in "${models[@]}"; do
            for inf_k in "${INF_CATEGORIES[@]}"; do
                ALL_PARAMS+=("${scenario_id}\t${rep}\t${inf_model}\t${inf_k}\t${n_states}\t${dataset_file}")
            done
        done
    done
done < "$SCENARIOS_FILE"

NUM_JOBS="${#ALL_PARAMS[@]}"
printf '%s  Found %d inference jobs.\n' "$(date '+%F %T')" "$NUM_JOBS"
[[ $MISSING_DATA -gt 0 ]] && printf '%s  Warning: %d replicates missing (run simulations first).\n' \
    "$(date '+%F %T')" "$MISSING_DATA"

if [[ $NUM_JOBS -eq 0 ]]; then
    echo "Error: No jobs to run. Run simulations first." >&2; exit 1
fi

# submit SLURM job
if [[ "$COMPUTE_RESOURCE" == "palmuc" ]]; then
    printf '%s  Preparing SLURM submission...\n' "$(date '+%F %T')"

    mkdir -p "$SLURM_LOGS" "$SLURM_SCRIPTS" "$PARAMS_DIR" "$OUTPUT_ROOT"

    PARAMS_FILE="${PARAMS_DIR}/inference_params.txt"
    > "$PARAMS_FILE"
    for p in "${ALL_PARAMS[@]}"; do printf '%b\n' "$p" >> "$PARAMS_FILE"; done

    SLURM_SCRIPT="${SLURM_SCRIPTS}/run_inference.slurm"

    cat > "$SLURM_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=inf_new
#SBATCH --output=${SLURM_LOGS}/inf_%A_%a.out
#SBATCH --error=${SLURM_LOGS}/inf_%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --qos=normal_prio

module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry

export R_LIBS_USER=\$HOME/R_libs

LINE_NUM=\$(( \${OFFSET:-0} + SLURM_ARRAY_TASK_ID ))
read -r scenario_id rep inf_model inf_k n_states dataset_file \\
    <<< "\$(sed -n "\${LINE_NUM}p" "${PARAMS_FILE}")"

printf '%s  Scenario: %s  rep: %s  model: %s  k: %s  states: %s\n' \\
    "\$(date '+%F %T')" "\$scenario_id" "\$rep" "\$inf_model" "\$inf_k" "\$n_states"

OUTPUT_DIR="${OUTPUT_ROOT}/\${scenario_id}/with_\${inf_model}_k\${inf_k}/rep_\${rep}"
mkdir -p "\${OUTPUT_DIR}"

srun rb-mpi "${MCMC_SCRIPT}" \\
        "\${scenario_id}_rep_\${rep}" "\${dataset_file}" "\${inf_model}" \\
        "\${OUTPUT_DIR}" 2 "\${inf_k}" "${MODELS_DIR}" "\${n_states}"

printf '%s  Done: %s rep %s %s k%s\n' "\$(date '+%F %T')" "\$scenario_id" "\$rep" "\$inf_model" "\$inf_k"
EOF

    chmod +x "$SLURM_SCRIPT"

    MAX_ARRAY=10000
    N_BATCHES=$(( (NUM_JOBS + MAX_ARRAY - 1) / MAX_ARRAY ))

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '%s  [DRY RUN] %d jobs → %d batch(es) (MaxArraySize=%d):\n' \
            "$(date '+%F %T')" "$NUM_JOBS" "$N_BATCHES" "$MAX_ARRAY"
        for (( batch=0; batch<N_BATCHES; batch++ )); do
            start=$(( batch * MAX_ARRAY + 1 ))
            end=$(( (batch + 1) * MAX_ARRAY ))
            [[ $end -gt $NUM_JOBS ]] && end=$NUM_JOBS
            batch_size=$(( end - start + 1 ))
            offset=$(( start - 1 ))
            printf '  Batch %d: sbatch --array=1-%d%%400 --export=ALL,OFFSET=%d -p krypton %s\n' \
                "$((batch+1))" "$batch_size" "$offset" "$SLURM_SCRIPT"
        done
        printf '%s  Preview (first 10 jobs):\n' "$(date '+%F %T')"
        head -10 "$PARAMS_FILE" | nl
    else
        for (( batch=0; batch<N_BATCHES; batch++ )); do
            start=$(( batch * MAX_ARRAY + 1 ))
            end=$(( (batch + 1) * MAX_ARRAY ))
            [[ $end -gt $NUM_JOBS ]] && end=$NUM_JOBS
            batch_size=$(( end - start + 1 ))
            offset=$(( start - 1 ))
            sbatch --array="1-${batch_size}%400" --export=ALL,OFFSET="${offset}" -p krypton "$SLURM_SCRIPT"
            printf '%s  Submitted batch %d/%d (jobs %d–%d).\n' \
                "$(date '+%F %T')" "$((batch+1))" "$N_BATCHES" "$start" "$end"
        done
        printf '%s  All %d batches submitted (max 400 running at once). Logs: %s\n' \
            "$(date '+%F %T')" "$N_BATCHES" "$SLURM_LOGS"
    fi

# local run sequentially
else
    if [[ "$DRY_RUN" != "true" ]]; then
        command -v rb >/dev/null 2>&1 || { echo "Error: rb (RevBayes) not found." >&2; exit 1; }
    fi

    mkdir -p "$OUTPUT_ROOT" "$LOG_ROOT"

    for param_str in "${ALL_PARAMS[@]}"; do
        IFS=$'\t' read -r scenario_id rep inf_model inf_k n_states dataset_file \
            <<< "$(printf '%b' "$param_str")"

        OUTPUT_DIR="${OUTPUT_ROOT}/${scenario_id}/with_${inf_model}_k${inf_k}/rep_${rep}"
        LOG_FILE="${LOG_ROOT}/${scenario_id}_rep_${rep}_${inf_model}_k${inf_k}.log"

        printf '%s  [%s] rep %s: %s k=%s states=%s\n' "$(date '+%F %T')" "$scenario_id" "$rep" "$inf_model" "$inf_k" "$n_states"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would run MCMC: ${inf_model} k=${inf_k} states=${n_states}"
            continue
        fi

        mkdir -p "$OUTPUT_DIR"

        rb "$MCMC_SCRIPT" \
            "${scenario_id}_rep_${rep}" "$dataset_file" "$inf_model" \
            "$OUTPUT_DIR" 1 "$inf_k" "$MODELS_DIR" "$n_states" \
            2>&1 | tee "$LOG_FILE"
    done

    printf '%s  All inference jobs completed. Output: %s\n' "$(date '+%F %T')" "$OUTPUT_ROOT"
fi
