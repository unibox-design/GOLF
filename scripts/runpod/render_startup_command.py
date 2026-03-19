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
    parser.add_argument(
        "--mode",
        choices=["bootstrap", "idle"],
        default="bootstrap",
        help="bootstrap runs the automation flow; idle keeps the container alive for manual debugging",
    )
    args = parser.parse_args()

    log_path = f"{args.results_dir}/{args.run_preset}.log"
    if args.mode == "idle":
        print("/bin/bash -lc 'mkdir -p /runpod/results && echo idle > /runpod/results/bootstrap.status && exec sleep infinity'")
        return 0

    command = (
        f"/usr/bin/env "
        f"RUN_PRESET={q(args.run_preset)} "
        f"DATA_VARIANT={q(args.data_variant)} "
        f"TRAIN_SHARDS={q(args.train_shards)} "
        f"RESULTS_DIR={q(args.results_dir)} "
        f"RUN_LOG_PATH={q(log_path)} "
        f"REPO_ROOT=/runpod/parameter-golf "
        f"AUTOMATION_ROOT=/opt/golf "
        f"KEEP_ALIVE_ON_EXIT=1 "
        f"/bin/bash /opt/golf/scripts/runpod/bootstrap.sh"
    )

    print(command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
