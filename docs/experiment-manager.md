# Experiment Manager Design

## Goal

Provide a minimal, reliable wrapper around `parameter-golf` experiments so runs are easier to repeat and compare.

## Principles

- Keep configuration separate from execution.
- Keep every run reproducible from a preset plus a command line.
- Store logs and results in plain files.
- Avoid adding dependencies beyond shell and Python standard library.

## Core Files

### `config/runs.example.json`

Named presets. Each preset contains:

- `description`: short human label
- `env`: environment variables passed to the training command
- `command`: command array to execute inside the `parameter-golf` repo

The config file is deliberately JSON so it can be parsed with the Python standard library.

### `experiments.csv`

Single ledger of completed parse results.

Columns:

- `timestamp`
- `run_id`
- `preset`
- `status`
- `log_path`
- `val_loss`
- `val_bpb`
- `model_bytes`
- `code_bytes`
- `total_bytes`
- `notes`

### `scripts/launch_run.sh`

Responsibilities:

- read a named preset from the config file
- build the environment and command
- create a timestamped log path
- print the fully expanded command
- optionally execute it

It does not parse logs itself. That stays separate.

### `scripts/parse_log.py`

Responsibilities:

- inspect a training log
- extract final metrics when present
- classify the run status
- optionally append one result row to `experiments.csv`

### `scripts/summarize_results.py`

Responsibilities:

- read `experiments.csv`
- sort by best `val_bpb`
- print a compact table

## Why This Shape

This keeps the workflow understandable for a beginner:

1. presets define what to run
2. launcher starts it
3. parser records the result
4. summary compares runs

That is enough to support disciplined experimentation before introducing a larger automation layer.

## Current Local Reference Runs

- `baseline_dev_manual_2026-03-20`
  - completed on a manual Runpod pod with the pinned EU volume
  - `val_bpb=1.61206716`

- `kv2_failed_2026-03-20`
  - useful negative result
  - compile-enabled `kv2` failed on the RTX 4090 because of an Inductor/Triton resource error

- `kv2_dev_2026-03-20`
  - current best local dev run
  - `val_bpb=1.60084048`
  - confirms that `NUM_KV_HEADS=2` is better than the current `baseline_dev` on this setup when compile is disabled
