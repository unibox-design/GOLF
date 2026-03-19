#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod/create_pod.sh --env-file FILE [--dry-run] [--mode MODE]

Options:
  --env-file   Shell env file with Runpod and experiment settings
  --dry-run    Print the rendered runpodctl command without executing it
  --mode       bootstrap or idle (default: bootstrap)
EOF
}

ENV_FILE=""
DRY_RUN=0
MODE="bootstrap"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --mode) MODE="$2"; shift 2 ;;
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

required_vars=(
  RUNPOD_API_KEY
  POD_NAME
  CONTAINER_DISK_GB
  VOLUME_GB
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

if [[ -z "${TEMPLATE_ID:-}" ]]; then
  if [[ -z "${RUNPOD_IMAGE_NAME:-}" || -z "${GPU_TYPE:-}" || -z "${GPU_COUNT:-}" ]]; then
    echo "When TEMPLATE_ID is empty, RUNPOD_IMAGE_NAME, GPU_TYPE, and GPU_COUNT are required." >&2
    exit 1
  fi
fi

STARTUP_COMMAND="$(
  python3 "$REPO_ROOT/scripts/runpod/render_startup_command.py" \
    --run-preset "$RUN_PRESET" \
    --data-variant "$DATA_VARIANT" \
    --train-shards "$TRAIN_SHARDS" \
    --results-dir "$RESULTS_DIR" \
    --mode "$MODE"
)"
STARTUP_COMMAND_QUOTED="$(
  python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$STARTUP_COMMAND"
)"

SECURE_FLAG=()
if [[ "${SECURE_CLOUD:-false}" == "true" ]]; then
  SECURE_FLAG+=(--secureCloud)
fi

CMD=(
  runpodctl create pod
  --name "$POD_NAME"
  --containerDiskSize "$CONTAINER_DISK_GB"
  --volumeSize "$VOLUME_GB"
  --volumePath "${VOLUME_PATH:-/workspace}"
  --args "$STARTUP_COMMAND"
)

if [[ -n "${TEMPLATE_ID:-}" ]]; then
  CMD+=(--templateId "$TEMPLATE_ID")
else
  CMD+=(--gpuType "$GPU_TYPE" --gpuCount "$GPU_COUNT" --imageName "$RUNPOD_IMAGE_NAME")
fi

if [[ -n "${MIN_VCPU:-}" ]]; then
  CMD+=(--vcpu "$MIN_VCPU")
fi

if [[ -n "${MIN_MEM_GB:-}" ]]; then
  CMD+=(--mem "$MIN_MEM_GB")
fi

if [[ -n "${MAX_COST_PER_HOUR:-}" ]]; then
  CMD+=(--cost "$MAX_COST_PER_HOUR")
fi

if [[ -n "${PORTS:-}" ]]; then
  for port in ${PORTS}; do
    CMD+=(--ports "$port")
  done
fi

if [[ ${#SECURE_FLAG[@]} -gt 0 ]]; then
  CMD+=("${SECURE_FLAG[@]}")
fi

if [[ -n "${EXTRA_POD_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FLAGS=( $EXTRA_POD_FLAGS )
  CMD+=("${EXTRA_FLAGS[@]}")
fi

printf 'Rendered startup command:\n%s\n\n' "$STARTUP_COMMAND"
printf 'Runpod command:'
printf ' %q' "${CMD[@]}"
printf '\n'
printf 'SSH note: if Runpod generates an RSA keypair, macOS OpenSSH may require `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa`.\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

if [[ -z "${RUNPOD_SKIP_CONFIGURE:-}" ]]; then
  printf 'Configuring runpodctl with provided API key\n'
  runpodctl config --apiKey "$RUNPOD_API_KEY"
else
  printf 'Skipping runpodctl reconfiguration; using existing local CLI auth.\n'
fi

"${CMD[@]}"
