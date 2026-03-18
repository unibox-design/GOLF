#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/launch_run.sh --config CONFIG --run PRESET --repo REPO_PATH [--results CSV] [--logs-dir DIR] [--log-path FILE] [--dry-run]

Options:
  --config     JSON config file with named run presets
  --run        Preset name inside the config file
  --repo       Path to the parameter-golf repository
  --results    CSV file to append parsed results later (default: experiments.csv)
  --logs-dir   Directory for log files (default: logs)
  --log-path   Explicit log file path (overrides --logs-dir)
  --dry-run    Print the command without executing it
EOF
}

CONFIG=""
RUN_NAME=""
REPO_PATH=""
RESULTS_CSV="experiments.csv"
LOGS_DIR="logs"
LOG_PATH_OVERRIDE=""
DRY_RUN=0
BASE_DIR="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --run) RUN_NAME="$2"; shift 2 ;;
    --repo) REPO_PATH="$2"; shift 2 ;;
    --results) RESULTS_CSV="$2"; shift 2 ;;
    --logs-dir) LOGS_DIR="$2"; shift 2 ;;
    --log-path) LOG_PATH_OVERRIDE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$CONFIG" || -z "$RUN_NAME" || -z "$REPO_PATH" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Config file not found: $CONFIG" >&2
  exit 1
fi

if [[ ! -d "$REPO_PATH" ]]; then
  echo "Repo path not found: $REPO_PATH" >&2
  exit 1
fi

mkdir -p "$LOGS_DIR"
LOGS_DIR_ABS="$BASE_DIR/$LOGS_DIR"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
if [[ -n "$LOG_PATH_OVERRIDE" ]]; then
  LOG_PATH="$LOG_PATH_OVERRIDE"
  mkdir -p "$(dirname "$LOG_PATH")"
else
  LOG_PATH="$LOGS_DIR_ABS/${TIMESTAMP}_${RUN_NAME}.log"
fi

EXPORTED_LINES="$(
python3 - "$CONFIG" "$RUN_NAME" "$REPO_PATH" "$LOG_PATH" <<'PY'
import json
import shlex
import sys
from pathlib import Path

config_path, run_name, repo_path, log_path = sys.argv[1:5]
with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)
if run_name not in config:
    raise SystemExit(f"Preset not found: {run_name}")

preset = config[run_name]
env = preset.get("env", {})
command = preset.get("command", [])
if not command:
    raise SystemExit(f"Preset has no command: {run_name}")

for key, value in env.items():
    print(f'export {key}={shlex.quote(str(value))}')

full_cmd = " ".join(shlex.quote(part) for part in command)
venv_activate = f"{repo_path}/.venv/bin/activate"
if Path(venv_activate).exists():
    print(f'. {shlex.quote(venv_activate)}')
print('export PYTHONUNBUFFERED=1')
print(f'cd {shlex.quote(repo_path)}')
print(f'exec {full_cmd} 2>&1 | tee {shlex.quote(log_path)}')
PY
)"

RUN_SCRIPT="$(mktemp)"
{
  echo "set -euo pipefail"
  printf '%s\n' "$EXPORTED_LINES"
} > "$RUN_SCRIPT"

echo "Preset: $RUN_NAME"
echo "Repo: $REPO_PATH"
echo "Log: $LOG_PATH"
echo "Results CSV: $RESULTS_CSV"
echo
echo "Expanded launch script:"
cat "$RUN_SCRIPT"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  rm -f "$RUN_SCRIPT"
  exit 0
fi

bash "$RUN_SCRIPT"
rm -f "$RUN_SCRIPT"
