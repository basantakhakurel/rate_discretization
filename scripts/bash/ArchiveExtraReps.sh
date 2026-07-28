#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SIM_ROOT="${REPO_ROOT}/SimData"
[[ -d "${SIM_ROOT}/SimData" ]] && SIM_ROOT="${SIM_ROOT}/SimData"
INF_ROOT="${REPO_ROOT}/InferenceOutput"
ARCHIVE_ROOT="${REPO_ROOT}/archive/ArchivedExtraReps"

KEEP_REPS=10
EXECUTE=false
SCOPE="both"

usage() {
    cat <<EOF
Usage: $0 [--keep-reps N] [--execute] [--scope both|inference|simdata]

Moves rep_<N> directories with N > --keep-reps out of the live pipeline
directories into ${ARCHIVE_ROOT}, preserving their relative path. Nothing is
deleted, only relocated. Safe to run repeatedly - already-archived reps are
simply not found again.

  --keep-reps N   Keep rep_1..rep_N in place, move anything above (default: 10)
  --execute       Actually move things (default: dry run, prints only)
  --scope S       What to archive: both (default), inference, or simdata
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-reps) KEEP_REPS="$2"; shift 2 ;;
        --execute) EXECUTE=true; shift ;;
        --scope) SCOPE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

n_moved=0
n_skipped=0
total_kb=0

move_dir() {
    local src="$1" dest="$2"
    [[ -d "$src" ]] || return 0

    if [[ -e "$dest" ]]; then
        printf '  SKIP (destination already exists): %s\n' "${dest#"$REPO_ROOT"/}" >&2
        ((n_skipped++)) || true
        return 0
    fi

    local size_kb
    size_kb=$(du -sk "$src" 2>/dev/null | awk '{print $1}')
    total_kb=$(( total_kb + size_kb ))
    ((n_moved++)) || true

    if [[ "$EXECUTE" == "true" ]]; then
        mkdir -p "$(dirname "$dest")"
        mv "$src" "$dest"
        printf '  MOVED  %-65s (%s KB)\n' "${src#"$REPO_ROOT"/}" "$size_kb"
    else
        printf '  WOULD MOVE  %-61s (%s KB)\n' "${src#"$REPO_ROOT"/}" "$size_kb"
    fi
}

if [[ "$SCOPE" == "both" || "$SCOPE" == "simdata" ]]; then
    echo "Scanning SimData for rep_$((KEEP_REPS + 1))+ ..."
    for scenario_dir in "$SIM_ROOT"/*/; do
        [[ -d "${scenario_dir}data" ]] || continue
        scenario_id="$(basename "$scenario_dir")"
        for rep_dir in "${scenario_dir}data"/rep_*/; do
            rep_num="$(basename "$rep_dir")"; rep_num="${rep_num#rep_}"
            [[ "$rep_num" =~ ^[0-9]+$ ]] || continue
            (( rep_num <= KEEP_REPS )) && continue
            move_dir "${rep_dir%/}" "${ARCHIVE_ROOT}/SimData/${scenario_id}/data/rep_${rep_num}"
        done
    done
fi

if [[ "$SCOPE" == "both" || "$SCOPE" == "inference" ]]; then
    echo "Scanning InferenceOutput for rep_$((KEEP_REPS + 1))+ ..."
    for scenario_dir in "$INF_ROOT"/*/; do
        scenario_id="$(basename "$scenario_dir")"
        for combo_dir in "${scenario_dir}"with_*/; do
            combo="$(basename "$combo_dir")"
            for rep_dir in "${combo_dir}"rep_*/; do
                rep_num="$(basename "$rep_dir")"; rep_num="${rep_num#rep_}"
                [[ "$rep_num" =~ ^[0-9]+$ ]] || continue
                (( rep_num <= KEEP_REPS )) && continue
                move_dir "${rep_dir%/}" "${ARCHIVE_ROOT}/InferenceOutput/${scenario_id}/${combo}/rep_${rep_num}"
            done
        done
    done
fi

echo
if [[ "$n_moved" -eq 0 && "$n_skipped" -eq 0 ]]; then
    echo "Nothing above rep_${KEEP_REPS} found. Nothing to do."
    exit 0
fi

total_mb=$(awk -v k="$total_kb" 'BEGIN{printf "%.1f", k/1024}')
[[ "$n_skipped" -gt 0 ]] && printf '%d already archived (skipped).\n' "$n_skipped"

if [[ "$EXECUTE" == "true" ]]; then
    printf 'Moved %d directories (~%s MB) into %s\n' "$n_moved" "$total_mb" "$ARCHIVE_ROOT"
else
    printf 'DRY RUN: would move %d directories (~%s MB) into %s\n' "$n_moved" "$total_mb" "$ARCHIVE_ROOT"
    echo "Re-run with --execute to actually move them."
fi
