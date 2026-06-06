$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Config = Join-Path $ScriptDir "config.windows.ps1"
if (-not (Test-Path $Config)) {
    Write-Host "[ERROR] Missing config.windows.ps1. Run:"
    Write-Host "  Copy-Item .\config.windows.example.ps1 .\config.windows.ps1"
    exit 1
}

. $Config

function Get-UsablePython {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }
    throw "No usable Python found."
}

function Get-RcloneCommand {
    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\rclone.exe",
        "$env:ProgramFiles\Rclone\rclone.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    throw "rclone not found. Run .\install_dependencies_windows.ps1 first."
}

$Python = Get-UsablePython
$Rclone = Get-RcloneCommand
$env:Path = (Split-Path -Parent $Rclone) + ";" + $env:Path

New-Item -ItemType Directory -Force -Path $env:DOWNLOAD_STAGING | Out-Null
New-Item -ItemType Directory -Force -Path $env:ARCHIVE_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $env:LOG_DIR | Out-Null

$LogFile = Join-Path $env:LOG_DIR ("download_loras_windows_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Run-Logged {
    param([scriptblock]$Block)
    & $Block 2>&1 | Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE"
    }
}

if (-not $env:CIVITAI_TOKEN) {
    Write-Host "[WARN] CIVITAI_TOKEN is not set. Gated Civitai downloads may fail."
}
if (-not $env:HF_TOKEN -and -not $env:HUGGING_FACE_HUB_TOKEN) {
    Write-Host "[WARN] HF_TOKEN is not set. Gated Hugging Face downloads may fail."
}

$env:LORAS_CSV = Join-Path $ScriptDir "loras.csv"

Write-Host "[INFO] Testing rclone remote"
Run-Logged { & $Rclone lsd "$($env:RCLONE_REMOTE):" }
Run-Logged { & $Rclone mkdir "$($env:RCLONE_REMOTE):$($env:DRIVE_LORA_DIR)" }

Write-Host "[INFO] Starting LoRA downloader"
Run-Logged { & $Python (Join-Path $ScriptDir "download_loras_to_gdrive.py") }

Write-Host "[INFO] Remote LoRA directory"
Run-Logged { & $Rclone ls "$($env:RCLONE_REMOTE):$($env:DRIVE_LORA_DIR)/" }

Write-Host "[INFO] Done"
