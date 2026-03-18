# Parameter Golf Experiment Manager

Minimal script-based experiment manager for running and tracking `parameter-golf` experiments.

This project is intentionally small. It is meant to automate the boring parts of the workflow:

- define named run presets
- launch a run with a reproducible command
- save logs in a predictable location
- parse final metrics from a training log
- append results to `experiments.csv`
- summarize completed runs

## Scope

This scaffold does not modify the upstream `parameter-golf` codebase. It assumes you already have a clone of that repository somewhere else, either:

- on your local machine, or
- on a remote machine such as Runpod

The launcher works best when the scripts are copied into the same machine where the training command will run.

## File Layout

- `docs/experiment-manager.md`: workflow and design notes
- `docs/docker-workflow.md`: Docker-based workflow for repeatable runs
- `docs/github-runpod-automation.md`: GitHub image build plus Runpod launch workflow
- `config/runs.example.json`: example run presets
- `config/runpod.env.example`: template for Runpod automation settings
- `experiments.csv`: experiment ledger
- `scripts/launch_run.sh`: launches a configured run and records metadata
- `scripts/docker_launch.sh`: runs the launcher inside the trainer container
- `scripts/runpod/create_pod.sh`: creates a Runpod pod from a published image
- `scripts/runpod/render_startup_command.py`: renders the pod startup command
- `scripts/parse_log.py`: extracts final metrics from a training log
- `scripts/summarize_results.py`: prints a compact summary from `experiments.csv`
- `docker/manager.Dockerfile`: lightweight image for parser and summary tasks
- `docker/trainer.Dockerfile`: configurable training image
- `docker/runpod.Dockerfile`: published image for Runpod pods
- `.github/workflows/build-runpod-image.yml`: builds and pushes the Runpod image to GHCR
- `compose.yml`: container definitions
- `examples/sample_train.log`: sample log for local dry runs

## Intended Workflow

1. Copy or clone this scaffold onto the machine where `parameter-golf` will run.
2. Update `config/runs.example.json` or create your own config file.
3. Launch a run with `scripts/launch_run.sh`.
4. Let training finish and write a log file.
5. Parse the log and append metrics to `experiments.csv`.
6. Run `scripts/summarize_results.py` to compare outcomes.

## Quick Dry Run

Validate the parser and summary commands without needing GPUs:

```bash
python3 scripts/parse_log.py \
  --log examples/sample_train.log \
  --run-id sample-baseline \
  --preset baseline \
  --append experiments.csv

python3 scripts/summarize_results.py --csv experiments.csv
```

## Docker Workflow

Use Docker when you want a consistent execution environment across your machine and Runpod.

Manager-only tasks:

```bash
docker compose run --rm manager \
  python scripts/summarize_results.py --csv experiments.csv
```

Trainer tasks:

```bash
docker compose run --rm trainer \
  bash scripts/launch_run.sh \
    --config config/runs.example.json \
    --run baseline \
    --repo /workspace/parameter-golf \
    --dry-run
```

For a full guide, see [docs/docker-workflow.md](/Users/proximity/Documents/Golf/docs/docker-workflow.md).

## GitHub + Runpod Automation

The automated path is:

1. push code to GitHub
2. build a Runpod image in GitHub Actions
3. create a pod with `runpodctl`
4. let the pod download data and run the chosen preset automatically

Guide: [docs/github-runpod-automation.md](/Users/proximity/Documents/Golf/docs/github-runpod-automation.md)

## Next Step

Once the workflow is stable, this can be extended with:

- remote SSH execution
- notifications
- queued runs
- automatic polling and result ingestion
