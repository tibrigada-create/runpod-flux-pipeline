# RunPod Flux Workflow State

Last updated: 2026-06-02

This document describes the currently working RunPod + ComfyUI + Flux Unchained setup.

## Runtime Overview

The image generation stack runs remotely on a RunPod GPU pod. The local Windows machine is only used as a control station through the browser.

Remote persistent workspace:

```text
/workspace
```

Main installed components:

```text
/workspace/ComfyUI
/workspace/flux_controller
/workspace/venvs/flux-comfyui
/workspace/flux_controller_outputs
```

Main start command:

```bash
/workspace/start_flux_stack.sh
```

This command starts:

```text
ComfyUI backend:     http://127.0.0.1:8188
Gradio controller:   http://0.0.0.0:7860
```

RunPod HTTP services:

```text
7860  Flux Unchained Controller
8188  ComfyUI, optional/debug
8888  Jupyter Lab from the RunPod template, if enabled
```

## Current Working Flow

The user opens the Gradio controller on RunPod port `7860`.

The controller:

1. Scans ComfyUI model folders.
2. Lets the user choose Flux GGUF, CLIP-L, T5-XXL, VAE, optional upscaler, and optional LoRAs.
3. Builds a ComfyUI API JSON workflow dynamically.
4. Sends the workflow to ComfyUI through:

```text
POST http://127.0.0.1:8188/prompt
```

5. Tracks progress through the ComfyUI WebSocket:

```text
ws://127.0.0.1:8188/ws
```

6. Reads finished outputs through:

```text
GET http://127.0.0.1:8188/history/{prompt_id}
GET http://127.0.0.1:8188/view?... 
```

7. Downloads the generated PNG into:

```text
/workspace/flux_controller_outputs
```

8. Displays the PNG in Gradio and exposes it through the download control.

The Gradio launch has been patched with:

```python
allowed_paths=[str(DOWNLOAD_DIR)]
```

This is required because Gradio refuses to serve files outside its working directory unless the path is explicitly allowed.

## ComfyUI Installation

ComfyUI is installed at:

```text
/workspace/ComfyUI
```

The Python virtual environment is:

```text
/workspace/venvs/flux-comfyui
```

The backend launcher is:

```bash
/workspace/start_comfyui.sh
```

It runs:

```bash
python main.py --listen 0.0.0.0 --port 8188
```

ComfyUI logs are written by the stack launcher to:

```text
/workspace/comfyui.log
```

## Installed Custom Nodes

The setup script installs these custom nodes:

```text
/workspace/ComfyUI/custom_nodes/ComfyUI-GGUF
/workspace/ComfyUI/custom_nodes/ComfyUI-Manager
/workspace/ComfyUI/custom_nodes/ComfyUI-Impact-Pack
/workspace/ComfyUI/custom_nodes/ComfyUI_PuLID_Flux_ll
/workspace/ComfyUI/custom_nodes/a-person-mask-generator
/workspace/ComfyUI/custom_nodes/comfyui-instantId-faceswap
```

Currently used by the basic working workflow:

```text
ComfyUI-GGUF
```

Installed but not yet wired into the active API workflow:

```text
ComfyUI-Impact-Pack / FaceDetailer
PuLID Flux
a-person-mask-generator
InstantID faceswap
```

These can be integrated later by exporting a richer ComfyUI API workflow and adapting the controller template.

## Current Model Files

Primary Flux model:

```text
/workspace/ComfyUI/models/unet/fluxunchained-dev-Q6_K.gguf
```

Source:

```text
https://huggingface.co/mhnakif/fluxunchained-dev/resolve/main/fluxunchained-dev-Q6_K.gguf?download=true
```

Text encoders:

```text
/workspace/ComfyUI/models/clip/clip_l.safetensors
/workspace/ComfyUI/models/clip/t5xxl_fp8_e4m3fn.safetensors
```

Sources:

```text
https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true
https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors?download=true
```

Flux VAE / AE:

```text
/workspace/ComfyUI/models/vae/ae.safetensors
```

Current working source:

```text
https://huggingface.co/MaxedOut/ComfyUI-Starter-Packs/resolve/main/Flux1/vae/ae.safetensors?download=true
```

Important note:

The original `black-forest-labs/FLUX.1-schnell` VAE URL returned `401 Unauthorized` without Hugging Face access. A wrong VAE caused this ComfyUI runtime error:

```text
expected input ... to have 4 channels, but got 16 channels
```

That error means an SD/SDXL-style 4-channel VAE was loaded instead of the Flux 16-channel AE. The current `ae.safetensors` is the working Flux AE and is about `319M` as shown on the RunPod filesystem.

Optional upscaler:

```text
/workspace/ComfyUI/models/upscale_models/4x-UltraSharp.pth
```

Source:

```text
https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth?download=true
```

LoRA directory:

```text
/workspace/ComfyUI/models/loras
```

The controller scans this folder and exposes up to six LoRA slots. Each selected LoRA is injected with a per-slot weight slider.

## Active API Workflow

The controller uses:

```text
/workspace/flux_controller/comfyui_flux_unchained_api_workflow.json
```

Source file in this repository:

```text
runpod_flux_pipeline/comfyui_flux_unchained_api_workflow.json
```

Node summary:

```text
10  UnetLoaderGGUF       Loads fluxunchained-dev-Q6_K.gguf
11  DualCLIPLoader       Loads clip_l + t5xxl_fp8, type=flux
12  VAELoader            Loads ae.safetensors
30  ModelSamplingFlux    Applies Flux sampling shift settings
40  CLIPTextEncode       Positive prompt
41  FluxGuidance         Flux guidance value
42  CLIPTextEncode       Empty negative prompt
50  EmptyLatentImage     Width, height, batch size
60  KSampler             Euler/simple, steps, seed, CFG 1.0
70  VAEDecode            Decodes Flux latent through AE/VAE
80  SaveImage            Writes PNG output
```

Dynamic LoRA injection:

The base template does not hard-code LoRAs. The Gradio controller dynamically inserts `LoraLoader` nodes starting at node IDs `101`, `102`, etc. The final model and CLIP outputs are rewired into `ModelSamplingFlux` and `CLIPTextEncode`.

Optional upscaling:

If an upscaler is selected, the controller inserts:

```text
90  UpscaleModelLoader
91  ImageUpscaleWithModel
```

and rewires `SaveImage` to save the upscaled image instead of the raw VAE decode.

## Current Generation Defaults

Controller defaults:

```text
Width:          1024
Height:         1024
Steps:          28
CFG:            1.0, fixed in workflow
Sampler:        euler
Scheduler:      beta
Flux guidance:  2.6
Seed:           randomized by default
Filename:       flux_unchained
LoRA slots:     six slots, default none
LoRA weight:    0.75 default per slot, range 0.0 to 1.2
```

## Realism Tuning Notes

The controller defaults were adjusted to reduce overly smooth or plastic-looking output:

```text
Flux guidance: 2.6, adjustable from 2.0 to 3.2
Scheduler:     beta by default
Alternatives:  sgm_uniform or simple
CFG:           remains fixed at 1.0
```

Recommended tuning pattern:

```text
Use 2.2-2.8 guidance for skin texture and photographic roughness.
Use beta first, then compare against sgm_uniform.
Keep CFG at 1.0 for Flux.
Use Q6_K as the minimum practical GGUF quality target on 24GB VRAM.
Try Q8_0 only when VRAM and speed budget allow it.
```

LoRA usage is intentionally handled through the six controller slots rather than hard-coded into the workflow. For realism, prefer one texture/photo LoRA at moderate weight before stacking many adapters:

```text
Realism / amateur photo / skin texture LoRA: 0.4-0.6
Body type / age / anatomy LoRA:             around 0.5
Pose or interaction LoRA:                   0.6-0.9, test carefully
```

Impact Pack is now installed by setup so FaceDetailer can be added in ComfyUI later. It is not automatically inserted into the current API workflow because FaceDetailer requires detector models and a tuned inpaint/detailer subgraph. The stable path is:

```text
1. Open ComfyUI on port 8188.
2. Build and test FaceDetailer interactively after the current SaveImage path.
3. Export the tested workflow in API format.
4. Replace or extend comfyui_flux_unchained_api_workflow.json.
```

Tested successful prompt category:

```text
Apple / natural photo-style prompt
```

Observed successful result:

```text
Done. Seed: 4782878679310385259.
```

## Operational Notes

Start stack:

```bash
/workspace/start_flux_stack.sh
```

Stop current foreground stack:

```text
Ctrl+C
```

Kill leftover ComfyUI/controller processes if needed:

```bash
pkill -f "python main.py" || true
pkill -f "/workspace/flux_controller/app.py" || true
```

Restart stack:

```bash
/workspace/start_flux_stack.sh
```

After finishing a test session, stop the RunPod pod from the RunPod UI to avoid GPU billing.

## Repository Sync Notes

The working transfer method is GitHub:

```bash
cd /workspace
git clone https://github.com/tibrigada-create/runpod-flux-pipeline.git
cd runpod-flux-pipeline
chmod +x setup_runpod.sh
./setup_runpod.sh
```

If the local repository changes, upload/commit the changed files to GitHub, then on RunPod use `git pull` inside:

```text
/workspace/runpod-flux-pipeline
```

The local `setup_runpod.sh` has been updated to use the working public Flux AE mirror by default.
