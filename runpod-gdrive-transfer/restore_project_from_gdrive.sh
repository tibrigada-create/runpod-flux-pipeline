#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing config.sh. Run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

mkdir -p "$LOG_DIR" "$ARCHIVE_DIR"
LOG_FILE="$LOG_DIR/restore_project_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

REMOTE_PROJECT="${RCLONE_REMOTE}:${DRIVE_PROJECT_DIR}"
ARCHIVE_PATH="${ARCHIVE_DIR}/${PROJECT_ARCHIVE_NAME}"

echo "[INFO] Restoring project from Google Drive"

command -v rclone >/dev/null || { echo "[ERROR] Missing rclone"; exit 1; }
command -v tar >/dev/null || { echo "[ERROR] Missing tar"; exit 1; }

rclone lsf "$REMOTE_PROJECT/" | grep -Fx "$PROJECT_ARCHIVE_NAME" >/dev/null || {
  echo "[ERROR] Archive not found on Google Drive: $REMOTE_PROJECT/$PROJECT_ARCHIVE_NAME"
  exit 1
}

mkdir -p "$ARCHIVE_DIR"
echo "[INFO] Downloading archive"
rclone copy "$REMOTE_PROJECT/$PROJECT_ARCHIVE_NAME" "$ARCHIVE_DIR/" --progress
rclone copy "$REMOTE_PROJECT/${PROJECT_ARCHIVE_NAME}.sha256" "$ARCHIVE_DIR/" --progress || true

if [[ -f "${ARCHIVE_PATH}.sha256" ]]; then
  echo "[INFO] Verifying sha256"
  (cd "$ARCHIVE_DIR" && sha256sum -c "${PROJECT_ARCHIVE_NAME}.sha256")
fi

ARCHIVE_BYTES="$(stat -c%s "$ARCHIVE_PATH")"
FREE_BYTES="$(df -PB1 "$LOCAL_WORKSPACE" | awk 'NR==2 {print $4}')"
echo "[INFO] Archive bytes: $ARCHIVE_BYTES"
echo "[INFO] Free bytes at workspace: $FREE_BYTES"
if (( FREE_BYTES < ARCHIVE_BYTES )); then
  echo "[WARN] Free space is smaller than archive size. Restore may fail."
fi

echo "[INFO] Listing first archive entries"
tar -tf "$ARCHIVE_PATH" | head -n 50

if [[ -d "$COMFYUI_DIR" && "${RESTORE_OVERWRITE:-no}" != "yes" ]]; then
  echo "[WARN] Target already exists: $COMFYUI_DIR"
  read -r -p "Continue and allow tar to overwrite existing files? Type YES: " answer
  if [[ "$answer" != "YES" ]]; then
    echo "[INFO] Restore cancelled by user."
    exit 0
  fi
fi

echo "[INFO] Extracting archive to /"
tar -xf "$ARCHIVE_PATH" -C /

if [[ ! -d "$COMFYUI_DIR" ]]; then
  echo "[ERROR] Restore finished but COMFYUI_DIR does not exist: $COMFYUI_DIR"
  exit 1
fi

echo "[INFO] Restore complete"
echo "Next steps may be:"
echo "  cd /workspace/ComfyUI"
echo "  /workspace/start_comfyui.sh"

