#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
MUSUBI_ROOT="$(pwd)"

# ============================================================
#  Merge multiple character LoRAs into a single LoRA via SVD
#
#  Usage:
#    merge_character_loras.sh <output_name> <lora1:strength> <lora2:strength> [lora3:strength] ...
#
#  Example:
#    merge_character_loras.sh sdxl_feliciaday_merged \
#      "sdxl_feliciaday_v1.safetensors:0.7" \
#      "sdxl_feliciaday_v1_onetrainer.safetensors:0.5" \
#      "sdxl_feliciaday_v1_resized.safetensors:0.3"
#
#  LoRA files are looked up in these directories (first match wins):
#    1. <musubi-tuner>/output
#    2. <musubi-tuner>/../OneTrainer/models
#    3. <musubi-tuner>/../ComfyUI/models/loras/SDXL
#    4. Absolute path (if provided)
#
#  Output is saved to: output/<output_name>.safetensors
# ============================================================

PYTHON_EXE="${MUSUBI_ROOT}/venv/bin/python"
SD_SCRIPTS_DIR="${SD_SCRIPTS_DIR:-${MUSUBI_ROOT}/../kohya_ss/sd-scripts}"
MERGE_SCRIPT="${SD_SCRIPTS_DIR}/networks/svd_merge_lora.py"
OUTPUT_DIR="${MUSUBI_ROOT}/output"
NEW_RANK=64

SEARCH_DIR1="$OUTPUT_DIR"
SEARCH_DIR2="${MUSUBI_ROOT}/../OneTrainer/models"
SEARCH_DIR3="${MUSUBI_ROOT}/../ComfyUI/models/loras/SDXL"

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") <output_name> <lora1:strength> <lora2:strength> [lora3:strength] ..."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") sdxl_feliciaday_merged \"sdxl_feliciaday_v1.safetensors:0.7\" \"sdxl_feliciaday_v1_onetrainer.safetensors:0.5\""
  exit 1
fi

OUTPUT_NAME="$1"
shift

if [ -z "${1:-}" ]; then
  echo "[ERROR] Need at least two lora:strength pairs."
  exit 1
fi

MODELS=()
RATIOS=()
COUNT=0

resolve_lora() {
  local lora_file="$1"
  if [ -f "$lora_file" ]; then
    echo "$lora_file"
  elif [ -f "${SEARCH_DIR1}/${lora_file}" ]; then
    echo "${SEARCH_DIR1}/${lora_file}"
  elif [ -f "${SEARCH_DIR2}/${lora_file}" ]; then
    echo "${SEARCH_DIR2}/${lora_file}"
  elif [ -f "${SEARCH_DIR3}/${lora_file}" ]; then
    echo "${SEARCH_DIR3}/${lora_file}"
  else
    echo ""
  fi
}

while [ $# -gt 0 ]; do
  ARG="$1"

  # Split on last colon: everything before is filename, after is strength
  LORA_FILE="${ARG%:*}"
  STRENGTH="${ARG##*:}"

  if [ -z "$STRENGTH" ] || [ "$LORA_FILE" = "$ARG" ]; then
    echo "[ERROR] Invalid format: $ARG — expected lora_file:strength"
    exit 1
  fi

  RESOLVED=$(resolve_lora "$LORA_FILE")
  if [ -z "$RESOLVED" ]; then
    echo "[ERROR] LoRA file not found: $LORA_FILE"
    echo "        Searched: $SEARCH_DIR1, $SEARCH_DIR2, $SEARCH_DIR3"
    exit 1
  fi

  echo "[INFO] LoRA: $RESOLVED @ strength $STRENGTH"
  MODELS+=("$RESOLVED")
  RATIOS+=("$STRENGTH")
  COUNT=$((COUNT + 1))

  shift
done

if [ "$COUNT" -lt 2 ]; then
  echo "[ERROR] Need at least two lora:strength pairs, got $COUNT."
  exit 1
fi

SAVE_TO="${OUTPUT_DIR}/${OUTPUT_NAME}.safetensors"

echo ""
echo "[INFO] Merging $COUNT LoRAs into: $SAVE_TO"
echo "[INFO] Output rank: $NEW_RANK"
echo ""

PYTHONPATH="$SD_SCRIPTS_DIR" "$PYTHON_EXE" "$MERGE_SCRIPT" \
  --models "${MODELS[@]}" \
  --ratios "${RATIOS[@]}" \
  --save_to "$SAVE_TO" \
  --new_rank "$NEW_RANK" \
  --save_precision bf16 \
  --precision float \
  --device cuda

echo ""
echo "[INFO] Merged LoRA saved to: $SAVE_TO"

SIZE=$(stat -c%s "$SAVE_TO" 2>/dev/null || stat -f%z "$SAVE_TO")
SIZE_MB=$((SIZE / 1048576))
echo "[INFO] File size: ${SIZE_MB} MB"

exit 0
