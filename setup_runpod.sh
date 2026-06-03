#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
COMFY_DIR="${COMFYUI_DIR:-${WORKSPACE_DIR}/ComfyUI}"
CONTROLLER_DIR="${CONTROLLER_DIR:-${WORKSPACE_DIR}/flux_controller}"
VENV_DIR="${VENV_DIR:-${WORKSPACE_DIR}/venvs/flux-comfyui}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

MODEL_REPO="${MODEL_REPO:-mhnakif/fluxunchained-dev}"
MODEL_FILE="${MODEL_FILE:-fluxunchained-dev-Q6_K.gguf}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true}"
CLIP_L_URL="${CLIP_L_URL:-https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors?download=true}"
T5_URL="${T5_URL:-https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors?download=true}"
VAE_URL="${VAE_URL:-https://huggingface.co/MaxedOut/ComfyUI-Starter-Packs/resolve/main/Flux1/vae/ae.safetensors?download=true}"
UPSCALER_URL="${UPSCALER_URL:-https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth?download=true}"

INSTALL_INSTANTID="${INSTALL_INSTANTID:-1}"
INSTALL_PULID="${INSTALL_PULID:-1}"
INSTALL_APERSONMASK="${INSTALL_APERSONMASK:-1}"
INSTALL_IMPACT_PACK="${INSTALL_IMPACT_PACK:-1}"
DOWNLOAD_UPSCALER="${DOWNLOAD_UPSCALER:-1}"
UPDATE_REPOS="${UPDATE_REPOS:-0}"
INSTALL_TORCH_IF_MISSING="${INSTALL_TORCH_IF_MISSING:-1}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu121}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    log "Skipping root command because sudo is unavailable: $*"
    return 0
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

clone_or_update() {
  local repo_url="$1"
  local dest="$2"
  local name
  name="$(basename "$dest")"

  if [[ -d "${dest}/.git" ]]; then
    if [[ "${UPDATE_REPOS}" == "1" ]]; then
      log "Updating ${name}"
      git -C "$dest" pull --ff-only || log "Could not update ${name}; keeping existing checkout."
    else
      log "${name} already exists"
    fi
  else
    log "Cloning ${name}"
    git clone --depth 1 "$repo_url" "$dest"
  fi
}

download_if_missing() {
  local url="$1"
  local dest="$2"
  ensure_dir "$(dirname "$dest")"

  if [[ -s "$dest" ]]; then
    log "Already downloaded: ${dest}"
    return 0
  fi

  log "Downloading $(basename "$dest")"
  local headers=()
  if [[ -n "${HF_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${HF_TOKEN}")
  elif [[ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${HUGGING_FACE_HUB_TOKEN}")
  fi

  local tmp="${dest}.part"
  curl -L --fail --retry 8 --retry-delay 5 --continue-at - "${headers[@]}" "$url" -o "$tmp"
  mv "$tmp" "$dest"
}

install_requirements_file() {
  local req="$1"
  local label="$2"
  if [[ -f "$req" ]]; then
    log "Installing Python requirements for ${label}"
    python -m pip install --prefer-binary -r "$req" || log "Requirement install failed for ${label}; continue and inspect ComfyUI logs if that node is needed."
  fi
}

log "Preparing apt packages"
if command -v apt-get >/dev/null 2>&1; then
  run_as_root apt-get update
  run_as_root apt-get install -y \
    aria2 build-essential ca-certificates cmake curl ffmpeg git git-lfs \
    libgl1 libglib2.0-0 python3-dev python3-pip python3-venv unzip wget
  git lfs install || true
fi

log "Creating Python virtual environment at ${VENV_DIR}"
ensure_dir "$(dirname "$VENV_DIR")"
if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
source "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip setuptools wheel

if [[ "${INSTALL_TORCH_IF_MISSING}" == "1" ]]; then
  if ! python - <<'PY'
import torch
print(torch.__version__)
PY
  then
    log "Torch is missing; installing CUDA wheel set"
    python -m pip install --index-url "$TORCH_INDEX_URL" torch torchvision torchaudio
  fi
fi

log "Installing ComfyUI"
ensure_dir "$WORKSPACE_DIR"
clone_or_update "https://github.com/comfyanonymous/ComfyUI.git" "$COMFY_DIR"
install_requirements_file "${COMFY_DIR}/requirements.txt" "ComfyUI"

CUSTOM_NODES="${COMFY_DIR}/custom_nodes"
ensure_dir "$CUSTOM_NODES"
clone_or_update "https://github.com/city96/ComfyUI-GGUF.git" "${CUSTOM_NODES}/ComfyUI-GGUF"
clone_or_update "https://github.com/ltdrdata/ComfyUI-Manager.git" "${CUSTOM_NODES}/ComfyUI-Manager"

if [[ "${INSTALL_IMPACT_PACK}" == "1" ]]; then
  clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" "${CUSTOM_NODES}/ComfyUI-Impact-Pack"
fi

if [[ "${INSTALL_PULID}" == "1" ]]; then
  clone_or_update "https://github.com/lldacing/ComfyUI_PuLID_Flux_ll.git" "${CUSTOM_NODES}/ComfyUI_PuLID_Flux_ll"
fi

if [[ "${INSTALL_APERSONMASK}" == "1" ]]; then
  clone_or_update "https://github.com/djbielejeski/a-person-mask-generator.git" "${CUSTOM_NODES}/a-person-mask-generator"
fi

if [[ "${INSTALL_INSTANTID}" == "1" ]]; then
  clone_or_update "https://github.com/nosiu/comfyui-instantId-faceswap.git" "${CUSTOM_NODES}/comfyui-instantId-faceswap"
fi

install_requirements_file "${CUSTOM_NODES}/ComfyUI-GGUF/requirements.txt" "ComfyUI-GGUF"
install_requirements_file "${CUSTOM_NODES}/ComfyUI-Manager/requirements.txt" "ComfyUI-Manager"
install_requirements_file "${CUSTOM_NODES}/ComfyUI-Impact-Pack/requirements.txt" "ComfyUI-Impact-Pack"
install_requirements_file "${CUSTOM_NODES}/ComfyUI_PuLID_Flux_ll/requirements.txt" "PuLID Flux"
install_requirements_file "${CUSTOM_NODES}/a-person-mask-generator/requirements.txt" "a-person-mask-generator"
install_requirements_file "${CUSTOM_NODES}/comfyui-instantId-faceswap/requirements.txt" "InstantID faceswap"

log "Installing face-identity runtime dependencies"
python -m pip install --prefer-binary onnxruntime-gpu insightface || log "InsightFace install failed; PuLID/InstantID may need manual dependency repair."

log "Downloading baseline models"
download_if_missing "$MODEL_URL" "${COMFY_DIR}/models/unet/${MODEL_FILE}"
download_if_missing "$CLIP_L_URL" "${COMFY_DIR}/models/clip/clip_l.safetensors"
download_if_missing "$T5_URL" "${COMFY_DIR}/models/clip/t5xxl_fp8_e4m3fn.safetensors"
download_if_missing "$VAE_URL" "${COMFY_DIR}/models/vae/ae.safetensors"

if [[ "${DOWNLOAD_UPSCALER}" == "1" ]]; then
  download_if_missing "$UPSCALER_URL" "${COMFY_DIR}/models/upscale_models/4x-UltraSharp.pth"
fi

log "Installing controller"
ensure_dir "$CONTROLLER_DIR"
cp "${SCRIPT_DIR}/app.py" "$CONTROLLER_DIR/app.py"
cp "${SCRIPT_DIR}/requirements.txt" "$CONTROLLER_DIR/requirements.txt"
cp "${SCRIPT_DIR}/comfyui_flux_unchained_api_workflow.json" "$CONTROLLER_DIR/comfyui_flux_unchained_api_workflow.json"
python -m pip install -r "$CONTROLLER_DIR/requirements.txt"

log "Creating launcher scripts"
cat > "${WORKSPACE_DIR}/start_comfyui.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source "${VENV_DIR}/bin/activate"
cd "${COMFY_DIR}"
exec python main.py --listen 0.0.0.0 --port 8188
EOF
chmod +x "${WORKSPACE_DIR}/start_comfyui.sh"

cat > "${WORKSPACE_DIR}/start_flux_controller.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source "${VENV_DIR}/bin/activate"
export COMFYUI_DIR="${COMFY_DIR}"
export COMFYUI_BASE_URL="\${COMFYUI_BASE_URL:-http://127.0.0.1:8188}"
export CONTROLLER_PORT="\${CONTROLLER_PORT:-7860}"
cd "${CONTROLLER_DIR}"
exec python app.py
EOF
chmod +x "${WORKSPACE_DIR}/start_flux_controller.sh"

cat > "${WORKSPACE_DIR}/start_flux_stack.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
"${WORKSPACE_DIR}/start_comfyui.sh" > "${WORKSPACE_DIR}/comfyui.log" 2>&1 &
COMFY_PID=\$!
echo "ComfyUI PID: \${COMFY_PID}"
sleep 8
"${WORKSPACE_DIR}/start_flux_controller.sh"
EOF
chmod +x "${WORKSPACE_DIR}/start_flux_stack.sh"

log "Done"
cat <<EOF

Run commands:
  ${WORKSPACE_DIR}/start_flux_stack.sh

Ports to expose in RunPod:
  7860  Flux controller
  8188  ComfyUI, optional

Model override examples:
  MODEL_FILE=fluxunchained-dev-q8-0.gguf MODEL_URL=https://huggingface.co/mhnakif/fluxunchained-dev/resolve/main/fluxunchained-dev-q8-0.gguf?download=true ./setup_runpod.sh
  HF_TOKEN=hf_xxx ./setup_runpod.sh
EOF
