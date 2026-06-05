#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing config.sh. Run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

mkdir -p "$LOG_DIR" "$DOWNLOAD_STAGING" "$ARCHIVE_DIR"
LOG_FILE="$LOG_DIR/download_loras_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

command -v rclone >/dev/null || { echo "[ERROR] Missing rclone"; exit 1; }
command -v python3 >/dev/null || { echo "[ERROR] Missing python3"; exit 1; }

echo "[INFO] Testing rclone remote"
rclone lsd "${RCLONE_REMOTE}:" >/dev/null
rclone mkdir "${RCLONE_REMOTE}:${DRIVE_LORA_DIR}"

if [[ -z "${CIVITAI_TOKEN:-}" ]]; then
  echo "[WARN] CIVITAI_TOKEN is not set. Gated Civitai downloads may fail."
  echo "[WARN] Set it with: export CIVITAI_TOKEN='your_token_here'"
fi

if [[ -z "${HF_TOKEN:-}" && -z "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
  echo "[WARN] HF_TOKEN is not set. Gated Hugging Face downloads may fail."
  echo "[WARN] Set it with: export HF_TOKEN='hf_your_token_here'"
fi

export RCLONE_REMOTE DRIVE_LORA_DIR DOWNLOAD_STAGING ARCHIVE_DIR LORA_ARCHIVE_NAME LOG_DIR
export LORAS_CSV="${SCRIPT_DIR}/loras.csv"

python3 "$SCRIPT_DIR/download_loras_to_gdrive.py"

echo "[INFO] Remote LoRA directory"
rclone ls "${RCLONE_REMOTE}:${DRIVE_LORA_DIR}/"

echo "[INFO] Done"

