#!/usr/bin/env bash
set -euo pipefail


# SCARY SCRIPT
# THIS CANCELS JOBS - USE WITH CAUTION

KEEP_REPS=10
EXECUTE=false
SKIP_RUNNING=false
USER_NAME="${USER}"
OFFSET_OVERRIDE=""

usage() {
    cat <<EOF
Usage: $0 [--keep-reps N] [--execute] [--skip-running] [--user NAME] [--offset N]

  --keep-reps N   Keep rep_1..rep_N, cancel anything above (default: 10)
  --execute       Actually scancel matching jobs (default: dry run, prints only)
  --skip-running  Only ever act on PENDING jobs; RUNNING jobs are always listed
                   as informational only, never cancelled even with --execute.
                   Use this for a zero-risk first pass (nothing running is ever
                   touched), then drop the flag once you've reviewed the
                   RUNNING evidence lines and are ready to cancel those too.
  --user NAME     SLURM user to query (default: \$USER)
  --offset N      Force OFFSET used for all PENDING line lookups (default: auto,
                   assumed 0 - only needed if a tier was split into >1 sbatch
                   batch, i.e. more than 10000 jobs in that tier)

Always run without --execute first and review the printed evidence line for
every RUNNING job marked "CANCEL" before re-running with --execute.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-reps) KEEP_REPS="$2"; shift 2 ;;
        --execute) EXECUTE=true; shift ;;
        --skip-running) SKIP_RUNNING=true; shift ;;
        --user) USER_NAME="$2"; shift 2 ;;
        --offset) OFFSET_OVERRIDE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PARAMS_DIR="${REPO_ROOT}/slurm/params"
SLURM_LOGS="${REPO_ROOT}/slurm/logs"

declare -a TO_CANCEL_RUNNING=()
declare -a TO_CANCEL_PENDING=()
declare -A TIER_FILE_LINES=()

n_kept=0
n_cancel=0
n_unresolved=0

printf 'Scanning jobs for user %s (keep-reps=%s)...\n' "$USER_NAME" "$KEEP_REPS"
echo

get_line_count() {
    local tier_key="$1" params_file="$2"
    if [[ -z "${TIER_FILE_LINES[$tier_key]+x}" ]]; then
        TIER_FILE_LINES[$tier_key]=$(wc -l < "$params_file")
    fi
    echo "${TIER_FILE_LINES[$tier_key]}"
}

while IFS='|' read -r jobid_task jobname state; do
    [[ "$jobname" == inf_* ]] || continue
    tier_key="${jobname#inf_}"
    jobid="${jobid_task%%_*}"
    taskid="${jobid_task#*_}"
    [[ "$taskid" == "$jobid_task" ]] && continue   # not an array task, skip

    rep=""
    evidence=""
    case "$state" in
        R)
            logfile="${SLURM_LOGS}/inf_${tier_key}_${jobid}_${taskid}.out"
            if [[ -f "$logfile" ]]; then
                evidence=$(grep -m1 'rep:' "$logfile" || true)
                rep=$(grep -oE 'rep: [0-9]+' <<< "$evidence" | awk '{print $2}')
            fi
            ;;
        PD)
            params_file="${PARAMS_DIR}/inference_params_${tier_key}.txt"
            offset="${OFFSET_OVERRIDE:-0}"
            if [[ -f "$params_file" ]]; then
                nlines=$(get_line_count "$tier_key" "$params_file")
                line_num=$(( offset + taskid ))
                if (( line_num > nlines )); then
                    printf '  WARNING: %s task %s -> line %d exceeds %s (%d lines). Params file may be stale/offset wrong - leaving alone.\n' \
                        "$jobid" "$taskid" "$line_num" "$params_file" "$nlines" >&2
                else
                    evidence=$(sed -n "${line_num}p" "$params_file")
                    rep=$(awk -F'\t' '{print $2}' <<< "$evidence")
                fi
            fi
            ;;
        *)
            continue ;;
    esac

    if [[ -z "$rep" || ! "$rep" =~ ^[0-9]+$ ]]; then
        printf '  UNRESOLVED: %-16s (%-20s state=%-2s) - could not determine rep, leaving alone\n' \
            "$jobid_task" "$jobname" "$state"
        ((n_unresolved++)) || true
        continue
    fi

    if (( rep > KEEP_REPS )); then
        printf '  CANCEL: %-16s state=%-2s rep=%-4s | %s\n' "$jobid_task" "$state" "$rep" "$evidence"
        if [[ "$state" == "R" ]]; then
            TO_CANCEL_RUNNING+=("$jobid_task")
        else
            TO_CANCEL_PENDING+=("$jobid_task")
        fi
        ((n_cancel++)) || true
    else
        ((n_kept++)) || true
    fi
done < <(squeue -u "$USER_NAME" -r -h -o '%i|%j|%t')

n_cancel_running="${#TO_CANCEL_RUNNING[@]}"
n_cancel_pending="${#TO_CANCEL_PENDING[@]}"

echo
printf 'Kept       (rep <= %s): %d\n' "$KEEP_REPS" "$n_kept"
printf 'To cancel  (rep >  %s): %d  (running=%d, pending=%d)\n' "$KEEP_REPS" "$n_cancel" "$n_cancel_running" "$n_cancel_pending"
printf 'Unresolved (left alone): %d\n' "$n_unresolved"

if [[ "$n_cancel" -eq 0 ]]; then
    echo "Nothing to cancel."
    exit 0
fi

CANCEL_LIST="/tmp/cancel_extra_reps_$$.txt"
{ printf '%s\n' "${TO_CANCEL_PENDING[@]}" 2>/dev/null; printf '%s\n' "${TO_CANCEL_RUNNING[@]}" 2>/dev/null; } > "$CANCEL_LIST"
printf 'Full cancel list written to: %s\n' "$CANCEL_LIST"

if [[ "$EXECUTE" != "true" ]]; then
    echo "DRY RUN - nothing cancelled. Check every 'CANCEL ... state=R' evidence line above against"
    echo "your own knowledge of that run, then re-run with --execute."
    exit 0
fi

if [[ "$n_cancel_pending" -gt 0 ]]; then
    printf 'Cancelling %d PENDING jobs (zero risk - none have started)...\n' "$n_cancel_pending"
    for jt in "${TO_CANCEL_PENDING[@]}"; do
        scancel "$jt"
    done
fi

if [[ "$n_cancel_running" -eq 0 ]]; then
    echo "No RUNNING jobs to cancel."
elif [[ "$SKIP_RUNNING" == "true" ]]; then
    printf 'Skipping %d RUNNING jobs (--skip-running set). Their evidence lines are printed above for review;\n' "$n_cancel_running"
    echo "drop --skip-running and re-run once you've checked them to cancel those too."
else
    printf 'Cancelling %d RUNNING jobs...\n' "$n_cancel_running"
    for jt in "${TO_CANCEL_RUNNING[@]}"; do
        scancel "$jt"
    done
fi

echo "Done."
