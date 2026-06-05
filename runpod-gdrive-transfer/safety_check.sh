#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing config.sh. Run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/safety_check_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "== Disk =="
df -h

echo
echo "== Local sizes =="
du -sh "$COMFYUI_DIR" 2>/dev/null || true
du -sh "$COMFYUI_DIR/models" 2>/dev/null || true
du -sh "$LORA_TARGET_DIR" 2>/dev/null || true

echo
echo "== rclone about =="
rclone about "${RCLONE_REMOTE}:" || true

echo
echo "== Google Drive directories =="
rclone lsd "${RCLONE_REMOTE}:${GDRIVE_BASE}" || true

echo
echo "== Project archive =="
rclone lsf "${RCLONE_REMOTE}:${DRIVE_PROJECT_DIR}/" || true

echo
echo "== LoRA archive =="
rclone lsf "${RCLONE_REMOTE}:${DRIVE_LORA_DIR}/" || true

