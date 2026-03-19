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
    args = parser.parse_args()

    log_path = f"{args.results_dir}/{args.run_preset}.log"
    csv_path = f"{args.results_dir}/experiments.csv"
    bootstrap_log = f"{args.results_dir}/bootstrap.log"
    status_file = f"{args.results_dir}/bootstrap.status"

    command = (
        f"mkdir -p {q(args.results_dir)} && "
        f"("
        f"cd /workspace/golf/parameter-golf && "
        f"python3 data/cached_challenge_fineweb.py --variant {q(args.data_variant)} "
        f"--train-shards {q(args.train_shards)} && "
        f"cd /workspace/golf && "
        f"bash scripts/launch_run.sh --config config/runs.example.json "
        f"--run {q(args.run_preset)} --repo /workspace/golf/parameter-golf "
        f"--results {q(csv_path)} --log-path {q(log_path)} && "
        f"python3 scripts/parse_log.py --log {q(log_path)} --run-id {q(args.run_preset)} "
        f"--preset {q(args.run_preset)} --append {q(csv_path)}"
        f") > >(tee -a {q(bootstrap_log)}) 2>&1; rc=$?; "
        f"echo $rc > {q(status_file)}; "
        f"echo \"bootstrap_exit_code=$rc\" | tee -a {q(bootstrap_log)}; "
        f"tail -f /dev/null"
    )

    print(command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
