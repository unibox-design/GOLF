#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod/ssh_command.sh POD_ID [--no-rsa-flags] [--key PATH]

Print a ready-to-run SSH command for a Runpod pod based on `runpodctl ssh connect`.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

POD_ID="$1"
shift

KEY_PATH="${HOME}/.runpod/ssh/Proximity-MBP-ed25519"
USE_RSA_FLAGS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY_PATH="$2"; shift 2 ;;
    --no-rsa-flags) USE_RSA_FLAGS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

CONNECT_OUTPUT="$(runpodctl ssh connect "$POD_ID")"

if [[ "$CONNECT_OUTPUT" != ssh\ * ]]; then
  printf '%s\n' "$CONNECT_OUTPUT" >&2
  exit 1
fi

BASE_CMD="$CONNECT_OUTPUT -i $KEY_PATH"
if [[ "$USE_RSA_FLAGS" -eq 1 ]]; then
  BASE_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa ${CONNECT_OUTPUT#ssh } -i $KEY_PATH"
else
  BASE_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CONNECT_OUTPUT#ssh } -i $KEY_PATH"
fi

printf '%s\n' "$BASE_CMD"
