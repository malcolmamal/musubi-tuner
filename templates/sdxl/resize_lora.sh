#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
MUSUBI_ROOT="$(pwd)"

# ============================================================
#  Resize a LoRA to a lower rank via SVD compression
#
#  Usage:
#    resize_lora.sh <lora_file> [new_rank]
#
#  Examples:
#    resize_lora.sh sdxl_feliciaday_v1.safetensors
#    resize_lora.sh sdxl_feliciaday_v1.safetensors 16
#    resize_lora.sh /full/path/to/lora.safetensors 4
#
#  Output: <original_name>_resized.safetensors in same directory
#  Default rank: 8
# ============================================================

PYTHON_EXE="${MUSUBI_ROOT}/venv/bin/python"
SD_SCRIPTS_DIR="${SD_SCRIPTS_DIR:-${MUSUBI_ROOT}/../kohya_ss/sd-scripts}"
RESIZE_SCRIPT="${SD_SCRIPTS_DIR}/networks/resize_lora.py"

SEARCH_DIR1="${MUSUBI_ROOT}/output"
SEARCH_DIR2="${MUSUBI_ROOT}/../OneTrainer/models"
SEARCH_DIR3="${MUSUBI_ROOT}/../ComfyUI/models/loras/SDXL"

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") <lora_file> [new_rank]"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") sdxl_feliciaday_v1.safetensors"
  echo "  $(basename "$0") sdxl_feliciaday_v1.safetensors 16"
  exit 1
fi

LORA_FILE="$1"
NEW_RANK="${2:-8}"
RESOLVED=""

# Resolve lora file path
if [ -f "$LORA_FILE" ]; then
  RESOLVED="$LORA_FILE"
elif [ -f "${SEARCH_DIR1}/${LORA_FILE}" ]; then
  RESOLVED="${SEARCH_DIR1}/${LORA_FILE}"
elif [ -f "${SEARCH_DIR2}/${LORA_FILE}" ]; then
  RESOLVED="${SEARCH_DIR2}/${LORA_FILE}"
elif [ -f "${SEARCH_DIR3}/${LORA_FILE}" ]; then
  RESOLVED="${SEARCH_DIR3}/${LORA_FILE}"
else
  echo "[ERROR] LoRA file not found: $LORA_FILE"
  echo "        Searched: $SEARCH_DIR1, $SEARCH_DIR2, $SEARCH_DIR3"
  exit 1
fi

# Build output path: same directory, _resized suffix
LORA_DIR="$(dirname "$RESOLVED")"
LORA_NAME="$(basename "$RESOLVED" .safetensors)"
SAVE_TO="${LORA_DIR}/${LORA_NAME}_resized.safetensors"

echo "[INFO] Input:  $RESOLVED"
echo "[INFO] Output: $SAVE_TO"
echo "[INFO] New rank: $NEW_RANK"
echo ""

PYTHONPATH="$SD_SCRIPTS_DIR" "$PYTHON_EXE" "$RESIZE_SCRIPT" \
  --model "$RESOLVED" \
  --save_to "$SAVE_TO" \
  --new_rank "$NEW_RANK" \
  --save_precision bf16 \
  --device cuda \
  --dynamic_method sv_fro \
  --dynamic_param 0.999

echo ""

ORIG_SIZE=$(stat -c%s "$RESOLVED" 2>/dev/null || stat -f%z "$RESOLVED")
NEW_SIZE=$(stat -c%s "$SAVE_TO" 2>/dev/null || stat -f%z "$SAVE_TO")
ORIG_MB=$((ORIG_SIZE / 1048576))
NEW_MB=$((NEW_SIZE / 1048576))
echo "[INFO] Original: ${ORIG_MB} MB -> Resized: ${NEW_MB} MB"
echo "[INFO] Saved to: $SAVE_TO"

exit 0
