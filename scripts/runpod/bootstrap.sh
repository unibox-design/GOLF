#!/usr/bin/env bash
set -euo pipefail

RUN_PRESET="${RUN_PRESET:?RUN_PRESET is required}"
DATA_VARIANT="${DATA_VARIANT:?DATA_VARIANT is required}"
TRAIN_SHARDS="${TRAIN_SHARDS:?TRAIN_SHARDS is required}"
RESULTS_DIR="${RESULTS_DIR:?RESULTS_DIR is required}"
REPO_ROOT="${REPO_ROOT:-/runpod/parameter-golf}"
AUTOMATION_ROOT="${AUTOMATION_ROOT:-/opt/golf}"
PARAMETER_GOLF_REPO_URL="${PARAMETER_GOLF_REPO_URL:-https://github.com/openai/parameter-golf.git}"
KEEP_ALIVE_ON_EXIT="${KEEP_ALIVE_ON_EXIT:-1}"

BOOTSTRAP_LOG="$RESULTS_DIR/bootstrap.log"
STATUS_FILE="$RESULTS_DIR/bootstrap.status"
RUN_LOG="$RESULTS_DIR/${RUN_PRESET}.log"
CSV_PATH="$RESULTS_DIR/experiments.csv"
DEPS_STAMP="$REPO_ROOT/.deps_installed"

mkdir -p "$RESULTS_DIR"
touch "$BOOTSTRAP_LOG"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$BOOTSTRAP_LOG"
}

finish() {
  local rc="$1"
  echo "$rc" > "$STATUS_FILE"
  log "bootstrap_exit_code=$rc"
  if [[ "$KEEP_ALIVE_ON_EXIT" == "1" ]]; then
    log "keeping container alive for inspection"
    tail -f /dev/null
  fi
  exit "$rc"
}

trap 'finish $?' EXIT

log "automation_root=$AUTOMATION_ROOT"
log "repo_root=$REPO_ROOT"
log "results_dir=$RESULTS_DIR"

if [[ ! -d "$REPO_ROOT/.git" ]]; then
  log "cloning parameter-golf into $REPO_ROOT"
  rm -rf "$REPO_ROOT"
  git clone "$PARAMETER_GOLF_REPO_URL" "$REPO_ROOT" 2>&1 | tee -a "$BOOTSTRAP_LOG"
else
  log "parameter-golf repo already present at $REPO_ROOT"
fi

if [[ ! -f "$DEPS_STAMP" ]]; then
  log "installing Python dependencies"
  python3 -m pip install --upgrade pip 2>&1 | tee -a "$BOOTSTRAP_LOG"
  pip install -r "$REPO_ROOT/requirements.txt" 2>&1 | tee -a "$BOOTSTRAP_LOG"
  date '+%Y-%m-%d %H:%M:%S' > "$DEPS_STAMP"
else
  log "dependency install already completed"
fi

log "downloading cached FineWeb variant=$DATA_VARIANT train_shards=$TRAIN_SHARDS"
(
  cd "$REPO_ROOT"
  python3 data/cached_challenge_fineweb.py --variant "$DATA_VARIANT" --train-shards "$TRAIN_SHARDS"
) 2>&1 | tee -a "$BOOTSTRAP_LOG"

log "launching preset $RUN_PRESET"
(
  cd "$AUTOMATION_ROOT"
  bash scripts/launch_run.sh \
    --config config/runs.example.json \
    --run "$RUN_PRESET" \
    --repo "$REPO_ROOT" \
    --results "$CSV_PATH" \
    --log-path "$RUN_LOG"
) 2>&1 | tee -a "$BOOTSTRAP_LOG"

log "parsing run log"
(
  cd "$AUTOMATION_ROOT"
  python3 scripts/parse_log.py \
    --log "$RUN_LOG" \
    --run-id "$RUN_PRESET" \
    --preset "$RUN_PRESET" \
    --append "$CSV_PATH"
) 2>&1 | tee -a "$BOOTSTRAP_LOG"
