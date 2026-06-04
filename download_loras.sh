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

  headers=()
  if [[ "$url" == *"civitai.com"* && -n "${CIVITAI_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${CIVITAI_TOKEN}")
  elif [[ "$url" == *"huggingface.co"* ]]; then
    if [[ -n "${HF_TOKEN:-}" ]]; then
      headers=(-H "Authorization: Bearer ${HF_TOKEN}")
    elif [[ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
      headers=(-H "Authorization: Bearer ${HUGGING_FACE_HUB_TOKEN}")
    fi
  fi

  echo "Downloading LoRA: $filename"
  tmp="${dest}.part"
  curl -L --fail --retry 8 --retry-delay 5 "${headers[@]}" "$url" -o "$tmp"
  mv "$tmp" "$dest"
  echo "Saved: $dest"
done < "$MANIFEST"

echo
echo "Done. LoRA files in:"
echo "  $LORA_DIR"
echo
echo "In the controller, press:"
echo "  Refresh model library"
