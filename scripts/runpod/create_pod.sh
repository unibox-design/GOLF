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

contains_exact() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
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
    --workspace-root "${WORKSPACE_ROOT:-/workspace}" \
    --automation-root "${AUTOMATION_ROOT:-}" \
    --repo-root "${REPO_ROOT_ON_POD:-}" \
    --automation-repo-url "${AUTOMATION_REPO_URL:-https://github.com/unibox-design/GOLF.git}" \
    --mode "$MODE"
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
elif [[ "${AUTO_GPU_PICK:-0}" == "1" ]]; then
  live_gpu_types=()
  while IFS= read -r row; do
    [[ -n "$row" ]] && live_gpu_types+=("$row")
  done < <(
    runpodctl get cloud | awk '
      NR<=1 { next }
      $0 ~ /^[[:space:]]*$/ { next }
      $0 ~ /^SUPER[[:space:]]*$/ { next }
      $0 ~ /^Generation[[:space:]]*$/ { next }
      $0 ~ /^Blackwell/ { next }
      $0 ~ /^Edition[[:space:]]*$/ { next }
      {
        line=$0
        gsub(/\r/, "", line)
        n=split(line, fields, /[[:space:]]{2,}/)
        if (n < 5) next
        gpu=fields[1]
        mem=fields[2]+0
        vcpu=fields[3]+0
        spot=fields[4]
        ondemand=fields[5]
        if (spot == "Reserved" && ondemand == "Reserved") next
        price = (ondemand == "Reserved" ? spot : ondemand)
        if (price == "Reserved") next
        printf "%s\t%d\t%d\t%.3f\n", gpu, mem, vcpu, price + 0
      }
    '
  )

  PREFERRED_GPU_ORDER=(
    "1x NVIDIA GeForce RTX 4090"
    "1x NVIDIA GeForce RTX 4080"
    "1x NVIDIA A40"
    "1x NVIDIA RTX A5000"
    "1x NVIDIA RTX A6000"
    "1x NVIDIA GeForce RTX 4070 Ti"
    "1x NVIDIA RTX 5000 Ada"
    "1x NVIDIA RTX 4000 Ada"
    "1x NVIDIA L40S"
    "1x NVIDIA GeForce RTX 3090 Ti"
    "1x NVIDIA GeForce RTX 3090"
    "1x NVIDIA A100 80GB PCIe"
    "1x NVIDIA A100-SXM4-80GB"
    "1x NVIDIA H100 PCIe"
    "1x NVIDIA H100 80GB HBM3"
    "1x NVIDIA H100 NVL"
  )

  live_gpu_names=()
  for row in "${live_gpu_types[@]}"; do
    gpu_name="${row%%$'\t'*}"
    rest="${row#*$'\t'}"
    mem_gb="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    vcpu_count="${rest%%$'\t'*}"
    price="${rest#*$'\t'}"

    if [[ -n "${MIN_MEM_GB:-}" ]] && (( mem_gb < MIN_MEM_GB )); then
      continue
    fi
    if [[ -n "${MIN_VCPU:-}" ]] && (( vcpu_count < MIN_VCPU )); then
      continue
    fi
    if [[ -n "${MAX_COST_PER_HOUR:-}" ]]; then
      awk_check="$(awk -v p="$price" -v m="$MAX_COST_PER_HOUR" 'BEGIN { exit !(p <= m) }' && echo ok || true)"
      if [[ "$awk_check" != "ok" ]]; then
        continue
      fi
    fi

    live_gpu_names+=("$gpu_name")
  done

  for preferred in "${PREFERRED_GPU_ORDER[@]}"; do
    if contains_exact "$preferred" "${live_gpu_names[@]}"; then
      GPU_TYPES+=("${preferred#1x }")
    fi
  done

  for gpu_name in "${live_gpu_names[@]}"; do
    if ! contains_exact "${gpu_name#1x }" "${GPU_TYPES[@]}"; then
      GPU_TYPES+=("${gpu_name#1x }")
    fi
  done
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
