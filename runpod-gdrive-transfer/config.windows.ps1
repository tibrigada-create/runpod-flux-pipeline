# Copy this file to config.windows.ps1 and adjust paths if needed.

$env:RCLONE_REMOTE = "gdrive"
$env:GDRIVE_BASE = "RunPod_Backup"

$env:LOCAL_WORKSPACE = "C:\RunPod_Backup_Work"
$env:DOWNLOAD_STAGING = "C:\RunPod_Backup_Work\download_staging"
$env:ARCHIVE_DIR = "C:\RunPod_Backup_Work\archives"
$env:LOG_DIR = "C:\RunPod_Backup_Work\logs"

$env:DRIVE_LORA_DIR = "RunPod_Backup/loras"
$env:LORA_ARCHIVE_NAME = "flux_loras_bundle.tar"

# Tokens are intentionally not stored here.
# Set them in the current PowerShell session before running the downloader:
#   $env:HF_TOKEN = "hf_your_token_here"
#   $env:CIVITAI_TOKEN = "your_civitai_token_here"

