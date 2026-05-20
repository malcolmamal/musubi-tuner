#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

if [ -z "${1:-}" ]; then
  echo "Usage: $(basename "$0") <dataset_name>"
  echo "Example: $(basename "$0") aubreyplaza"
  exit 1
fi

DATASET_NAME="$1"
STATUS_FILE="$(pwd)/datasets/sdxl_${DATASET_NAME}.txt"
DATASET_CONFIG="$(pwd)/templates/sdxl/dataset.currentset.toml"
PYTHON_EXE="$(pwd)/venv/bin/python"
SDXL_CHECKPOINT="${SDXL_CHECKPOINT:-$(pwd)/../ComfyUI/models/checkpoints/SDXL/bigLove_ultra3.safetensors}"
SD_SCRIPTS_DIR="${SD_SCRIPTS_DIR:-$(pwd)/../kohya_ss/sd-scripts}"
OUTPUT_NAME="sdxl_${DATASET_NAME}_v1"

if [ ! -f "$PYTHON_EXE" ]; then
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] Python executable not found: $PYTHON_EXE"
  exit 1
fi

echo "[INFO] Dataset name   : $DATASET_NAME"
echo "[INFO] Dataset config : $DATASET_CONFIG"
echo "[INFO] Output prefix  : $OUTPUT_NAME"
echo "[INFO] Base model     : $SDXL_CHECKPOINT"

pushd "$SD_SCRIPTS_DIR" > /dev/null

echo "running" > "$STATUS_FILE"
echo "[INFO] Running SDXL character LoRA training..."
"$PYTHON_EXE" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 sdxl_train_network.py \
  --pretrained_model_name_or_path "$SDXL_CHECKPOINT" \
  --dataset_config "$DATASET_CONFIG" \
  --output_dir "$(dirs -l +0)/../../output" \
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
  --max_token_length 150

TRAIN_EXIT=$?
popd > /dev/null

if [ $TRAIN_EXIT -ne 0 ]; then
  echo "errored" > "$STATUS_FILE"
  echo "[ERROR] Training failed."
  exit 1
fi

MUSUBI_ROOT="$(pwd)"
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

echo "finished" > "$STATUS_FILE"
echo "[INFO] Completed successfully."
exit 0
