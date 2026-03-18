#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/docker_launch.sh --run PRESET --repo REPO_PATH [--config CONFIG] [--dry-run] [--build]

Options:
  --run        Preset name inside the config file
  --repo       Repo path as seen from inside the container, usually /workspace/parameter-golf
  --config     Config file path inside the container (default: config/runs.example.json)
  --dry-run    Print the expanded launch script without executing it
  --build      Force a rebuild of the trainer image before running
EOF
}

CONFIG="config/runs.example.json"
RUN_NAME=""
REPO_PATH=""
DRY_RUN=0
FORCE_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --run) RUN_NAME="$2"; shift 2 ;;
    --repo) REPO_PATH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --build) FORCE_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RUN_NAME" || -z "$REPO_PATH" ]]; then
  usage
  exit 1
fi

if [[ "$FORCE_BUILD" -eq 1 ]]; then
  docker compose build trainer
fi

CMD=(
  docker compose run --rm trainer
  bash scripts/launch_run.sh
  --config "$CONFIG"
  --run "$RUN_NAME"
  --repo "$REPO_PATH"
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  CMD+=(--dry-run)
fi

printf 'Running:'
printf ' %q' "${CMD[@]}"
printf '\n'

"${CMD[@]}"
