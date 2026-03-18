#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
from datetime import datetime, timezone
from pathlib import Path


VAL_BPB_RE = re.compile(r"final_int8_zlib_roundtrip(?:_exact)?[^\n]*?val_bpb:([0-9.]+)")
VAL_LOSS_RE = re.compile(r"final_int8_zlib_roundtrip(?:_exact)?[^\n]*?val_loss:([0-9.]+)")
MODEL_BYTES_RE = re.compile(r"(?:Serialized model int8\+zlib|model_bytes):\s*([0-9]+)")
CODE_BYTES_RE = re.compile(r"(?:Code size|code_bytes):\s*([0-9]+)")
TOTAL_BYTES_RE = re.compile(r"(?:Total submission size int8\+zlib|total_bytes):\s*([0-9]+)")


def last_match(pattern: re.Pattern[str], text: str) -> str:
    matches = pattern.findall(text)
    return matches[-1] if matches else ""


def classify_status(text: str, val_bpb: str) -> str:
    lowered = text.lower()
    if val_bpb:
        return "completed"
    if "traceback" in lowered or "error" in lowered:
        return "failed"
    return "incomplete"


def append_row(csv_path: Path, row: dict[str, str]) -> None:
    with csv_path.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "timestamp",
                "run_id",
                "preset",
                "status",
                "log_path",
                "val_loss",
                "val_bpb",
                "model_bytes",
                "code_bytes",
                "total_bytes",
                "notes",
            ],
        )
        writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse a parameter-golf training log.")
    parser.add_argument("--log", required=True, help="Path to the training log")
    parser.add_argument("--run-id", required=True, help="Logical run id")
    parser.add_argument("--preset", required=True, help="Preset name used for the run")
    parser.add_argument("--append", help="CSV file to append to")
    parser.add_argument("--notes", default="", help="Optional notes column")
    args = parser.parse_args()

    log_path = Path(args.log)
    text = log_path.read_text(encoding="utf-8", errors="replace")

    val_bpb = last_match(VAL_BPB_RE, text)
    val_loss = last_match(VAL_LOSS_RE, text)
    model_bytes = last_match(MODEL_BYTES_RE, text)
    code_bytes = last_match(CODE_BYTES_RE, text)
    total_bytes = last_match(TOTAL_BYTES_RE, text)
    status = classify_status(text, val_bpb)

    row = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "run_id": args.run_id,
        "preset": args.preset,
        "status": status,
        "log_path": str(log_path),
        "val_loss": val_loss,
        "val_bpb": val_bpb,
        "model_bytes": model_bytes,
        "code_bytes": code_bytes,
        "total_bytes": total_bytes,
        "notes": args.notes,
    }

    for key in row:
        print(f"{key}={row[key]}")

    if args.append:
        append_row(Path(args.append), row)
        print(f"appended_to={args.append}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
