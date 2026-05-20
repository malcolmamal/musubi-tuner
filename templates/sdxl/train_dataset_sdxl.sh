#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
MUSUBI_ROOT="$(pwd)"

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") <dataset_name>"
  echo "Example: $(basename "$0") aubreyplaza"
  exit 1
fi

DATASET_NAME="$1"
SOURCE_DATASET_DIR="${SOURCE_DATASET_DIR:-$(pwd)/../ai-toolkit/datasets/${DATASET_NAME}}"
CURRENTSET_DIR="${MUSUBI_ROOT}/datasets/currentset"
CACHE_DIR="${MUSUBI_ROOT}/datasets/cache"
STATUS_FILE="${MUSUBI_ROOT}/datasets/sdxl_${DATASET_NAME}.txt"
DATASET_CONFIG="${MUSUBI_ROOT}/templates/sdxl/dataset.currentset.toml"
PYTHON_EXE="${MUSUBI_ROOT}/venv/bin/python"
SDXL_CHECKPOINT="${SDXL_CHECKPOINT:-${MUSUBI_ROOT}/../ComfyUI/models/checkpoints/SDXL/bigLove_ultra3.safetensors}"
SD_SCRIPTS_DIR="${SD_SCRIPTS_DIR:-${MUSUBI_ROOT}/../kohya_ss/sd-scripts}"
OUTPUT_NAME="sdxl_${DATASET_NAME}_v1"
EXIT_CODE=0

if [ ! -d "$SOURCE_DATASET_DIR" ]; then
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] Dataset directory not found: $SOURCE_DATASET_DIR"
  exit 1
fi

if [ ! -f "$PYTHON_EXE" ]; then
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] Python executable not found: $PYTHON_EXE"
  exit 1
fi

IMAGE_COUNT=$("$PYTHON_EXE" -c "
from pathlib import Path
exts={'.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl'}
print(sum(1 for f in Path('${SOURCE_DATASET_DIR}').iterdir() if f.is_file() and f.suffix.lower() in exts))
")

if [ "$IMAGE_COUNT" = "0" ] || [ -z "$IMAGE_COUNT" ]; then
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] No supported image files found in: $SOURCE_DATASET_DIR"
  exit 1
fi

echo "starting" > "$STATUS_FILE"

echo "[INFO] Dataset name   : $DATASET_NAME"
echo "[INFO] Source dataset : $SOURCE_DATASET_DIR"
echo "[INFO] Staging dir    : $CURRENTSET_DIR"
echo "[INFO] Cache dir      : $CACHE_DIR"
echo "[INFO] Status file    : $STATUS_FILE"
echo "[INFO] Dataset config : $DATASET_CONFIG"
echo "[INFO] Output prefix  : $OUTPUT_NAME"
echo "[INFO] Image count    : $IMAGE_COUNT"
echo "[INFO] Base model     : $SDXL_CHECKPOINT"

mkdir -p "$CURRENTSET_DIR" "$CACHE_DIR"

# Clear staging and cache
rm -rf "${CURRENTSET_DIR:?}"/* "${CACHE_DIR:?}"/*

# Copy images
echo "[INFO] Copying dataset images to currentset..."
find "$SOURCE_DATASET_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.jxl' \) -exec cp {} "$CURRENTSET_DIR/" \;

# Create caption files
echo "[INFO] Creating caption files with sks trigger word..."
for img in "$CURRENTSET_DIR"/*.{png,jpg,jpeg,webp,bmp,avif,jxl}; do
  [ -f "$img" ] || continue
  caption="${img%.*}.txt"
  if [ ! -f "$caption" ]; then
    printf 'sks' > "$caption"
  fi
done

cleanup() {
  echo "[INFO] Cleaning staging and cache directories..."
  rm -rf "${CURRENTSET_DIR:?}"/* "${CACHE_DIR:?}"/*
}

pushd "$SD_SCRIPTS_DIR" > /dev/null

echo "running" > "$STATUS_FILE"
echo "[INFO] Running SDXL character LoRA training..."
"$PYTHON_EXE" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 sdxl_train_network.py \
  --pretrained_model_name_or_path "$SDXL_CHECKPOINT" \
  --dataset_config "$DATASET_CONFIG" \
  --output_dir "${MUSUBI_ROOT}/output" \
  --output_name "$OUTPUT_NAME" \
  --save_model_as safetensors \
  --mixed_precision bf16 \
  --network_module networks.lora \
  --network_dim 32 \
  --network_alpha 16 \
  --network_train_unet_only \
  --learning_rate 1e-4 \
  --lr_scheduler cosine_with_restarts \
  --lr_warmup_steps 100 \
  --optimizer_type AdamW8bit \
  --max_train_epochs 100 \
  --save_every_n_epochs 100 \
  --gradient_checkpointing \
  --cache_latents \
  --cache_text_encoder_outputs \
  --sdpa \
  --max_data_loader_n_workers 2 \
  --persistent_data_loader_workers \
  --seed 42 \
  --max_token_length 150 || {
  popd > /dev/null
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] Training failed."
  EXIT_CODE=1
  cleanup
  exit 1
}

popd > /dev/null

TRAINED_LORA="${MUSUBI_ROOT}/output/${OUTPUT_NAME}.safetensors"
RESIZED_LORA="${MUSUBI_ROOT}/output/${OUTPUT_NAME}_resized.safetensors"

if [ -f "$TRAINED_LORA" ]; then
  echo "[INFO] Resizing LoRA via SVD compression..."
  PYTHONPATH="$SD_SCRIPTS_DIR" "$PYTHON_EXE" "$SD_SCRIPTS_DIR/networks/resize_lora.py" \
    --model "$TRAINED_LORA" \
    --save_to "$RESIZED_LORA" \
    --new_rank 8 \
    --save_precision bf16 \
    --device cuda \
    --dynamic_method sv_fro \
    --dynamic_param 0.999 || echo "[WARN] LoRA resize failed, original file still available."

  if [ -f "$RESIZED_LORA" ]; then
    echo "[INFO] Resized LoRA saved to: $RESIZED_LORA"
  fi
fi

cleanup

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "[ERROR] Wrapper finished with failures."
  exit "$EXIT_CODE"
fi

echo "finished" > "$STATUS_FILE"
echo "[INFO] Completed successfully."
exit 0
