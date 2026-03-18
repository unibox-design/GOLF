#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_float(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("inf")


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize experiment results.")
    parser.add_argument("--csv", required=True, help="Path to experiments.csv")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    rows.sort(key=lambda row: (parse_float(row.get("val_bpb", "")), row.get("timestamp", "")))

    print(
        f"{'preset':16} {'run_id':20} {'status':12} {'val_bpb':10} "
        f"{'val_loss':10} {'total_bytes':12} notes"
    )
    print("-" * 96)
    for row in rows:
        print(
            f"{row.get('preset', '')[:16]:16} "
            f"{row.get('run_id', '')[:20]:20} "
            f"{row.get('status', '')[:12]:12} "
            f"{row.get('val_bpb', '')[:10]:10} "
            f"{row.get('val_loss', '')[:10]:10} "
            f"{row.get('total_bytes', '')[:12]:12} "
            f"{row.get('notes', '')}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
