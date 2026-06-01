from __future__ import annotations

import copy
import json
import os
import random
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import gradio as gr
import requests
import websocket


APP_DIR = Path(__file__).resolve().parent
COMFYUI_DIR = Path(os.getenv("COMFYUI_DIR", "/workspace/ComfyUI"))
COMFYUI_BASE_URL = os.getenv("COMFYUI_BASE_URL", "http://127.0.0.1:8188").rstrip("/")
WORKFLOW_TEMPLATE = Path(
    os.getenv("WORKFLOW_TEMPLATE", APP_DIR / "comfyui_flux_unchained_api_workflow.json")
)
DOWNLOAD_DIR = Path(os.getenv("CONTROLLER_OUTPUT_DIR", "/workspace/flux_controller_outputs"))
MAX_LORA_SLOTS = int(os.getenv("MAX_LORA_SLOTS", "6"))

NONE = "(none)"
DEFAULT_PREFIX = "flux_unchained"


def model_dir(name: str) -> Path:
    return COMFYUI_DIR / "models" / name


def relative_model_names(folder: Path, suffixes: tuple[str, ...]) -> list[str]:
    if not folder.exists():
        return []
    names: list[str] = []
    for path in folder.rglob("*"):
        if path.is_file() and path.suffix.lower() in suffixes:
            names.append(path.relative_to(folder).as_posix())
    return sorted(names, key=str.lower)


def scan_assets() -> dict[str, list[str]]:
    return {
        "unets": relative_model_names(model_dir("unet"), (".gguf", ".safetensors", ".sft")),
        "clips": relative_model_names(model_dir("clip"), (".safetensors", ".sft", ".gguf")),
        "vae": relative_model_names(model_dir("vae"), (".safetensors", ".sft")),
        "loras": [NONE] + relative_model_names(model_dir("loras"), (".safetensors", ".sft", ".pt")),
        "upscalers": [NONE] + relative_model_names(model_dir("upscale_models"), (".pth", ".safetensors", ".pt")),
    }


def first_or(items: list[str], fallback: str) -> str:
    return items[0] if items else fallback


def load_template() -> dict[str, Any]:
    with WORKFLOW_TEMPLATE.open("r", encoding="utf-8") as f:
        return json.load(f)


def selected_loras(*slot_values: Any) -> list[tuple[str, float]]:
    pairs: list[tuple[str, float]] = []
    for idx in range(0, len(slot_values), 2):
        name = str(slot_values[idx] or NONE)
        weight = float(slot_values[idx + 1] or 0.0)
        if name != NONE and weight > 0:
            pairs.append((name, weight))
    return pairs


def build_workflow(
    prompt: str,
    unet_name: str,
    clip_l_name: str,
    t5_name: str,
    vae_name: str,
    loras: list[tuple[str, float]],
    sampler: str,
    scheduler: str,
    steps: int,
    guidance: float,
    width: int,
    height: int,
    seed: int,
    upscale_model: str,
    filename_prefix: str,
) -> dict[str, Any]:
    workflow = copy.deepcopy(load_template())

    workflow["10"]["inputs"]["unet_name"] = unet_name
    workflow["11"]["inputs"]["clip_name1"] = clip_l_name
    workflow["11"]["inputs"]["clip_name2"] = t5_name
    workflow["11"]["inputs"]["type"] = "flux"
    workflow["12"]["inputs"]["vae_name"] = vae_name

    workflow["30"]["inputs"]["width"] = int(width)
    workflow["30"]["inputs"]["height"] = int(height)
    workflow["40"]["inputs"]["text"] = prompt
    workflow["41"]["inputs"]["guidance"] = float(guidance)
    workflow["50"]["inputs"]["width"] = int(width)
    workflow["50"]["inputs"]["height"] = int(height)

    workflow["60"]["inputs"]["seed"] = int(seed)
    workflow["60"]["inputs"]["steps"] = int(steps)
    workflow["60"]["inputs"]["cfg"] = 1.0
    workflow["60"]["inputs"]["sampler_name"] = sampler
    workflow["60"]["inputs"]["scheduler"] = scheduler
    workflow["80"]["inputs"]["filename_prefix"] = filename_prefix or DEFAULT_PREFIX

    model_source: list[Any] = ["10", 0]
    clip_source: list[Any] = ["11", 0]
    for idx, (lora_name, weight) in enumerate(loras, start=1):
        node_id = str(100 + idx)
        workflow[node_id] = {
            "class_type": "LoraLoader",
            "inputs": {
                "model": model_source,
                "clip": clip_source,
                "lora_name": lora_name,
                "strength_model": float(weight),
                "strength_clip": float(weight),
            },
        }
        model_source = [node_id, 0]
        clip_source = [node_id, 1]

    workflow["30"]["inputs"]["model"] = model_source
    workflow["40"]["inputs"]["clip"] = clip_source
    workflow["42"]["inputs"]["clip"] = clip_source

    if upscale_model and upscale_model != NONE:
        workflow["90"] = {
            "class_type": "UpscaleModelLoader",
            "inputs": {"model_name": upscale_model},
        }
        workflow["91"] = {
            "class_type": "ImageUpscaleWithModel",
            "inputs": {
                "upscale_model": ["90", 0],
                "image": ["70", 0],
            },
        }
        workflow["80"]["inputs"]["images"] = ["91", 0]
    else:
        workflow["80"]["inputs"]["images"] = ["70", 0]

    return workflow


def api_url(path: str) -> str:
    return f"{COMFYUI_BASE_URL}{path}"


def ws_url(client_id: str) -> str:
    base = COMFYUI_BASE_URL.replace("https://", "wss://").replace("http://", "ws://")
    return f"{base}/ws?{urlencode({'clientId': client_id})}"


def queue_prompt(workflow: dict[str, Any], client_id: str) -> str:
    response = requests.post(
        api_url("/prompt"),
        json={"prompt": workflow, "client_id": client_id},
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    if "prompt_id" not in payload:
        raise RuntimeError(f"Unexpected /prompt response: {payload}")
    return str(payload["prompt_id"])


def wait_for_prompt(prompt_id: str, client_id: str):
    socket = websocket.WebSocket()
    socket.settimeout(2)
    socket.connect(ws_url(client_id))
    try:
        while True:
            try:
                raw_message = socket.recv()
            except websocket.WebSocketTimeoutException:
                yield "Waiting for ComfyUI..."
                continue

            if not isinstance(raw_message, str):
                continue

            message = json.loads(raw_message)
            msg_type = message.get("type")
            data = message.get("data", {})

            if data.get("prompt_id") not in (None, prompt_id):
                continue

            if msg_type == "progress":
                value = data.get("value")
                maximum = data.get("max")
                yield f"Sampling {value}/{maximum}"
            elif msg_type == "executing":
                node = data.get("node")
                if node is None:
                    yield "Finalizing output..."
                    return
                yield f"Executing node {node}"
            elif msg_type == "execution_error":
                raise RuntimeError(json.dumps(data, indent=2))
    finally:
        socket.close()


def fetch_history(prompt_id: str) -> dict[str, Any]:
    for _ in range(180):
        response = requests.get(api_url(f"/history/{prompt_id}"), timeout=30)
        response.raise_for_status()
        history = response.json()
        if prompt_id in history:
            return history[prompt_id]
        time.sleep(1)
    raise TimeoutError("Timed out waiting for ComfyUI history.")


def download_saved_image(history: dict[str, Any]) -> Path:
    outputs = history.get("outputs", {})
    images = outputs.get("80", {}).get("images", [])
    if not images:
        for node_output in outputs.values():
            images = node_output.get("images", [])
            if images:
                break
    if not images:
        raise RuntimeError("ComfyUI finished, but no image output was found in /history.")

    image = images[0]
    params = {
        "filename": image["filename"],
        "subfolder": image.get("subfolder", ""),
        "type": image.get("type", "output"),
    }
    response = requests.get(api_url(f"/view?{urlencode(params)}"), stream=True, timeout=120)
    response.raise_for_status()

    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    destination = DOWNLOAD_DIR / image["filename"]
    with destination.open("wb") as f:
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            if chunk:
                f.write(chunk)
    return destination


def generate(
    prompt: str,
    unet_name: str,
    clip_l_name: str,
    t5_name: str,
    vae_name: str,
    sampler: str,
    scheduler: str,
    steps: int,
    guidance: float,
    width: int,
    height: int,
    seed: int,
    randomize_seed: bool,
    upscale_model: str,
    filename_prefix: str,
    *slot_values: Any,
):
    try:
        if not prompt.strip():
            yield "Prompt is empty.", None, None
            return

        actual_seed = random.randint(1, 2**63 - 1) if randomize_seed or seed < 0 else int(seed)
        loras = selected_loras(*slot_values)
        workflow = build_workflow(
            prompt=prompt,
            unet_name=unet_name,
            clip_l_name=clip_l_name,
            t5_name=t5_name,
            vae_name=vae_name,
            loras=loras,
            sampler=sampler,
            scheduler=scheduler,
            steps=steps,
            guidance=guidance,
            width=width,
            height=height,
            seed=actual_seed,
            upscale_model=upscale_model,
            filename_prefix=filename_prefix or DEFAULT_PREFIX,
        )

        client_id = str(uuid.uuid4())
        prompt_id = queue_prompt(workflow, client_id)
        yield f"Queued {prompt_id} with seed {actual_seed}.", None, None

        for status in wait_for_prompt(prompt_id, client_id):
            yield status, None, None

        history = fetch_history(prompt_id)
        image_path = download_saved_image(history)
        yield f"Done. Seed: {actual_seed}.", str(image_path), str(image_path)
    except Exception as exc:
        yield f"Error: {exc}", None, None


def refresh_choices():
    assets = scan_assets()
    dropdown_updates = [
        gr.update(choices=assets["unets"], value=first_or(assets["unets"], "")),
        gr.update(choices=assets["clips"], value="clip_l.safetensors" if "clip_l.safetensors" in assets["clips"] else first_or(assets["clips"], "")),
        gr.update(choices=assets["clips"], value="t5xxl_fp8_e4m3fn.safetensors" if "t5xxl_fp8_e4m3fn.safetensors" in assets["clips"] else first_or(assets["clips"], "")),
        gr.update(choices=assets["vae"], value="ae.safetensors" if "ae.safetensors" in assets["vae"] else first_or(assets["vae"], "")),
        gr.update(choices=assets["upscalers"], value=NONE),
    ]
    for _ in range(MAX_LORA_SLOTS):
        dropdown_updates.append(gr.update(choices=assets["loras"], value=NONE))
    return dropdown_updates


def build_ui() -> gr.Blocks:
    assets = scan_assets()
    default_clip_l = "clip_l.safetensors" if "clip_l.safetensors" in assets["clips"] else first_or(assets["clips"], "")
    default_t5 = "t5xxl_fp8_e4m3fn.safetensors" if "t5xxl_fp8_e4m3fn.safetensors" in assets["clips"] else first_or(assets["clips"], "")
    default_vae = "ae.safetensors" if "ae.safetensors" in assets["vae"] else first_or(assets["vae"], "")
    default_unet = "fluxunchained-dev-Q6_K.gguf" if "fluxunchained-dev-Q6_K.gguf" in assets["unets"] else first_or(assets["unets"], "")

    with gr.Blocks(title="Flux Unchained Controller") as demo:
        gr.Markdown("# Flux Unchained Controller")

        with gr.Row():
            with gr.Column(scale=2):
                prompt = gr.Textbox(
                    label="Positive prompt",
                    lines=10,
                    placeholder="Write the full Flux prompt here.",
                )
                with gr.Row():
                    width = gr.Slider(512, 1536, value=1024, step=64, label="Width")
                    height = gr.Slider(512, 1536, value=1024, step=64, label="Height")
                with gr.Row():
                    steps = gr.Slider(20, 40, value=28, step=1, label="Steps")
                    guidance = gr.Slider(3.0, 4.0, value=3.5, step=0.05, label="Flux guidance")
                with gr.Row():
                    sampler = gr.Dropdown(["euler"], value="euler", label="Sampler")
                    scheduler = gr.Dropdown(["simple", "beta"], value="simple", label="Scheduler")
                with gr.Row():
                    seed = gr.Number(value=-1, precision=0, label="Seed")
                    randomize_seed = gr.Checkbox(value=True, label="Randomize seed")
                filename_prefix = gr.Textbox(value=DEFAULT_PREFIX, label="Filename prefix")

            with gr.Column(scale=1):
                refresh = gr.Button("Refresh model library")
                unet_name = gr.Dropdown(assets["unets"], value=default_unet, label="Flux GGUF / UNet")
                clip_l_name = gr.Dropdown(assets["clips"], value=default_clip_l, label="CLIP-L")
                t5_name = gr.Dropdown(assets["clips"], value=default_t5, label="T5-XXL")
                vae_name = gr.Dropdown(assets["vae"], value=default_vae, label="VAE")
                upscale_model = gr.Dropdown(assets["upscalers"], value=NONE, label="Upscale model")

        lora_inputs: list[Any] = []
        with gr.Accordion("LoRA slots", open=True):
            for idx in range(MAX_LORA_SLOTS):
                with gr.Row():
                    lora = gr.Dropdown(assets["loras"], value=NONE, label=f"LoRA {idx + 1}")
                    weight = gr.Slider(0.0, 1.2, value=0.75, step=0.05, label=f"Weight {idx + 1}")
                    lora_inputs.extend([lora, weight])

        generate_button = gr.Button("Generate", variant="primary")
        status = gr.Textbox(label="Status", interactive=False)
        output_image = gr.Image(label="Output PNG", type="filepath")
        output_file = gr.File(label="Download lossless PNG")

        refresh_outputs = [unet_name, clip_l_name, t5_name, vae_name, upscale_model]
        refresh_outputs.extend(lora_inputs[0::2])
        refresh.click(refresh_choices, outputs=refresh_outputs)

        generate_button.click(
            generate,
            inputs=[
                prompt,
                unet_name,
                clip_l_name,
                t5_name,
                vae_name,
                sampler,
                scheduler,
                steps,
                guidance,
                width,
                height,
                seed,
                randomize_seed,
                upscale_model,
                filename_prefix,
                *lora_inputs,
            ],
            outputs=[status, output_image, output_file],
        )

    return demo


if __name__ == "__main__":
    port = int(os.getenv("CONTROLLER_PORT", "7860"))
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    build_ui().queue().launch(
        server_name="0.0.0.0",
        server_port=port,
        allowed_paths=[str(DOWNLOAD_DIR)],
    )
