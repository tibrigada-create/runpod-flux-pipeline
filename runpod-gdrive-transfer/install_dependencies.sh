#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/install_dependencies_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] Installing dependencies"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl wget jq python3 python3-pip tar rclone coreutils findutils
else
  echo "[ERROR] apt-get not found. This script expects a Debian/Ubuntu RunPod image."
  exit 1
fi

python3 -m pip install --upgrade pip
python3 -m pip install --upgrade requests huggingface_hub

echo "[INFO] Verifying tools"
rclone --version | head -n 2
python3 --version
jq --version
tar --version | head -n 1

echo "[INFO] Done"

