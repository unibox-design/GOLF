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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
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
  if [[ -z "${RUNPOD_IMAGE_NAME:-}" || -z "${GPU_COUNT:-}" ]]; then
    echo "When TEMPLATE_ID is empty, RUNPOD_IMAGE_NAME and GPU_COUNT are required." >&2
    exit 1
  fi
  if [[ -z "${GPU_TYPE:-}" && -z "${GPU_CANDIDATES:-}" ]]; then
    echo "When TEMPLATE_ID is empty, set GPU_TYPE or GPU_CANDIDATES." >&2
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

build_cmd() {
  local gpu_type="$1"
  local -a cmd=(
    runpodctl create pod
    --name "$POD_NAME"
    --containerDiskSize "$CONTAINER_DISK_GB"
    --volumeSize "$VOLUME_GB"
    --volumePath "${VOLUME_PATH:-/workspace}"
    --args "$STARTUP_COMMAND"
  )

  if [[ -n "${DATA_CENTER_ID:-}" ]]; then
    cmd+=(--dataCenterId "$DATA_CENTER_ID")
  fi

  if [[ -n "${NETWORK_VOLUME_ID:-}" ]]; then
    cmd+=(--networkVolumeId "$NETWORK_VOLUME_ID")
  fi

  if [[ -n "${TEMPLATE_ID:-}" ]]; then
    cmd+=(--templateId "$TEMPLATE_ID")
  else
    cmd+=(--gpuType "$gpu_type" --gpuCount "$GPU_COUNT" --imageName "$RUNPOD_IMAGE_NAME")
  fi

  if [[ -n "${MIN_VCPU:-}" ]]; then
    cmd+=(--vcpu "$MIN_VCPU")
  fi

  if [[ -n "${MIN_MEM_GB:-}" ]]; then
    cmd+=(--mem "$MIN_MEM_GB")
  fi

  if [[ -n "${MAX_COST_PER_HOUR:-}" ]]; then
    cmd+=(--cost "$MAX_COST_PER_HOUR")
  fi

  if [[ -n "${PORTS:-}" ]]; then
    for port in ${PORTS}; do
      cmd+=(--ports "$port")
    done
  fi

  if [[ ${#SECURE_FLAG[@]} -gt 0 ]]; then
    cmd+=("${SECURE_FLAG[@]}")
  fi

  if [[ -n "${EXTRA_POD_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    EXTRA_FLAGS=( $EXTRA_POD_FLAGS )
    cmd+=("${EXTRA_FLAGS[@]}")
  fi

  printf '%s\0' "${cmd[@]}"
}

build_cmd_array() {
  local gpu_type="$1"
  CMD=()
  while IFS= read -r -d '' item; do
    CMD+=("$item")
  done < <(build_cmd "$gpu_type")
}

GPU_TYPES=()
if [[ -n "${TEMPLATE_ID:-}" ]]; then
  GPU_TYPES+=("template")
elif [[ -n "${GPU_CANDIDATES:-}" ]]; then
  IFS=';' read -r -a raw_gpu_types <<< "$GPU_CANDIDATES"
  for raw_gpu_type in "${raw_gpu_types[@]}"; do
    gpu_type="$(trim "$raw_gpu_type")"
    if [[ -n "$gpu_type" ]]; then
      GPU_TYPES+=("$gpu_type")
    fi
  done
else
  GPU_TYPES+=("$GPU_TYPE")
fi

printf 'Rendered startup command:\n%s\n\n' "$STARTUP_COMMAND"
for gpu_type in "${GPU_TYPES[@]}"; do
  build_cmd_array "$gpu_type"
  if [[ "$gpu_type" == "template" ]]; then
    printf 'Runpod command:'
  else
    printf 'Runpod command for GPU %s:' "$gpu_type"
  fi
  printf ' %q' "${CMD[@]}"
  printf '\n'
done
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

last_status=1
for gpu_type in "${GPU_TYPES[@]}"; do
  build_cmd_array "$gpu_type"
  if [[ "$gpu_type" == "template" ]]; then
    printf 'Creating pod from template.\n'
    "${CMD[@]}"
    exit 0
  fi
  printf 'Trying GPU candidate: %s\n' "$gpu_type"
  set +e
  output="$("${CMD[@]}" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output"
  if [[ $status -eq 0 ]]; then
    exit 0
  fi
  last_status=$status
  printf 'GPU candidate failed: %s\n' "$gpu_type" >&2
done

exit "$last_status"
