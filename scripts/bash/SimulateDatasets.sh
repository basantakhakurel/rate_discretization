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
TREE_SCRIPT="${REPO_ROOT}/scripts/rev/simulateTree.Rev"
DATA_SCRIPT="${REPO_ROOT}/scripts/rev/simulateACRV.Rev"
CONT_GAMMA_SCRIPT="${REPO_ROOT}/scripts/r/simulateContinuousGamma.r"
CONT_LOGNORMAL_SCRIPT="${REPO_ROOT}/scripts/r/simulateContinuousLognormal.r"
OUTPUT_ROOT="${REPO_ROOT}/SimData"
LOG_ROOT="${REPO_ROOT}/ScreenLogs"
SLURM_LOGS="${REPO_ROOT}/slurm/ScreenLogs"
SLURM_SCRIPTS="${REPO_ROOT}/slurm/scripts"
PARAMS_DIR="${REPO_ROOT}/slurm/params"

GLOBAL_N_REPS=""
DRY_RUN=false
declare -a SELECTED_SCENARIOS=()

usage() {
    cat <<EOF
Usage: $0 <compute_resource> [OPTIONS]

  compute_resource  'local' to run directly, 'palmuc' to submit to SLURM

Options:
  --n-reps N       Override replicate count for all scenarios
  --scenario ID    Run only the specified scenario
  --dry-run        Print without executing so that everything checks out
  -h, --help       Show this help message

Examples:
  $0 local --dry-run
  $0 local --n-reps 3 --scenario 8taxa_1order_continuousGamma
  $0 palmuc --n-reps 25
  $0 palmuc --dry-run
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

declare -a ALL_PARAMS=()
while IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma n_reps; do
    [[ -z "$scenario_id" || "$scenario_id" =~ ^# ]] && continue
    should_run_scenario "$scenario_id" || continue
    [[ -n "$GLOBAL_N_REPS" ]] && n_reps="$GLOBAL_N_REPS"
    for rep in $(seq 1 "$n_reps"); do
        ALL_PARAMS+=("${scenario_id}\t${n_taxa}\t${expected_tl}\t${n_sites}\t${n_states}\t${rate_model}\t${num_categories}\t${alpha}\t${sigma}\t${rep}")
    done
done < "$SCENARIOS_FILE"

printf '%s  Found %d simulation jobs.\n' "$(date '+%F %T')" "${#ALL_PARAMS[@]}"

# submit SLURM array job
if [[ "$COMPUTE_RESOURCE" == "palmuc" ]]; then
    printf '%s  Preparing SLURM submission...\n' "$(date '+%F %T')"

    mkdir -p "$SLURM_LOGS" "$SLURM_SCRIPTS" "$PARAMS_DIR" "$OUTPUT_ROOT"

    PARAMS_FILE="${PARAMS_DIR}/simulation_params.txt"
    > "$PARAMS_FILE"
    for p in "${ALL_PARAMS[@]}"; do printf '%b\n' "$p" >> "$PARAMS_FILE"; done

    NUM_JOBS=$(wc -l < "$PARAMS_FILE")
    SLURM_SCRIPT="${SLURM_SCRIPTS}/run_simulations.slurm"

    cat > "$SLURM_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=sim_v2
#SBATCH --output=${SLURM_LOGS}/sim_%A_%a.out
#SBATCH --error=${SLURM_LOGS}/sim_%A_%a.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --qos=normal_prio

module purge
module load gnu/12
module load openmpi/4.1.6
module load boost/1.82.0
module load prebin/kry
module load R/4.4.2

export R_LIBS_USER=\$HOME/R_libs

read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma rep \\
    <<< "\$(sed -n "\${SLURM_ARRAY_TASK_ID}p" "${PARAMS_FILE}")"

printf '%s  Scenario: %s  rep: %s\n' "\$(date '+%F %T')" "\$scenario_id" "\$rep"

TREES_DIR="${OUTPUT_ROOT}/\${scenario_id}/trees"
REP_DIR="${OUTPUT_ROOT}/\${scenario_id}/data/rep_\${rep}"
TREE_FILE="\${TREES_DIR}/rep_\${rep}.tre"
mkdir -p "\${TREES_DIR}" "\${REP_DIR}"

rb "${TREE_SCRIPT}" "\${n_taxa}" "\${expected_tl}" "\${TREE_FILE}" "\$((100000 + rep))"

case "\${rate_model}" in
    continuousGamma)
        Rscript "${CONT_GAMMA_SCRIPT}" "\${TREE_FILE}" "\${n_sites}" "\${alpha}" "\${REP_DIR}" "\$((100000 + rep))"
        ;;
    continuousLognormal)
        Rscript "${CONT_LOGNORMAL_SCRIPT}" "\${TREE_FILE}" "\${n_sites}" "\${sigma}" "\${REP_DIR}" "\$((100000 + rep))"
        ;;
    discreteGammaMean|discreteGammaMedian|discreteLognormalMedian)
        rb "${DATA_SCRIPT}" "\${TREE_FILE}" 1 "\${n_sites}" "\${n_states}" "\${rate_model}" "\${num_categories}" "\${alpha}" "\${sigma}" "\${REP_DIR}"
        ;;
    *)
        printf 'Error: unknown rate_model %s\n' "\${rate_model}" >&2; exit 1 ;;
esac

printf '%s  Done: %s rep %s\n' "\$(date '+%F %T')" "\$scenario_id" "\$rep"
EOF

    chmod +x "$SLURM_SCRIPT"

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '%s  [DRY RUN] Would submit: sbatch --array=1-%d -p krypton %s\n' \
            "$(date '+%F %T')" "$NUM_JOBS" "$SLURM_SCRIPT"
        printf '%s  Preview (first 5 jobs):\n' "$(date '+%F %T')"
        head -5 "$PARAMS_FILE" | nl
    else
        sbatch --array="1-${NUM_JOBS}" -p krypton "$SLURM_SCRIPT"
        printf '%s  Jobs submitted! Check logs in %s\n' "$(date '+%F %T')" "$SLURM_LOGS"
    fi

# run sequentially
else
    if [[ "$DRY_RUN" != "true" ]]; then
        missing=()
        command -v rb >/dev/null 2>&1 || missing+=("rb (RevBayes)")
        command -v Rscript >/dev/null 2>&1 || missing+=("Rscript (R)")
        if [[ ${#missing[@]} -gt 0 ]]; then
            printf 'Error: missing required software: %s\n' "${missing[*]}" >&2; exit 1
        fi
    fi

    mkdir -p "$OUTPUT_ROOT" "$LOG_ROOT"

    for param_str in "${ALL_PARAMS[@]}"; do
        IFS=$'\t' read -r scenario_id n_taxa expected_tl n_sites n_states rate_model num_categories alpha sigma rep \
            <<< "$(printf '%b' "$param_str")"

        TREES_DIR="${OUTPUT_ROOT}/${scenario_id}/trees"
        REP_DIR="${OUTPUT_ROOT}/${scenario_id}/data/rep_${rep}"
        TREE_FILE="${TREES_DIR}/rep_${rep}.tre"
        LOG_FILE="${LOG_ROOT}/${scenario_id}.log"

        printf '%s  [%s] rep %s (%s)\n' "$(date '+%F %T')" "$scenario_id" "$rep" "$rate_model"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would simulate: tree + ${rate_model}"
            continue
        fi

        mkdir -p "$TREES_DIR" "$REP_DIR"

        rb "$TREE_SCRIPT" "$n_taxa" "$expected_tl" "$TREE_FILE" "$((100000 + rep))" \
            2>&1 | tee -a "$LOG_FILE"

        case "$rate_model" in
            continuousGamma)
                Rscript "$CONT_GAMMA_SCRIPT" "$TREE_FILE" "$n_sites" "$alpha" \
                    "$REP_DIR" "$((100000 + rep))" 2>&1 | tee -a "$LOG_FILE"
                ;;
            continuousLognormal)
                Rscript "$CONT_LOGNORMAL_SCRIPT" "$TREE_FILE" "$n_sites" "$sigma" \
                    "$REP_DIR" "$((100000 + rep))" 2>&1 | tee -a "$LOG_FILE"
                ;;
            discreteGammaMean|discreteGammaMedian|discreteLognormalMedian)
                rb "$DATA_SCRIPT" "$TREE_FILE" 1 "$n_sites" "$n_states" \
                    "$rate_model" "$num_categories" "$alpha" "$sigma" "$REP_DIR" \
                    2>&1 | tee -a "$LOG_FILE"
                ;;
            *)
                printf 'Error: unknown rate_model %s\n' "$rate_model" >&2; exit 1 ;;
        esac
    done

    printf '%s  All simulations completed. Output: %s\n' "$(date '+%F %T')" "$OUTPUT_ROOT"
fi
