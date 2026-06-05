# RunPod Flux Pipeline - Lessons Learned

Last updated: 2026-06-05

This document records practical findings from setting up and debugging the RunPod + ComfyUI + Flux controller pipeline. It is meant as project memory, so the same issues do not have to be rediscovered later.

## What GitHub Should Store

GitHub Free is suitable for:

- setup scripts
- controller source code
- ComfyUI API workflow JSON
- LoRA manifests
- README / operating notes
- troubleshooting notes like this file

GitHub Free is not suitable for the downloaded model files:

- `fluxunchained-dev-Q6_K.gguf` is about 9.2 GB
- `t5xxl_fp8_e4m3fn.safetensors` is about 4.6 GB
- `clip_l.safetensors` is about 235 MB
- `ae.safetensors` is about 319 MB
- LoRAs can be hundreds of MB each

Use GitHub as the recipe and logbook. Use RunPod volume, network volume, Hugging Face, object storage, or NAS for large binaries.

## Current Data Size Observed On RunPod

Observed approximate sizes:

```text
/workspace/ComfyUI                16 GB
/workspace/ComfyUI/models         15 GB
/workspace/ComfyUI/models/unet     9.2 GB
/workspace/ComfyUI/models/clip     4.8 GB
/workspace/ComfyUI/models/vae      319 MB
/workspace/ComfyUI/models/loras    302 MB+ depending on LoRAs
```

Useful size commands:

```bash
du -sh /workspace
du -sh /workspace/ComfyUI
du -sh /workspace/ComfyUI/models
du -sh /workspace/ComfyUI/models/*
du -sh /workspace/flux_controller_outputs
ls -lh /workspace/ComfyUI/models/unet
ls -lh /workspace/ComfyUI/models/clip
ls -lh /workspace/ComfyUI/models/vae
ls -lh /workspace/ComfyUI/models/loras
```

## RunPod Storage Lessons

### Volume Disk vs Network Volume

`Volume disk` is persistent storage mounted to `/workspace`, but it is tied to that Pod's lifecycle. It survives stopping and starting the same Pod. It is not a universal cloud drive automatically attached to every new Pod.

`Network volume` is the better long-term option when the same data must be reused with different GPUs or new Pods. It costs more, but it decouples the model data from one specific Pod.

### Practical Rule

For active experimentation, the current volume disk is fine.

For long-term reuse across GPUs, migrate model files to a network volume or other external storage later.

## RunPod Upload Lessons

### Browser Terminal Paste Is Fragile

Large pasted shell scripts can be truncated or inserted only partially in the RunPod web terminal. This caused broken heredocs and incomplete commands.

Avoid pasting long multi-line scripts into the terminal.

Better options:

- store scripts in GitHub and download them with `curl`
- use `git clone` for the repository
- use Jupyter file upload if the template exposes Jupyter
- use `runpodctl` only when the CLI is correctly configured

### runpodctl Was Not Reliable Initially

The local `runpodctl send` produced a receive code, but the Pod-side `runpodctl receive` failed until RunPod CLI config was created.

Observed issue:

```text
Runpod config file not found
runpodctl-receive: croc: receive: room not ready
```

Then `runpodctl config` failed with:

```text
API error: Unauthorized
```

Practical conclusion: for this project, GitHub raw downloads were simpler and more reliable than `runpodctl` for small files.

## GitHub Lessons

### Password Prompt For GitHub Clone

When cloning a public GitHub repository over HTTPS, no password should be needed if the URL is correct and the repo is public.

The earlier failed clone used a placeholder URL:

```bash
git clone https://github.com/TVUJ_USERNAME/runpod-flux-pipeline.git
```

The correct repository URL was:

```bash
git clone https://github.com/tibrigada-create/runpod-flux-pipeline.git
```

### `git pull` Can Be Blocked By Local Changes

Observed error:

```text
error: Your local changes to the following files would be overwritten by merge:
  setup_runpod.sh
Please commit your changes or stash them before you merge.
```

This happened because `setup_runpod.sh` was patched locally on the Pod. When this happens, avoid blindly overwriting local changes.

For a targeted controller update, it is usually enough to download only `app.py`:

```bash
pkill -f "/workspace/flux_controller/app.py" || true
curl -L https://raw.githubusercontent.com/tibrigada-create/runpod-flux-pipeline/main/app.py -o /workspace/flux_controller/app.py
/workspace/start_flux_controller.sh
```

If a full repository sync is needed, use a stash intentionally:

```bash
cd /workspace/runpod-flux-pipeline
git stash push -m "runpod local setup changes" setup_runpod.sh
git pull
```

## Startup Lessons

### Normal Startup

Start the whole stack:

```bash
/workspace/start_flux_stack.sh
```

This starts:

```text
ComfyUI backend:   127.0.0.1:8188
Gradio controller: 0.0.0.0:7860
```

### If Only Controller Needs Restart

Use this when ComfyUI is already running:

```bash
pkill -f "/workspace/flux_controller/app.py" || true
/workspace/start_flux_controller.sh
```

### If Only ComfyUI Needs Restart

Use this in a separate terminal:

```bash
/workspace/start_comfyui.sh
```

### Avoid Starting ComfyUI Twice

Observed ComfyUI error:

```text
Port 8188 is already in use on address 0.0.0.0
Could not acquire lock on database /workspace/ComfyUI/user/comfyui.db
```

Cause: another ComfyUI process was already running.

Check processes:

```bash
ps aux | grep -E "main.py|flux_controller|app.py" | grep -v grep
```

Stop duplicate ComfyUI only when needed:

```bash
pkill -f "python main.py" || true
```

## Controller / ComfyUI Connection Lessons

### Controller Works But Generate Fails With Connection Refused

Observed in controller:

```text
HTTPConnectionPool(host='127.0.0.1', port=8188): Failed to establish a new connection: [Errno 111] Connection refused
```

Meaning: Gradio controller is running on port `7860`, but ComfyUI backend is not running or has not finished starting.

Fix:

```bash
/workspace/start_comfyui.sh
```

Then wait until ComfyUI has finished loading and is listening on port `8188`.

### RunPod HTTP Services Can Show Initializing For A While

Port `7860` may show `Initializing...` until the Gradio server is actually listening. This should usually be seconds to a couple of minutes. If it stays initializing while the terminal shows no running controller, restart the controller.

## Gradio Output Path Lesson

Observed error:

```text
gradio.exceptions.InvalidPathError:
Cannot move /workspace/flux_controller_outputs/...png to the gradio cache dir
```

Cause: Gradio refused to serve files outside the app working directory.

Fix in `app.py`:

```python
allowed_paths=[str(DOWNLOAD_DIR)]
```

This is required in the `launch()` call.

## Flux VAE / AE Lesson

The original Black Forest Labs VAE URL returned:

```text
401 Unauthorized
```

A wrong VAE caused this ComfyUI runtime error:

```text
expected input ... to have 4 channels, but got 16 channels instead
```

Meaning: an SD/SDXL-style VAE was loaded instead of the Flux AE.

Working source:

```text
https://huggingface.co/MaxedOut/ComfyUI-Starter-Packs/resolve/main/Flux1/vae/ae.safetensors?download=true
```

Expected size:

```text
about 319 MB
```

Verification:

```bash
ls -lh /workspace/ComfyUI/models/vae/ae.safetensors
```

## Flux Parameter Lessons

Stable baseline:

```text
Sampler:       euler
Scheduler:     beta
CFG:           1.0 fixed
Flux guidance: 2.6 to 3.2
Steps:         28 to 34
Seed:          fixed for tests
LoRAs:         none for baseline tests
```

If outputs are too plastic:

```text
Flux guidance: 2.4 to 2.8
```

If outputs are too volatile:

```text
Randomize seed: off
Seed: fixed value
Flux guidance: around 3.0
LoRAs: none first
```

The controller UI was updated to allow:

```text
Flux guidance range: 1.0 to 4.0
Default:             2.6
Step:                0.05
```

CFG remains fixed at `1.0` for Flux and should not be raised like in older Stable Diffusion workflows.

## LoRA Lessons

### Where LoRAs Go

```text
/workspace/ComfyUI/models/loras
```

After adding LoRAs, press:

```text
Refresh model library
```

in the controller.

### First Working LoRA

The first successfully downloaded LoRA was:

```text
/workspace/ComfyUI/models/loras/srpo_32_base_oficial_model_fp16.safetensors
```

Observed size:

```text
about 302 MB
```

Suggested starting weight:

```text
0.35 to 0.55
```

Avoid starting unknown LoRAs at `0.75` unless the baseline is already stable.

### Bad LoRA Downloads Can Look Like Tiny Files

A failed Civitai download produced a file around `106B`. That is not a real LoRA.

Rule:

```text
Real LoRA files are usually tens or hundreds of MB.
Tiny files are usually HTML, JSON, auth errors, or redirects saved under a .safetensors name.
```

Check:

```bash
ls -lh /workspace/ComfyUI/models/loras
```

Remove invalid tiny files:

```bash
rm -f /workspace/ComfyUI/models/loras/bad_file.safetensors
```

### Civitai API Lessons

Civitai model page URLs are not always direct file downloads:

```text
https://civitai.com/models/...
```

The direct download URL often looks like:

```text
https://civitai.com/api/download/models/MODEL_VERSION_ID
```

Some Civitai downloads require an API token:

```bash
export CIVITAI_TOKEN=your_token_here
```

Important: never post the token in screenshots or chat. If a token was exposed, revoke it and create a new one.

Even when API metadata returns HTTP 200, a file download can still fail or save a tiny invalid response. Always verify file size afterward.

## PuLID / Extra Nodes Lesson

ComfyUI showed:

```text
ModuleNotFoundError: No module named 'facenet_pytorch'
Cannot import ComfyUI_PuLID_Flux_ll
```

This does not block the basic Flux generation workflow because PuLID is not wired into the active API workflow yet.

Fixing PuLID can be handled later by installing missing dependencies and then adding PuLID nodes into a richer exported ComfyUI API workflow.

## Browser / Port Lessons

RunPod useful ports:

```text
7860  Flux controller
8188  ComfyUI web UI / debug
8888  Jupyter Lab, if template exposes it
```

If port `8188` returns HTTP 403 through the RunPod proxy, use it mainly as optional debug. The controller only needs local access to `127.0.0.1:8188` from inside the Pod.

## Minimal Recovery Checklist

When things are confusing, use this order:

1. Check `/workspace` exists and contains the installed stack:

```bash
ls -lah /workspace
```

2. Check model files:

```bash
ls -lh /workspace/ComfyUI/models/unet
ls -lh /workspace/ComfyUI/models/clip
ls -lh /workspace/ComfyUI/models/vae
```

3. Start ComfyUI:

```bash
/workspace/start_comfyui.sh
```

4. In another terminal, start controller:

```bash
/workspace/start_flux_controller.sh
```

5. Open RunPod HTTP service on port `7860`.

6. In controller, press:

```text
Refresh model library
```

7. Test baseline first:

```text
LoRA: none
Seed: fixed
Randomize seed: off
Flux guidance: 3.0
Scheduler: beta
Steps: 32
```

8. Only after baseline works, add one LoRA at a low weight.

## Things Not To Redo

- Do not paste long scripts directly into the web terminal.
- Do not upload model binaries to GitHub Free.
- Do not repeatedly run full setup just to update `app.py`.
- Do not start ComfyUI multiple times on port `8188`.
- Do not trust `.safetensors` files until their size is verified.
- Do not expose API tokens in screenshots.
- Do not debug LoRA instability before confirming the no-LoRA baseline works.

