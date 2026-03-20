#!/usr/bin/env bash
set -euo pipefail

RUN_PRESET="${RUN_PRESET:?RUN_PRESET is required}"
DATA_VARIANT="${DATA_VARIANT:?DATA_VARIANT is required}"
TRAIN_SHARDS="${TRAIN_SHARDS:?TRAIN_SHARDS is required}"
RESULTS_DIR="${RESULTS_DIR:?RESULTS_DIR is required}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
REPO_ROOT="${REPO_ROOT:-$WORKSPACE_ROOT/parameter-golf}"
AUTOMATION_ROOT="${AUTOMATION_ROOT:-$WORKSPACE_ROOT/golf}"
VENV_ROOT="${VENV_ROOT:-$WORKSPACE_ROOT/venv}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-$WORKSPACE_ROOT/.cache/pip}"
HF_HOME="${HF_HOME:-$WORKSPACE_ROOT/.cache/huggingface}"
PARAMETER_GOLF_REPO_URL="${PARAMETER_GOLF_REPO_URL:-https://github.com/openai/parameter-golf.git}"
KEEP_ALIVE_ON_EXIT="${KEEP_ALIVE_ON_EXIT:-1}"

BOOTSTRAP_LOG="$RESULTS_DIR/bootstrap.log"
STATUS_FILE="$RESULTS_DIR/bootstrap.status"
RUN_LOG="$RESULTS_DIR/${RUN_PRESET}.log"
CSV_PATH="$RESULTS_DIR/experiments.csv"
DEPS_STAMP="$VENV_ROOT/.parameter_golf_deps_installed"

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

log "workspace_root=$WORKSPACE_ROOT"
log "automation_root=$AUTOMATION_ROOT"
log "repo_root=$REPO_ROOT"
log "venv_root=$VENV_ROOT"
log "results_dir=$RESULTS_DIR"

mkdir -p "$PIP_CACHE_DIR" "$HF_HOME"
export PIP_CACHE_DIR
export HF_HOME

ensure_venv() {
  if [[ ! -x "$VENV_ROOT/bin/python" ]]; then
    log "creating persistent virtualenv at $VENV_ROOT"
    python3 -m venv "$VENV_ROOT" 2>&1 | tee -a "$BOOTSTRAP_LOG"
  else
    log "persistent virtualenv already present at $VENV_ROOT"
  fi

  export PATH="$VENV_ROOT/bin:$PATH"
  export VIRTUAL_ENV="$VENV_ROOT"
  hash -r
  log "active_python=$(command -v python3)"
}

torch_has_enable_gqa() {
  python3 - <<'PY'
import inspect
import sys

try:
    import torch.nn.functional as F
except Exception:
    sys.exit(1)

try:
    sig = inspect.signature(F.scaled_dot_product_attention)
except Exception:
    sys.exit(1)

sys.exit(0 if "enable_gqa" in sig.parameters else 1)
PY
}

ensure_torch_compat() {
  if ! torch_has_enable_gqa; then
    log "upgrading torch to a version with scaled_dot_product_attention(enable_gqa=...) support"
    python3 -m pip install --upgrade "torch>=2.5" 2>&1 | tee -a "$BOOTSTRAP_LOG"
  else
    log "existing torch runtime already supports enable_gqa"
  fi
}

python_has_core_deps() {
  python3 - <<'PY'
import importlib
import sys

required = ["huggingface_hub", "datasets", "sentencepiece", "tqdm", "numpy"]
missing = [name for name in required if importlib.util.find_spec(name) is None]
sys.exit(0 if not missing else 1)
PY
}

ensure_venv

if [[ ! -d "$REPO_ROOT/.git" ]]; then
  log "cloning parameter-golf into $REPO_ROOT"
  rm -rf "$REPO_ROOT"
  git clone "$PARAMETER_GOLF_REPO_URL" "$REPO_ROOT" 2>&1 | tee -a "$BOOTSTRAP_LOG"
else
  log "parameter-golf repo already present at $REPO_ROOT"
fi

if [[ ! -f "$DEPS_STAMP" ]] || ! python_has_core_deps; then
  log "installing Python dependencies"
  python3 -m pip install --upgrade pip 2>&1 | tee -a "$BOOTSTRAP_LOG"
  ensure_torch_compat
  python3 -m pip install -r "$REPO_ROOT/requirements.txt" 2>&1 | tee -a "$BOOTSTRAP_LOG"
  date '+%Y-%m-%d %H:%M:%S' > "$DEPS_STAMP"
else
  log "dependency install already completed"
  ensure_torch_compat
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
