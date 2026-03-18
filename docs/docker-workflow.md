# Docker Workflow

## Goal

Run the experiment manager and `parameter-golf` commands in containers so local testing and remote runs use the same entrypoints.

## Services

### `manager`

Lightweight Python container for:

- parsing logs
- summarizing `experiments.csv`
- validating configs

It does not install the `parameter-golf` training stack.

### `trainer`

Training container for:

- launching presets with `scripts/launch_run.sh`
- running `train_gpt.py`
- writing logs into the mounted workspace

The trainer image is built from a configurable base image so you can choose a CPU-friendly or GPU-capable foundation depending on where you run it.

## Files

- `compose.yml`
- `docker/manager.Dockerfile`
- `docker/trainer.Dockerfile`
- `scripts/docker_launch.sh`

## Default Assumptions

- The workspace is mounted at `/workspace` inside containers.
- The `parameter-golf` repo is available at `/workspace/parameter-golf`.
- Logs are written to `/workspace/logs`.
- Results are written to `/workspace/experiments.csv`.

## Common Commands

### 1. Validate the Compose configuration

```bash
docker compose config
```

### 2. Summarize results in the manager container

```bash
docker compose run --rm manager \
  python scripts/summarize_results.py --csv experiments.csv
```

### 3. Dry-run a baseline launch in the trainer container

```bash
docker compose run --rm trainer \
  bash scripts/launch_run.sh \
    --config config/runs.example.json \
    --run baseline \
    --repo /workspace/parameter-golf \
    --dry-run
```

### 4. Use the wrapper script

```bash
bash scripts/docker_launch.sh \
  --run baseline \
  --repo /workspace/parameter-golf \
  --dry-run
```

## Choosing a Trainer Base Image

The trainer build uses the `TRAINER_BASE_IMAGE` build arg.

Examples:

- local CPU-oriented testing:
  - `TRAINER_BASE_IMAGE=python:3.12-slim`
- Runpod or another CUDA host:
  - set `TRAINER_BASE_IMAGE` to a CUDA-capable image that already matches your preferred Python and PyTorch stack

The image choice is left explicit because the right CUDA base depends on the host provider and the runtime you want to standardize on.

## Notes

- `train_gpt_mlx.py` is not a Docker target here. MLX is for native Apple Silicon runs.
- For Docker-based iteration, use `train_gpt.py` and plan to run serious experiments on a remote GPU host.
