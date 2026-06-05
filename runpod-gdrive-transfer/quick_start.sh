#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
  cp "$SCRIPT_DIR/config.example.sh" "$SCRIPT_DIR/config.sh"
  echo "[INFO] Created config.sh from example. Review it before continuing:"
  echo "  nano $SCRIPT_DIR/config.sh"
  exit 0
fi

bash "$SCRIPT_DIR/install_dependencies.sh"
echo "[INFO] Make sure rclone is configured before continuing."
echo "      See: $SCRIPT_DIR/setup_rclone.md"
read -r -p "Continue restore now? Type YES: " answer
if [[ "$answer" != "YES" ]]; then
  exit 0
fi

bash "$SCRIPT_DIR/restore_project_from_gdrive.sh"
bash "$SCRIPT_DIR/restore_loras_from_gdrive.sh"

