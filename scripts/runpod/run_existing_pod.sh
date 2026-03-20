#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod/run_existing_pod.sh POD_ID --env-file FILE [--run-preset NAME] [--key PATH]

Launch the configured bootstrap workflow on an already running Runpod pod.
This uses the existing pod's current image and mounted volume instead of
creating a new pod.
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

POD_ID="$1"
shift

ENV_FILE=""
KEY_PATH="${HOME}/.runpod/ssh/Proximity-MBP-ed25519"
RUN_PRESET_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --run-preset) RUN_PRESET_OVERRIDE="$2"; shift 2 ;;
    --key) KEY_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -n "$RUN_PRESET_OVERRIDE" ]]; then
  RUN_PRESET="$RUN_PRESET_OVERRIDE"
fi

required_vars=(
  RUN_PRESET
  DATA_VARIANT
  TRAIN_SHARDS
  RESULTS_DIR
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required variable: $var_name" >&2
    exit 1
  fi
done

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
AUTOMATION_ROOT="${AUTOMATION_ROOT:-$WORKSPACE_ROOT/golf}"
REPO_ROOT_ON_POD="${REPO_ROOT_ON_POD:-$WORKSPACE_ROOT/parameter-golf}"
AUTOMATION_REPO_URL="${AUTOMATION_REPO_URL:-https://github.com/unibox-design/GOLF.git}"

REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail
mkdir -p "$(printf '%q' "$RESULTS_DIR")" "$(printf '%q' "$WORKSPACE_ROOT")"
if [ ! -d "$(printf '%q' "$AUTOMATION_ROOT")/.git" ]; then
  git clone "$(printf '%q' "$AUTOMATION_REPO_URL")" "$(printf '%q' "$AUTOMATION_ROOT")"
else
  git -C "$(printf '%q' "$AUTOMATION_ROOT")" pull --ff-only || true
fi
rm -f "$(printf '%q' "$RESULTS_DIR")/bootstrap.status"
nohup /usr/bin/env \
  RUN_PRESET="$(printf '%q' "$RUN_PRESET")" \
  DATA_VARIANT="$(printf '%q' "$DATA_VARIANT")" \
  TRAIN_SHARDS="$(printf '%q' "$TRAIN_SHARDS")" \
  RESULTS_DIR="$(printf '%q' "$RESULTS_DIR")" \
  WORKSPACE_ROOT="$(printf '%q' "$WORKSPACE_ROOT")" \
  REPO_ROOT="$(printf '%q' "$REPO_ROOT_ON_POD")" \
  AUTOMATION_ROOT="$(printf '%q' "$AUTOMATION_ROOT")" \
  KEEP_ALIVE_ON_EXIT=0 \
  bash "$(printf '%q' "$AUTOMATION_ROOT")/scripts/runpod/bootstrap.sh" \
  >"$(printf '%q' "$RESULTS_DIR")/manual-bootstrap.stdout" 2>&1 < /dev/null &
echo "BOOTSTRAP_PID:\$!"
EOF
)

bash "$SCRIPT_DIR/remote_exec.sh" "$POD_ID" --key "$KEY_PATH" -- bash -lc "$REMOTE_SCRIPT"
