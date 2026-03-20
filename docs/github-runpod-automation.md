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
- `config/runs.example.json`
- `scripts/runpod/create_pod.sh`
- `scripts/runpod/render_startup_command.py`
- `scripts/runpod/bootstrap.sh`
- `scripts/runpod/ssh_command.sh`
- `scripts/runpod/remote_exec.sh`

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
bash scripts/runpod/create_pod.sh --env-file config/runpod.env --mode bootstrap --dry-run
```

Then launch the real pod:

```bash
bash scripts/runpod/create_pod.sh --env-file config/runpod.env --mode bootstrap
```

For a debug pod that only stays alive for SSH/manual inspection:

```bash
bash scripts/runpod/create_pod.sh --env-file config/runpod.dev-4090.env --mode idle
```

To resolve the exact SSH command for a pod:

```bash
bash scripts/runpod/ssh_command.sh <pod-id>
```

To run a remote command through the resolved SSH path:

```bash
bash scripts/runpod/remote_exec.sh <pod-id> -- cat /runpod/results/bootstrap.status
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
- `--mode idle` is the recommended first debug step whenever pod startup behavior is unclear.
- `runpodctl create pod` supports `--templateId`, but reusable Pod templates are not created by this CLI flow. The `.env` files in `config/` are the reusable launch presets for now.
- Current Runpod pricing from `runpodctl get cloud` on March 19, 2026 shows roughly:
  - `1x RTX 4090`: `$0.20/hr` spot, `$0.34/hr` on-demand
  - `1x A40`: `$0.24/hr` spot, `$0.35/hr` on-demand
  - `1x H100 80GB HBM3`: `$1.50/hr` spot, `$2.69/hr` on-demand
- For first runs, `1x RTX 4090` is the best cost/performance default in this list.
- Some Runpod-managed SSH keys are RSA. On recent macOS OpenSSH builds, you may need:
  - `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa`

## Lessons Learned

### Image and startup model

- A thin image is better than a fully prepared image for this workflow.
- Keep only the automation code in the published image.
- Clone `parameter-golf`, install Python requirements, and download data on the Runpod volume during bootstrap.
- Mount the persistent volume at `/runpod`, not over the image path, so `/opt/golf` stays intact.
- When pod startup behavior is unclear, use `--mode idle` first and verify SSH/container stability before running bootstrap.

### SSH behavior on this machine

- `runpodctl ssh connect` is the source of truth for the current pod endpoint.
- Runpod-managed SSH keys may be RSA, and recent macOS OpenSSH defaults may reject them.
- The working SSH shape on this machine may require:
  - `-o PubkeyAcceptedAlgorithms=+ssh-rsa`
  - `-o HostKeyAlgorithms=+ssh-rsa`
- The helper scripts `scripts/runpod/ssh_command.sh` and `scripts/runpod/remote_exec.sh` exist to avoid re-solving this each time.

### 4090 smoke-run behavior

- On the `1x RTX 4090` dev pod, the baseline can fail under `torch.compile` with Triton/Inductor kernel generation errors.
- The observed failure was:
  - `No valid triton configs`
  - `OutOfMemoryError: out of resource`
- This was not a normal training-memory OOM. It was an Inductor/Triton codegen limitation on the dev GPU.
- For cheap development runs, use:
  - `TORCHDYNAMO_DISABLE=1`
- The repo now includes a dedicated `baseline_dev` preset for this path:
  - set `RUN_PRESET=baseline_dev`
  - `config/runpod.dev-4090.env` already points to it
- With compile disabled, the baseline training loop did start and progressed successfully on the 4090.

### Practical split

- Use `RTX 4090` for cheap smoke tests and pipeline validation.
- Prefer disabling compile on dev GPUs.
- Reserve the compiled path and more serious timing-sensitive tests for H100-class runs later.

### Cost and persistence tradeoff

- Persistent volume adds cost even when the pod is stopped.
- GPU runtime usually dominates storage cost, so the first priority is to avoid leaving pods running idle.
- For a casual experimentation workflow, the recommended balance is:
  - use cheap GPUs like `RTX 4090`
  - keep the persistent volume modest, around `10 GB`
  - store only the useful durable assets:
    - cloned repo
    - dataset cache
    - logs
    - results CSV
- Large long-lived volumes and always-on pods are unnecessary for this project stage.
- If you only do a few runs, recreating more state each time may be cheaper than carrying a large volume.
- If you iterate repeatedly, a small persistent volume is usually worth it because it avoids repeated clone/install/download work.
- Suggested defaults:
  - dev / `4090`: `10 GB`
  - more serious / `H100`: `20 GB`
