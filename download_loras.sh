#!/usr/bin/env bash
set -Eeuo pipefail

MANIFEST="${1:-lora_manifest.tsv}"
LORA_DIR="${LORA_DIR:-/workspace/ComfyUI/models/loras}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST"
  echo "Copy lora_manifest.example.tsv to lora_manifest.tsv and add LoRA rows."
  exit 1
fi

mkdir -p "$LORA_DIR"

resolve_url() {
  local filename="$1"
  local url="$2"

  if [[ "$url" == *"civitai.com/models/"* && "$url" != *"/api/download/models/"* ]]; then
    python - "$filename" "$url" <<'PY'
import json
import re
import sys
import urllib.request

filename = sys.argv[1]
url = sys.argv[2]
match = re.search(r"civitai\.com/models/(\d+)", url)
if not match:
    print(url)
    raise SystemExit

api_url = f"https://civitai.com/api/v1/models/{match.group(1)}"
headers = {}
req = urllib.request.Request(api_url, headers=headers)
with urllib.request.urlopen(req, timeout=60) as response:
    model = json.load(response)

versions = model.get("modelVersions") or []
for version in versions:
    for file_info in version.get("files") or []:
        name = file_info.get("name") or ""
        if name == filename:
            print(file_info.get("downloadUrl") or url)
            raise SystemExit

for version in versions:
    for file_info in version.get("files") or []:
        name = file_info.get("name") or ""
        if name.endswith((".safetensors", ".sft", ".pt")):
            print(file_info.get("downloadUrl") or url)
            raise SystemExit

print(url)
PY
    return
  fi

  if [[ "$url" == https://huggingface.co/* && "$url" != *"/resolve/"* ]]; then
    echo "${url%/}/resolve/main/${filename}?download=true"
    return
  fi

  if [[ "$url" == https://github.com/* && "$url" != *"/releases/download/"* && "$url" != *"raw.githubusercontent.com"* ]]; then
    echo ""
    return
  fi

  echo "$url"
}

line_no=0
while IFS=$'\t' read -r filename url notes || [[ -n "${filename:-}" ]]; do
  line_no=$((line_no + 1))

  filename="${filename//$'\r'/}"
  url="${url//$'\r'/}"

  [[ -z "${filename// }" ]] && continue
  [[ "$filename" == \#* ]] && continue

  if [[ -z "${url:-}" ]]; then
    echo "Skipping line $line_no: missing URL"
    continue
  fi

  if [[ "$filename" != *.safetensors && "$filename" != *.sft && "$filename" != *.pt ]]; then
    echo "Skipping line $line_no: filename should end with .safetensors, .sft, or .pt: $filename"
    continue
  fi

  dest="${LORA_DIR}/${filename}"
  if [[ -s "$dest" ]]; then
    echo "Already exists: $dest"
    continue
  fi

  resolved_url="$(resolve_url "$filename" "$url")"
  if [[ -z "$resolved_url" ]]; then
    echo "Skipping line $line_no: unsupported non-direct URL for $filename: $url"
    continue
  fi

  headers=()
  if [[ "$resolved_url" == *"civitai.com"* && -n "${CIVITAI_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${CIVITAI_TOKEN}")
  elif [[ "$resolved_url" == *"huggingface.co"* ]]; then
    if [[ -n "${HF_TOKEN:-}" ]]; then
      headers=(-H "Authorization: Bearer ${HF_TOKEN}")
    elif [[ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
      headers=(-H "Authorization: Bearer ${HUGGING_FACE_HUB_TOKEN}")
    fi
  fi

  echo "Downloading LoRA: $filename"
  tmp="${dest}.part"
  curl -L --fail --retry 8 --retry-delay 5 "${headers[@]}" "$resolved_url" -o "$tmp"
  mv "$tmp" "$dest"
  echo "Saved: $dest"
done < "$MANIFEST"

echo
echo "Done. LoRA files in:"
echo "  $LORA_DIR"
echo
echo "In the controller, press:"
echo "  Refresh model library"
