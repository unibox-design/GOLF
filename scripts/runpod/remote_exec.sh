#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/runpod/remote_exec.sh POD_ID [--key PATH] [--no-rsa-flags] -- COMMAND...

Resolve the Runpod SSH command for POD_ID and execute a remote shell command through it.
EOF
}

if [[ $# -gt 0 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -lt 3 ]]; then
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
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Missing remote command after --" >&2
  usage
  exit 1
fi

SSH_CMD="$(
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh_command.sh" \
    "$POD_ID" \
    --key "$KEY_PATH" \
    $([[ "$USE_RSA_FLAGS" -eq 1 ]] && printf '%s' "" || printf '%s' "--no-rsa-flags")
)"

REMOTE_COMMAND=""
for arg in "$@"; do
  if [[ -n "$REMOTE_COMMAND" ]]; then
    REMOTE_COMMAND+=" "
  fi
  REMOTE_COMMAND+="$(python3 -c 'import shlex,sys; print(shlex.quote(sys.argv[1]))' "$arg")"
done

printf 'Running: %s %s\n' "$SSH_CMD" "$REMOTE_COMMAND" >&2
eval "$SSH_CMD $REMOTE_COMMAND"
