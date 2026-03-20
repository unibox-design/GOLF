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

## Leaderboard Lessons

Current public leaderboard direction, from strongest apparent signal to more complex ideas:

- Current public top record is `1.1748` and combines multiple ideas at once: sliding-window evaluation, fp16 tied embedding export, 10 layers, Muon weight decay, and specialized initialization.
- That means we should separate ideas into two buckets:
  - cheap next experiments on our current dev loop
  - more ambitious H100-side experiments once the volume-backed runtime is fully persistent

### 1. Evaluation strategy matters a lot

- `SlidingWindowEval` improved the naive baseline from `1.2244` to `1.1925` without materially changing training.
- The gain comes from scoring each token with much richer left context during validation instead of evaluating disjoint 1024-token chunks.
- This is one of the biggest currently published gains and should be considered a high-priority future step for us.
- It also increases evaluation cost materially, so it is better treated as a focused scoring improvement than a cheap everyday dev-loop default.

### 2. Quantization-aware choices matter almost as much as training choices

- `FP16Embed` and `WarmdownQuantization` both show that post-training quantization error is a major bottleneck.
- The tied embedding is unusually sensitive because it serves as both input embedding and output head.
- Keeping the tied embedding in fp16 during export appears to buy a large fraction of the published gains.
- Longer or more aggressive warmdown schedules also reduce quantization damage by smoothing the weight distribution.

### 3. Lower learning rates are a real baseline improvement

- The public `LowerLR` record reports that the baseline default learning rates are too high.
- A lower-LR variant around `MATRIX_LR=0.02`, `SCALAR_LR=0.02`, `TIED_EMBED_LR=0.03` improved the post-quant score over the naive baseline while keeping the architecture unchanged.
- This is an attractive next step for us because it is simple, cheap to test, and compatible with the current winner.

### 4. Longer sequence length can help

- Public `Seq2048` and `Seq4096` records show real gains from training with longer context.
- The tradeoff is fewer steps per 10-minute run, so this likely pays off more on faster hardware than on our current 4090 dev path.
- We are already testing the smaller version of this idea locally via `kv2_seq512_dev`, but the stronger leaderboard signal points upward in sequence length, not downward.

### 5. Extra depth also looks promising

- The current top public record includes `10 layers` plus several other changes.
- Another published record also improved over baseline with a 10-layer model plus lower learning rates and mixed precision export.
- Depth is therefore worth testing, but likely after we finish the lower-risk tuning ideas around the current `kv2_dev` winner.
- The practical lesson is not simply "add depth"; it is "add depth only when compression/export strategy is good enough to pay for it."

### 6. Some top gains are evaluation- or systems-heavy rather than architecture-heavy

- `SlidingWindowEval` is mostly evaluation logic.
- `LoRA TTT` shows that test-time adaptation can help, but the ablation suggests much of its gain comes from document isolation and strided evaluation rather than the LoRA updates themselves.
- These ideas are interesting, but they are higher complexity than the next changes we should make on the current dev loop.

## Practical Interpretation For Us

Given our current state:

1. We already have one winning local change: `NUM_KV_HEADS=2`.
2. The next cheapest likely improvements are:
   - lower learning rates
   - export/quantization changes, especially fp16 tied embedding
   - eventually sliding-window or richer-context evaluation
3. Longer-context and deeper-model ideas probably become more informative once we validate on H100-class hardware.
4. The current public frontier is already mixing architecture, evaluation, and export tricks, so we should avoid overfitting to architecture-only ideas.

## Recommended Next Sequence

1. Finish current dev comparisons around `kv2_dev`.
2. Add a lower-LR variant on top of `kv2_dev`.
3. Add an fp16-embedding export variant if the code change stays small.
4. Move the Python environment and pip cache onto the persistent volume.
5. Run the best current config on a single H100.
6. Only after that consider more expensive record-style experiments or a PR submission.
