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
