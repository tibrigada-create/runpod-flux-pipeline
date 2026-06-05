#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing config.sh. Run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

mkdir -p "$LOG_DIR" "$ARCHIVE_DIR" "$LORA_TARGET_DIR"
LOG_FILE="$LOG_DIR/restore_loras_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

REMOTE_LORA="${RCLONE_REMOTE}:${DRIVE_LORA_DIR}"
ARCHIVE_PATH="${ARCHIVE_DIR}/${LORA_ARCHIVE_NAME}"

command -v rclone >/dev/null || { echo "[ERROR] Missing rclone"; exit 1; }
command -v tar >/dev/null || { echo "[ERROR] Missing tar"; exit 1; }

rclone lsf "$REMOTE_LORA/" | grep -Fx "$LORA_ARCHIVE_NAME" >/dev/null || {
  echo "[ERROR] LoRA archive not found on Google Drive: $REMOTE_LORA/$LORA_ARCHIVE_NAME"
  exit 1
}

echo "[INFO] Downloading LoRA archive"
rclone copy "$REMOTE_LORA/$LORA_ARCHIVE_NAME" "$ARCHIVE_DIR/" --progress
rclone copy "$REMOTE_LORA/sha256sum.txt" "$ARCHIVE_DIR/" --progress || true

echo "[INFO] Archive contents preview"
tar -tf "$ARCHIVE_PATH" | head -n 50

if [[ "${RESTORE_OVERWRITE:-no}" != "yes" ]]; then
  existing_count=0
  while IFS= read -r item; do
    if [[ -e "$LORA_TARGET_DIR/$item" ]]; then
      existing_count=$((existing_count + 1))
    fi
  done < <(tar -tf "$ARCHIVE_PATH")

  if (( existing_count > 0 )); then
    echo "[WARN] $existing_count LoRA files already exist in $LORA_TARGET_DIR"
    read -r -p "Continue and allow overwrite? Type YES: " answer
    if [[ "$answer" != "YES" ]]; then
      echo "[INFO] Restore cancelled by user."
      exit 0
    fi
  fi
fi

before="$(mktemp)"
after="$(mktemp)"
find "$LORA_TARGET_DIR" -maxdepth 1 -type f -printf '%f\n' | sort > "$before"

echo "[INFO] Extracting LoRAs"
tar -xf "$ARCHIVE_PATH" -C "$LORA_TARGET_DIR"

find "$LORA_TARGET_DIR" -maxdepth 1 -type f -printf '%f\n' | sort > "$after"

echo "[INFO] Newly added files:"
comm -13 "$before" "$after" || true

rm -f "$before" "$after"

echo "[INFO] Done. In ComfyUI/controller, refresh the model library or restart ComfyUI if needed."

