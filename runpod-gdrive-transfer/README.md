# RunPod Google Drive Transfer Toolkit

Reusable scripts for backing up a RunPod ComfyUI workspace to Google Drive, restoring it on a new RunPod, and downloading LoRA files into a reusable Google Drive bundle.

The goal is to keep expensive RunPod storage usage low while keeping the project reproducible.

## What This Toolkit Does

There are four workflows:

A. First backup of the current RunPod work to Google Drive  
B. Restore the work on a new RunPod  
C. Download additional LoRA files and upload them to Google Drive  
D. Back up final changes after a work session

The scripts use:

```text
rclone -> Google Drive
tar    -> archive files
Python -> LoRA metadata/download logic
```

They do not use public Google Drive links through `wget` or `curl`.

## Files

```text
config.example.sh              example configuration
install_dependencies.sh         installs rclone, jq, Python packages, etc.
setup_rclone.md                 manual Google Drive rclone setup
export_project_to_gdrive.sh     archives /workspace/ComfyUI and uploads it
restore_project_from_gdrive.sh  restores the project archive
loras.csv                       LoRA source list
download_loras_to_gdrive.py     robust LoRA downloader
download_loras_to_gdrive.sh     shell wrapper for the downloader
restore_loras_from_gdrive.sh    restores LoRA tar into ComfyUI
safety_check.sh                 prints disk/Drive status
quick_start.sh                  optional restore helper for new pods
logs/                           generated logs
```

## Important Storage Notes

GitHub Free should store this toolkit and project source code, not large model binaries.

Google Drive can store the large archives if you have enough space. Your current expected project archive may be tens of GB.

The project export uses plain `.tar`, not gzip. AI model files are already compressed, so gzip usually saves little space and wastes time.

## One-Time Setup On Current RunPod

From the RunPod terminal:

```bash
cd /workspace
git clone https://github.com/tibrigada-create/runpod-flux-pipeline.git
```

If this toolkit is inside that repo, go to it. If you upload it as a separate folder, go to that folder:

```bash
cd /workspace/runpod-flux-pipeline/runpod-gdrive-transfer
```

If the folder is directly in `/workspace`:

```bash
cd /workspace/runpod-gdrive-transfer
```

Create config:

```bash
cp config.example.sh config.sh
nano config.sh
```

For the current setup, defaults are usually fine:

```text
RCLONE_REMOTE="gdrive"
GDRIVE_BASE="RunPod_Backup"
LOCAL_WORKSPACE="/workspace"
COMFYUI_DIR="/workspace/ComfyUI"
```

Install dependencies:

```bash
bash install_dependencies.sh
```

Configure rclone:

```bash
rclone config
```

Follow `setup_rclone.md`.

Test:

```bash
rclone lsd gdrive:
rclone mkdir gdrive:RunPod_Backup
rclone ls gdrive:RunPod_Backup
```

## A. First Backup From Current RunPod

Run:

```bash
bash safety_check.sh
bash export_project_to_gdrive.sh
```

The script creates:

```text
/workspace/_archives/runpod_project_latest.tar
/workspace/_archives/runpod_project_latest.tar.sha256
/workspace/_backup_staging/manifest_project.txt
/workspace/_backup_staging/manifest_project.sha256
/workspace/_backup_staging/disk_usage_project.txt
```

Then it uploads them to:

```text
gdrive:RunPod_Backup/project/
```

At the end it prints that the backup is complete. Only then is it safe to stop the RunPod if you no longer need it.

## B. Restore On A New RunPod

On the new RunPod:

```bash
cd /workspace
git clone https://github.com/tibrigada-create/runpod-flux-pipeline.git
cd /workspace/runpod-flux-pipeline/runpod-gdrive-transfer
cp config.example.sh config.sh
nano config.sh
bash install_dependencies.sh
```

Configure rclone again using `setup_rclone.md`, or securely copy your existing rclone config.

Then restore:

```bash
bash restore_project_from_gdrive.sh
```

The script downloads:

```text
gdrive:RunPod_Backup/project/runpod_project_latest.tar
```

and extracts it back under `/workspace`.

If `/workspace/ComfyUI` already exists, the script asks for confirmation before allowing overwrite.

## C. Download LoRAs To Google Drive

LoRA sources are listed in:

```text
loras.csv
```

Some Hugging Face or Civitai models may require login, license acceptance, or tokens.

Set tokens only as environment variables:

```bash
export HF_TOKEN='hf_your_token_here'
export CIVITAI_TOKEN='your_civitai_token_here'
```

Never paste tokens into screenshots, GitHub files, or chat. If a token is exposed, revoke it and create a new one.

Run:

```bash
bash download_loras_to_gdrive.sh
```

The downloader:

- reads `loras.csv`
- resolves Hugging Face repo files
- resolves Civitai model metadata
- refuses to pretend success on 403/404/API errors
- rejects tiny fake model files
- computes SHA256
- creates `flux_loras_bundle.tar`
- uploads the tar, report, manifest, and checksums to Google Drive

Output location:

```text
gdrive:RunPod_Backup/loras/
```

Local staging:

```text
/workspace/_download_staging
/workspace/_archives
```

Important: URLs in the LoRA table may be inaccurate or changed. The script verifies reality and writes unresolved items into:

```text
lora_download_report.md
```

## C2. Download LoRAs From Local Windows Before Starting RunPod

This saves RunPod GPU time. It uses the same `loras.csv` and Python downloader, but runs on your PC.

From PowerShell:

```powershell
cd "C:\Codex projekty\Img analyzer to prompt\runpod-gdrive-transfer"
Copy-Item .\config.windows.example.ps1 .\config.windows.ps1
.\install_dependencies_windows.ps1
```

Configure Google Drive locally:

```powershell
rclone config
```

See:

```text
setup_rclone_windows.md
```

Set tokens only in the current PowerShell session:

```powershell
$env:HF_TOKEN = "hf_your_token_here"
$env:CIVITAI_TOKEN = "your_civitai_token_here"
```

Run the download/upload:

```powershell
.\download_loras_to_gdrive_windows.ps1
```

The local files are staged in:

```text
C:\RunPod_Backup_Work
```

Google Drive output:

```text
gdrive:RunPod_Backup/loras/
```

## D. Restore LoRAs From Google Drive

After restoring the project or installing ComfyUI on a new Pod:

```bash
bash restore_loras_from_gdrive.sh
```

This downloads:

```text
gdrive:RunPod_Backup/loras/flux_loras_bundle.tar
```

and extracts it into:

```text
/workspace/ComfyUI/models/loras
```

Then press `Refresh model library` in the controller, or restart ComfyUI if needed.

## End Of Work Session

At the end of each RunPod work session:

```bash
bash export_project_to_gdrive.sh
```

This updates the Google Drive project archive.

## Recommended Order For You

Current RunPod:

```bash
cd /workspace/runpod-gdrive-transfer
cp config.example.sh config.sh
nano config.sh
bash install_dependencies.sh
```

Set up Google Drive:

```bash
rclone config
```

Test:

```bash
bash safety_check.sh
```

Backup current project:

```bash
bash export_project_to_gdrive.sh
```

Download LoRAs and save them to Google Drive:

```bash
export HF_TOKEN='hf_your_token_here'
export CIVITAI_TOKEN='your_civitai_token_here'
bash download_loras_to_gdrive.sh
```

Future new RunPod:

```bash
cd /workspace
git clone https://github.com/tibrigada-create/runpod-flux-pipeline.git
cd /workspace/runpod-flux-pipeline/runpod-gdrive-transfer
cp config.example.sh config.sh
nano config.sh
bash install_dependencies.sh
rclone config
bash restore_project_from_gdrive.sh
bash restore_loras_from_gdrive.sh
```

## Troubleshooting

### rclone says remote not found

Run:

```bash
rclone config
```

and create a remote named exactly:

```text
gdrive
```

or change `RCLONE_REMOTE` in `config.sh`.

### Not enough disk space for tar

The export script needs enough local free space to create the archive before uploading it. If the project is 60 GB, expect to need roughly another 60 GB free during export.

Later improvement: stream tar directly into rclone. For first reliable version, this toolkit keeps a local archive so checksums and restore are easier.

### Civitai returns 403

Possible causes:

- missing `CIVITAI_TOKEN`
- model requires login or accepted terms
- model URL changed
- API protection/rate limit

Set:

```bash
export CIVITAI_TOKEN='your_token_here'
```

Then rerun the downloader. Check `lora_download_report.md`.

### Downloaded .safetensors Is Tiny

A real LoRA is usually tens or hundreds of MB. A tiny file is probably an HTML page, JSON error, or redirect response.

The Python downloader rejects files smaller than 1 MB.

Check manually:

```bash
ls -lh /workspace/_download_staging
```
