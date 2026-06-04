# RunPod Flux Unchained Pipeline

This folder contains a RunPod-oriented ComfyUI + Flux GGUF controller.

## Files

- `setup_runpod.sh` installs ComfyUI, custom nodes, baseline models, and the controller into `/workspace`.
- `app.py` is the Gradio micro-app that talks to ComfyUI through `/prompt`, WebSocket progress, `/history`, and `/view`.
- `comfyui_flux_unchained_api_workflow.json` is the API-format ComfyUI workflow template.
- `requirements.txt` contains only the controller dependencies.

## Quick Start On RunPod

Use a PyTorch CUDA template with an RTX 4090 pod and a persistent volume mounted at `/workspace`.

```bash
cd /workspace
git clone <your-repo-url> flux_bundle
cd flux_bundle/runpod_flux_pipeline
chmod +x setup_runpod.sh
./setup_runpod.sh
```

Start everything:

```bash
/workspace/start_flux_stack.sh
```

Expose these ports in RunPod:

- `7860` for the Flux controller
- `8188` for ComfyUI itself, optional but useful for debugging workflows

## Model Choices

The default model is:

```text
mhnakif/fluxunchained-dev -> fluxunchained-dev-Q6_K.gguf
```

For Q8, run setup like this:

```bash
MODEL_FILE=fluxunchained-dev-q8-0.gguf \
MODEL_URL='https://huggingface.co/mhnakif/fluxunchained-dev/resolve/main/fluxunchained-dev-q8-0.gguf?download=true' \
./setup_runpod.sh
```

If Hugging Face asks for authentication or license acceptance:

```bash
HF_TOKEN=hf_your_token ./setup_runpod.sh
```

## LoRA Use

Put LoRAs here:

```text
/workspace/ComfyUI/models/loras/
```

Then press `Refresh model library` in the controller. Each visible slot has its own weight slider from `0.0` to `1.2`; the default `0.75` is a conservative starting point.

Recommended starting weights:

```text
Realism / amateur photo / skin texture: 0.40-0.60
Body type / age / anatomy:             0.40-0.60
Pose / interaction / composition:      0.60-0.90
Strong style LoRA:                     0.30-0.70
```

For repeatable downloads, copy the example manifest and add direct LoRA download URLs:

```bash
cd /workspace/runpod-flux-pipeline
nano lora_manifest.tsv
chmod +x download_loras.sh
./download_loras.sh
```

The repository also contains `lora_manifest.tsv` generated from the current LoRA matrix spreadsheet. The downloader can resolve Civitai model page URLs through the Civitai API and can turn simple Hugging Face repo URLs into `/resolve/main/<filename>` download URLs.

For Civitai links that require login, create a Civitai API token and run:

```bash
export CIVITAI_TOKEN=your_token_here
./download_loras.sh
```

For gated Hugging Face links:

```bash
export HF_TOKEN=hf_your_token_here
./download_loras.sh
```

## ComfyUI API Workflow

The controller injects:

- raw positive prompt into `CLIPTextEncode`
- selected Flux GGUF into `UnetLoaderGGUF`
- CLIP-L and T5 into `DualCLIPLoader`
- LoRA chains through `LoraLoader`
- Flux guidance into `FluxGuidance`
- sampler parameters into `KSampler`
- optional `4x-UltraSharp.pth` through `UpscaleModelLoader` and `ImageUpscaleWithModel`

The template intentionally stays small so you can open the full ComfyUI UI on port `8188`, export an API-format workflow, and swap it in later if you want PuLID or segmentation wired directly into generation.
