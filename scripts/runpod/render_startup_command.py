#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shlex


def q(value: str) -> str:
    return shlex.quote(value)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render the pod startup command.")
    parser.add_argument("--run-preset", required=True)
    parser.add_argument("--data-variant", required=True)
    parser.add_argument("--train-shards", required=True)
    parser.add_argument("--results-dir", required=True)
    parser.add_argument("--workspace-root", default="/workspace")
    parser.add_argument("--automation-root", default="")
    parser.add_argument("--repo-root", default="")
    parser.add_argument(
        "--automation-repo-url",
        default="https://github.com/unibox-design/GOLF.git",
    )
    parser.add_argument(
        "--mode",
        choices=["bootstrap", "idle"],
        default="bootstrap",
        help="bootstrap runs the automation flow; idle keeps the container alive for manual debugging",
    )
    args = parser.parse_args()

    workspace_root = args.workspace_root
    automation_root = args.automation_root or f"{workspace_root}/golf"
    repo_root = args.repo_root or f"{workspace_root}/parameter-golf"
    log_path = f"{args.results_dir}/{args.run_preset}.log"

    if args.mode == "idle":
        return _print_idle(args.results_dir)

    setup = (
        f"set -euo pipefail; "
        f"mkdir -p {q(args.results_dir)} {q(workspace_root)}; "
        f"if [ ! -d {q(automation_root)}/.git ]; then "
        f"git clone {q(args.automation_repo_url)} {q(automation_root)}; "
        f"else git -C {q(automation_root)} pull --ff-only || true; fi; "
        f"/usr/bin/env "
        f"RUN_PRESET={q(args.run_preset)} "
        f"DATA_VARIANT={q(args.data_variant)} "
        f"TRAIN_SHARDS={q(args.train_shards)} "
        f"RESULTS_DIR={q(args.results_dir)} "
        f"RUN_LOG_PATH={q(log_path)} "
        f"WORKSPACE_ROOT={q(workspace_root)} "
        f"REPO_ROOT={q(repo_root)} "
        f"AUTOMATION_ROOT={q(automation_root)} "
        f"KEEP_ALIVE_ON_EXIT=1 "
        f"/bin/bash {q(automation_root)}/scripts/runpod/bootstrap.sh"
    )
    print(f"/bin/bash -lc {q(setup)}")
    return 0


def _print_idle(results_dir: str) -> int:
    command = (
        "set -euo pipefail; "
        f"mkdir -p {q(results_dir)}; "
        f"echo idle > {q(results_dir)}/bootstrap.status; "
        "exec sleep infinity"
    )
    print(f"/bin/bash -lc {q(command)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
