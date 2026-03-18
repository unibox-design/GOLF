# GitHub, Docker, and Runpod Automation

## Goal

Automate the experiment loop with:

- GitHub as the source of truth
- Docker images for reproducible runtime
- `runpodctl` for pod creation

## Architecture

1. Push code to GitHub.
2. GitHub Actions builds `docker/runpod.Dockerfile` and pushes the image to GHCR.
3. A local script uses `runpodctl` plus `config/runpod.env` to create a pod from that image.
4. The pod startup command:
   - creates a results directory
   - downloads the cached dataset shard
   - launches the configured experiment preset
   - parses the log into `experiments.csv`

## Required Secrets

### Local

- `RUNPOD_API_KEY` in `config/runpod.env`

### GitHub repository secrets

- `GHCR_PAT` is optional if you need a personal token for package publishing

For most repositories, the default `GITHUB_TOKEN` is enough to push to GHCR when the workflow permissions are set correctly.

## Files

- `.github/workflows/build-runpod-image.yml`
- `docker/runpod.Dockerfile`
- `config/runpod.env.example`
- `scripts/runpod/create_pod.sh`
- `scripts/runpod/render_startup_command.py`

## First-Time Setup

1. Create a GitHub repo for this workspace.
2. Push the current files.
3. Run the `Build Runpod Image` GitHub workflow.
4. Copy `config/runpod.env.example` to `config/runpod.env`.
5. Fill in:
   - `RUNPOD_API_KEY`
   - `RUNPOD_IMAGE_NAME`
   - your preferred GPU settings
   - quote any env values that contain spaces, such as `GPU_TYPE="NVIDIA H100 PCIe"`
6. Run:

```bash
bash scripts/runpod/create_pod.sh --env-file config/runpod.env --dry-run
```

Then launch the real pod:

```bash
bash scripts/runpod/create_pod.sh --env-file config/runpod.env
```

## What the Pod Does

The pod starts from the published Docker image and runs one shell command. That command:

1. downloads `sp1024` cached data with the requested shard count
2. launches the named preset through `scripts/launch_run.sh`
3. parses the resulting log into `experiments.csv`

Logs and CSV output are written into `/workspace/results` inside the pod.
Logs and CSV output are written into `/runpod/results` by default so they land on the persistent volume path that Runpod mounts automatically.

## Notes

- This is intentionally a first-pass automation path.
- Result export back to GitHub can be added later as a second step.
- For real GPU runs, use a CUDA-capable base image in `docker/runpod.Dockerfile` via the workflow input.
