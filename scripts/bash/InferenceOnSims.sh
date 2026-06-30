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

# Partition/memory tier by inf_k.
# krypton node ratio ~8GB/core -> 16G for 2 cores. lemmium 16GB/core -> can go higher if needed.
get_resources_for_k() {
    case "$1" in
        2|4)    echo "krypton 8G" ;;
        8)      echo "krypton 16G" ;;
        16|100) echo "lemmium 32G" ;;
        *)      echo "krypton 16G" ;;
    esac
}

declare -a ALL_PARAMS=()
declare -a ALL_TIERS=()
MISSING_DATA=0
SKIPPED_DONE=0

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
                output_dir="${OUTPUT_ROOT}/${scenario_id}/with_${inf_model}_k${inf_k}/rep_${rep}"
                map_tre="${output_dir}/${scenario_id}_rep_${rep}_${inf_model}_${inf_k}_Cats.map.tre"
                if [[ -f "$map_tre" ]]; then
                    ((SKIPPED_DONE++)) || true
                    continue
                fi
                read -r partition mem <<< "$(get_resources_for_k "$inf_k")"
                ALL_PARAMS+=("${scenario_id}\t${rep}\t${inf_model}\t${inf_k}\t${n_states}\t${dataset_file}")
                ALL_TIERS+=("${partition}_${mem}")
            done
        done
    done
done < "$SCENARIOS_FILE"

NUM_JOBS="${#ALL_PARAMS[@]}"
printf '%s  Found %d inference jobs to run (%d already completed, skipped).\n' \
    "$(date '+%F %T')" "$NUM_JOBS" "$SKIPPED_DONE"
[[ $MISSING_DATA -gt 0 ]] && printf '%s  Warning: %d replicates missing (run simulations first).\n' \
    "$(date '+%F %T')" "$MISSING_DATA"

if [[ $NUM_JOBS -eq 0 ]]; then
    printf '%s  All inference jobs already completed.\n' "$(date '+%F %T')"; exit 0
fi

# submit SLURM job
if [[ "$COMPUTE_RESOURCE" == "palmuc" ]]; then
    printf '%s  Preparing SLURM submission...\n' "$(date '+%F %T')"

    mkdir -p "$SLURM_LOGS" "$SLURM_SCRIPTS" "$PARAMS_DIR" "$OUTPUT_ROOT"

    declare -A TIER_PARAMS_FILE=()
    declare -A TIER_COUNT=()
    declare -a TIER_KEYS=()

    for i in "${!ALL_PARAMS[@]}"; do
        tier_key="${ALL_TIERS[$i]}"
        if [[ -z "${TIER_PARAMS_FILE[$tier_key]+x}" ]]; then
            params_file="${PARAMS_DIR}/inference_params_${tier_key}.txt"
            > "$params_file"
            TIER_PARAMS_FILE[$tier_key]="$params_file"
            TIER_COUNT[$tier_key]=0
            TIER_KEYS+=("$tier_key")
        fi
        printf '%b\n' "${ALL_PARAMS[$i]}" >> "${TIER_PARAMS_FILE[$tier_key]}"
        TIER_COUNT[$tier_key]=$(( TIER_COUNT[$tier_key] + 1 ))
    done

    for tier_key in "${TIER_KEYS[@]}"; do
        params_file="${TIER_PARAMS_FILE[$tier_key]}"
        tier_jobs="${TIER_COUNT[$tier_key]}"
        partition="${tier_key%%_*}"
        mem="${tier_key#*_}"

        SLURM_SCRIPT="${SLURM_SCRIPTS}/run_inference_${tier_key}.slurm"

        cat > "$SLURM_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=inf_${tier_key}
#SBATCH --output=${SLURM_LOGS}/inf_${tier_key}_%A_%a.out
#SBATCH --error=${SLURM_LOGS}/inf_${tier_key}_%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --cpus-per-task=1
#SBATCH --mem=${mem}
#SBATCH --qos=normal_prio

set -euo pipefail

module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry

export R_LIBS_USER=\$HOME/R_libs

LINE_NUM=\$(( \${OFFSET:-0} + SLURM_ARRAY_TASK_ID ))
read -r scenario_id rep inf_model inf_k n_states dataset_file \\
    <<< "\$(sed -n "\${LINE_NUM}p" "${params_file}")"

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
        N_BATCHES=$(( (tier_jobs + MAX_ARRAY - 1) / MAX_ARRAY ))

        if [[ "$DRY_RUN" == "true" ]]; then
            printf '%s  [DRY RUN] Tier %s: %d jobs → %d batch(es) (partition=%s mem=%s):\n' \
                "$(date '+%F %T')" "$tier_key" "$tier_jobs" "$N_BATCHES" "$partition" "$mem"
            for (( batch=0; batch<N_BATCHES; batch++ )); do
                start=$(( batch * MAX_ARRAY + 1 ))
                end=$(( (batch + 1) * MAX_ARRAY ))
                [[ $end -gt $tier_jobs ]] && end=$tier_jobs
                batch_size=$(( end - start + 1 ))
                offset=$(( start - 1 ))
                printf '  Batch %d: sbatch --array=1-%d%%400 --export=ALL,OFFSET=%d -p %s %s\n' \
                    "$((batch+1))" "$batch_size" "$offset" "$partition" "$SLURM_SCRIPT"
            done
            printf '%s  Preview (first 5 jobs):\n' "$(date '+%F %T')"
            head -5 "$params_file" | nl
        else
            for (( batch=0; batch<N_BATCHES; batch++ )); do
                start=$(( batch * MAX_ARRAY + 1 ))
                end=$(( (batch + 1) * MAX_ARRAY ))
                [[ $end -gt $tier_jobs ]] && end=$tier_jobs
                batch_size=$(( end - start + 1 ))
                offset=$(( start - 1 ))
                sbatch --array="1-${batch_size}%400" --export=ALL,OFFSET="${offset}" -p "$partition" "$SLURM_SCRIPT"
                printf '%s  Submitted %s batch %d/%d (jobs %d–%d).\n' \
                    "$(date '+%F %T')" "$tier_key" "$((batch+1))" "$N_BATCHES" "$start" "$end"
            done
        fi
    done

    [[ "$DRY_RUN" != "true" ]] && printf '%s  All tiers submitted (max 400 running at once per tier). Logs: %s\n' \
        "$(date '+%F %T')" "$SLURM_LOGS"

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
