# GitHub, Docker, and Runpod Automation

## Goal

Automate the experiment loop with:

- GitHub as the source of truth
- Docker images for reproducible runtime
- `runpodctl` for pod creation

## Architecture

1. Push code to GitHub.
2. GitHub Actions builds a thin `docker/runpod.Dockerfile` image and pushes it to GHCR.
3. A local script uses `runpodctl` plus `config/runpod.env` to create a pod from that image.
4. The pod startup command:
   - clones `parameter-golf` onto the Runpod volume if needed
   - installs Python dependencies onto the pod the first time
   - downloads the cached dataset shard
   - launches the configured experiment preset
   - parses the log into `experiments.csv`
   - stays alive for inspection even if bootstrap fails

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
- `config/runpod.dev-4090.env`
- `config/runpod.baseline-h100.env`
- `scripts/runpod/create_pod.sh`
- `scripts/runpod/render_startup_command.py`
- `scripts/runpod/bootstrap.sh`

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
   - start with `config/runpod.dev-4090.env` for cheaper validation runs
   - move to `config/runpod.baseline-h100.env` only after the flow is stable
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

1. clones `parameter-golf` to `/runpod/parameter-golf` if it is not already present
2. installs Python dependencies once and caches that state on the volume
3. downloads `sp1024` cached data with the requested shard count
4. launches the named preset through `scripts/launch_run.sh`
5. parses the resulting log into `experiments.csv`

Logs and CSV output are written into `/runpod/results` by default.

Important files inside the pod:

- `/runpod/results/bootstrap.log`
- `/runpod/results/bootstrap.status`
- `/runpod/results/<preset>.log`
- `/runpod/results/experiments.csv`

## Notes

- This is intentionally a first-pass automation path.
- Result export back to GitHub can be added later as a second step.
- The default GPU base image is `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`.
- The image is intentionally thin. Heavy repo clone, dependency install, and dataset setup happen on the pod volume instead of during GitHub image build.
- `runpodctl create pod` supports `--templateId`, but reusable Pod templates are not created by this CLI flow. The `.env` files in `config/` are the reusable launch presets for now.
- Current Runpod pricing from `runpodctl get cloud` on March 19, 2026 shows roughly:
  - `1x RTX 4090`: `$0.20/hr` spot, `$0.34/hr` on-demand
  - `1x A40`: `$0.24/hr` spot, `$0.35/hr` on-demand
  - `1x H100 80GB HBM3`: `$1.50/hr` spot, `$2.69/hr` on-demand
- For first runs, `1x RTX 4090` is the best cost/performance default in this list.
- Some Runpod-managed SSH keys are RSA. On recent macOS OpenSSH builds, you may need:
  - `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa`
