#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Missing config.sh. Run: cp config.example.sh config.sh"
  exit 1
fi
source "$CONFIG_FILE"

mkdir -p "$LOG_DIR" "$BACKUP_STAGING" "$ARCHIVE_DIR"
LOG_FILE="$LOG_DIR/export_project_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

REMOTE_PROJECT="${RCLONE_REMOTE}:${DRIVE_PROJECT_DIR}"
ARCHIVE_PATH="${ARCHIVE_DIR}/${PROJECT_ARCHIVE_NAME}"
MANIFEST_PATH="${BACKUP_STAGING}/manifest_project.txt"
SHA_PATH="${BACKUP_STAGING}/manifest_project.sha256"
USAGE_PATH="${BACKUP_STAGING}/disk_usage_project.txt"

echo "[INFO] Exporting RunPod project to Google Drive"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing command: $1"; exit 1; }
}

require_cmd rclone
require_cmd tar
require_cmd sha256sum
require_cmd du
require_cmd df

if [[ ! -d "$COMFYUI_DIR" ]]; then
  echo "[ERROR] COMFYUI_DIR does not exist: $COMFYUI_DIR"
  exit 1
fi

echo "[INFO] Testing rclone remote"
rclone lsd "${RCLONE_REMOTE}:" >/dev/null
rclone mkdir "$REMOTE_PROJECT"

echo "[INFO] Measuring selected data"
du -sh "$COMFYUI_DIR" || true
du -sh "$COMFYUI_DIR/models" || true
df -h "$ARCHIVE_DIR"

EST_BYTES="$(du -sb "$COMFYUI_DIR" | awk '{print $1}')"
FREE_BYTES="$(df -PB1 "$ARCHIVE_DIR" | awk 'NR==2 {print $4}')"

echo "[INFO] Estimated source bytes: $EST_BYTES"
echo "[INFO] Free bytes at archive destination: $FREE_BYTES"

if (( FREE_BYTES < EST_BYTES )); then
  echo "[ERROR] Not enough free disk space to create an uncompressed tar archive."
  echo "[ERROR] Free space must be roughly at least the selected backup size."
  exit 1
fi

echo "[INFO] Building manifest"
find "$COMFYUI_DIR" \
  -path "*/__pycache__/*" -prune -o \
  -path "*/.git/*" -prune -o \
  -path "*/.cache/*" -prune -o \
  -path "*/cache/*" -prune -o \
  -path "*/temp/*" -prune -o \
  -path "*/tmp/*" -prune -o \
  -path "*/venv/*" -prune -o \
  -path "*/.venv/*" -prune -o \
  -path "*/node_modules/*" -prune -o \
  -type f -print | sort > "$MANIFEST_PATH"

du -ah "$COMFYUI_DIR" | sort -h > "$USAGE_PATH"
sha256sum "$MANIFEST_PATH" "$USAGE_PATH" > "$SHA_PATH"

echo "[INFO] Creating tar archive: $ARCHIVE_PATH"
rm -f "$ARCHIVE_PATH"
tar -cf "$ARCHIVE_PATH" \
  --exclude='__pycache__' \
  --exclude='.git' \
  --exclude='.cache' \
  --exclude='cache' \
  --exclude='temp' \
  --exclude='tmp' \
  --exclude='venv' \
  --exclude='.venv' \
  --exclude='node_modules' \
  -C / \
  "${COMFYUI_DIR#/}"

echo "[INFO] Archive size"
ls -lh "$ARCHIVE_PATH"
sha256sum "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"

echo "[INFO] Uploading archive and manifests to Google Drive"
rclone copy "$ARCHIVE_PATH" "$REMOTE_PROJECT/" --progress
rclone copy "${ARCHIVE_PATH}.sha256" "$REMOTE_PROJECT/" --progress
rclone copy "$MANIFEST_PATH" "$REMOTE_PROJECT/" --progress
rclone copy "$SHA_PATH" "$REMOTE_PROJECT/" --progress
rclone copy "$USAGE_PATH" "$REMOTE_PROJECT/" --progress

echo "[INFO] Remote project directory"
rclone ls "$REMOTE_PROJECT/"

echo "[INFO] Checking uploaded archive"
rclone check "$ARCHIVE_DIR" "$REMOTE_PROJECT/" --include "$PROJECT_ARCHIVE_NAME" --include "${PROJECT_ARCHIVE_NAME}.sha256" --one-way --progress

echo
echo "Backup dokoncena. Ted je bezpecne RunPod instanci ukoncit, pokud uz ji nepotrebujes."

