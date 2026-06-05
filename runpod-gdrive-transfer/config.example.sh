#!/usr/bin/env bash

# Copy this file to config.sh and adjust values if needed.

RCLONE_REMOTE="gdrive"
GDRIVE_BASE="RunPod_Backup"

LOCAL_WORKSPACE="/workspace"
COMFYUI_DIR="/workspace/ComfyUI"

BACKUP_STAGING="/workspace/_backup_staging"
DOWNLOAD_STAGING="/workspace/_download_staging"
ARCHIVE_DIR="/workspace/_archives"
LOG_DIR="./logs"

LORA_TARGET_DIR="/workspace/ComfyUI/models/loras"

DRIVE_PROJECT_DIR="RunPod_Backup/project"
DRIVE_LORA_DIR="RunPod_Backup/loras"

PROJECT_ARCHIVE_NAME="runpod_project_latest.tar"
LORA_ARCHIVE_NAME="flux_loras_bundle.tar"

# Set to "yes" only when you intentionally want restore scripts to overwrite
# files that already exist under /workspace.
RESTORE_OVERWRITE="no"

