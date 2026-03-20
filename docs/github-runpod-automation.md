# GitHub, Docker, and Runpod Automation

## Goal

Automate the experiment loop with:

- GitHub as the source of truth
- Docker images for reproducible runtime
- `runpodctl` for pod creation

## Architecture

1. Push code to GitHub.
2. GitHub Actions can still build a custom image, but the default launch path now prefers a stock Runpod PyTorch image because it placed more reliably with pinned network volumes.
3. A local script uses `runpodctl` plus `config/runpod.env` to create a pod from that image.
4. The pod startup command:
   - clones this automation repo onto the Runpod volume if needed
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
- `config/runpod.env.example`
- `config/runpod.dev-4090.env`
- `config/runpod.baseline-h100.env`
- `config/runs.example.json`
- `scripts/runpod/create_pod.sh`
- `scripts/runpod/run_existing_pod.sh`
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
   - optionally pin `DATA_CENTER_ID`
   - optionally attach `NETWORK_VOLUME_ID`
   - set `GPU_CANDIDATES` to an ordered list if you want the launcher to try multiple GPU types automatically
   - use `MAX_COST_PER_HOUR` to keep those attempts under your spending cap
   - quote any env values that contain spaces, such as `GPU_TYPE="NVIDIA H100 PCIe"`
   - start with `config/runpod.dev-4090.env` for cheaper validation runs
   - if `4090` placement is unavailable in your pinned region, let `GPU_CANDIDATES` fall through to the next suitable option
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

To start a configured run on an already running pod:

```bash
bash scripts/runpod/run_existing_pod.sh <pod-id> --env-file config/runpod.env
```

To override the preset for that pod run:

```bash
bash scripts/runpod/run_existing_pod.sh <pod-id> --env-file config/runpod.env --run-preset kv2_dev
```

## What the Pod Does

The pod starts from the published Docker image and runs one shell command. That command:

1. clones `parameter-golf` to `/runpod/parameter-golf` if it is not already present
2. installs Python dependencies once and caches that state on the volume
3. downloads `sp1024` cached data with the requested shard count
4. launches the named preset through `scripts/launch_run.sh`
5. parses the resulting log into `experiments.csv`

Logs and CSV output are written into `/workspace/results` by default.

Important files inside the pod:

- `/workspace/results/bootstrap.log`
- `/workspace/results/bootstrap.status`
- `/workspace/results/<preset>.log`
- `/workspace/results/experiments.csv`

## Region and persistent volume

`runpodctl create pod` supports both:

- `--dataCenterId`
- `--networkVolumeId`

The current CLI does not expose volume creation/listing commands, so the practical setup is:

1. create a network volume in the Runpod UI
2. choose the datacenter explicitly
3. copy the datacenter id and network volume id into the env file
4. launch pods attached to that same volume

Recommended approach:

- pick one region for dev work and stay there
- use a GPU type that is actually available in that region
- reuse the same network volume across pods in that region
- keep an ordered GPU candidate list ready so a capacity miss does not block your next test

If you want an EU dev setup, use an EU datacenter only if your chosen GPU is actually offered there at the time you launch.

Practical fallback set for this repo:

1. `RTX 4090`
2. `RTX 4080`
3. `A40`
4. `RTX PRO 4500`
5. `RTX 5090`
6. `RTX 2000 Ada`
7. `RTX PRO 6000`
8. `RTX PRO 6000 WK`
9. `RTX 4000 Ada`
10. `L4`

They all use the same `baseline_dev` preset and the same mounted volume. The launcher tries them in order until one succeeds.

Example:

```env
GPU_CANDIDATES="NVIDIA GeForce RTX 4090;NVIDIA GeForce RTX 4080;NVIDIA A40"
MAX_COST_PER_HOUR=3
DATA_CENTER_ID=EU-RO-1
NETWORK_VOLUME_ID=your-volume-id
```

The launcher will try those GPU types in order against the same pinned region and volume until one succeeds. Expand that list if your region tends to surface different cards across the day.

## Notes

- This is intentionally a first-pass automation path.
- Result export back to GitHub can be added later as a second step.
- The default launch image is `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`.
- Heavy repo clone, dependency install, and dataset setup happen on the mounted `/workspace` volume instead of during image build.
- `--mode idle` is the recommended first debug step whenever pod startup behavior is unclear.
- `runpodctl create pod` supports `--templateId`, but reusable Pod templates are not created by this CLI flow. The `.env` files in `config/` are the reusable launch presets for now.
- Current Runpod pricing from `runpodctl get cloud` on March 19, 2026 shows roughly:
  - `1x RTX 4090`: `$0.20/hr` spot, `$0.34/hr` on-demand
  - `1x RTX 4080`: `$0.17/hr` spot, `$0.28/hr` on-demand
  - `1x A40`: `$0.24/hr` spot, `$0.35/hr` on-demand
  - `1x H100 80GB HBM3`: `$1.50/hr` spot, `$2.69/hr` on-demand
- For first runs, `1x RTX 4090` is the best cost/performance default in this list when available.
- `RTX 4080` and `A40` are the first fallback options for the same dev workflow.
- A `MAX_COST_PER_HOUR` cap of `3` leaves headroom for all current dev options and a future single-H100 experiment.
- Some Runpod-managed SSH keys are RSA. On recent macOS OpenSSH builds, you may need:
  - `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa`

## Lessons Learned

### Image and startup model

- A stock Runpod PyTorch image placed more reliably than the custom GHCR image when using a pinned network volume.
- Clone both this automation repo and `parameter-golf` onto the mounted `/workspace` volume during bootstrap.
- Keep runtime state on `/workspace` so future pods can reuse the same repo, data, and results.
- When pod startup behavior is unclear, use `--mode idle` first and verify container stability before running bootstrap.

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

### Recorded smoke result

- Manual pod on `EU-RO-1` volume `GOLF_VOL`
- Stock image: `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`
- Torch upgraded during bootstrap to satisfy `enable_gqa`
- Final exact result:
  - `val_bpb: 1.61206716`
  - `val_loss: 2.72190787`
  - `total submission size int8+zlib: 9045206`

### Recorded improvement

- Existing-pod helper run on the same manual pod
- Preset: `kv2_dev`
- Change relative to baseline dev: `NUM_KV_HEADS=2` with compile disabled
- Final exact result:
  - `val_bpb: 1.60084048`
  - `val_loss: 2.70295209`
  - `total submission size int8+zlib: 9958297`
- This beat the local `baseline_dev` reference by about `0.0112` bpb

### Automation status

- GitHub build automation works
- Existing-pod experiment automation works
- Direct CLI pod creation against the pinned `EU-RO-1` network volume is still unreliable
- Practical workflow today:
  - create the pod manually in Runpod UI
  - run experiments through `scripts/runpod/run_existing_pod.sh`

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
