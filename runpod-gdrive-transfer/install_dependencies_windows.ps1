$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("install_dependencies_windows_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

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
    return $null
}

function Write-Log {
    param([string]$Message)
    $Message | Tee-Object -FilePath $LogFile -Append
}

Write-Log "[INFO] Checking Python"
$Python = Get-UsablePython
& $Python --version | Tee-Object -FilePath $LogFile -Append

Write-Log "[INFO] Installing Python packages"
& $Python -m ensurepip --upgrade | Tee-Object -FilePath $LogFile -Append
& $Python -m pip install --upgrade pip requests huggingface_hub | Tee-Object -FilePath $LogFile -Append

$Rclone = Get-RcloneCommand
if ($null -eq $Rclone) {
    Write-Log "[WARN] rclone not found."
    $Winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -ne $Winget) {
        Write-Log "[INFO] Installing rclone through winget"
        winget install --id Rclone.Rclone --exact --accept-package-agreements --accept-source-agreements | Tee-Object -FilePath $LogFile -Append
        $Rclone = Get-RcloneCommand
    } else {
        Write-Log "[ERROR] winget not found. Install rclone manually from https://rclone.org/downloads/"
        exit 1
    }
} else {
    Write-Log "[INFO] rclone found: $Rclone"
}

if ($null -eq $Rclone) {
    Write-Log "[ERROR] rclone install finished, but rclone.exe was not found. Restart PowerShell and try again."
    exit 1
}

Write-Log "[INFO] Verifying rclone"
& $Rclone --version | Select-Object -First 3 | Tee-Object -FilePath $LogFile -Append

Write-Log "[INFO] Done"
