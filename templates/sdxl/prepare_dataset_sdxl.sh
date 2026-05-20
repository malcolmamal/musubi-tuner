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
SOURCE_DATASET_DIR="${SOURCE_DATASET_DIR:-${MUSUBI_ROOT}/../ai-toolkit/datasets/${DATASET_NAME}}"
CURRENTSET_DIR="${MUSUBI_ROOT}/datasets/currentset"
CACHE_DIR="${MUSUBI_ROOT}/datasets/cache"
STATUS_FILE="${MUSUBI_ROOT}/datasets/sdxl_${DATASET_NAME}.txt"
DATASET_CONFIG="${MUSUBI_ROOT}/templates/sdxl/dataset.currentset.toml"
PYTHON_EXE="${MUSUBI_ROOT}/venv/bin/python"

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
echo "[INFO] Image count    : $IMAGE_COUNT"

mkdir -p "$CURRENTSET_DIR" "$CACHE_DIR"

echo "[INFO] Clearing staging and cache directories..."
rm -rf "${CURRENTSET_DIR:?}"/* "${CACHE_DIR:?}"/*

echo "[INFO] Copying dataset images to currentset..."
find "$SOURCE_DATASET_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.jxl' \) -exec cp {} "$CURRENTSET_DIR/" \;

echo "[INFO] Creating caption files with sks trigger word..."
for img in "$CURRENTSET_DIR"/*.{png,jpg,jpeg,webp,bmp,avif,jxl}; do
  [ -f "$img" ] || continue
  caption="${img%.*}.txt"
  if [ ! -f "$caption" ]; then
    printf 'sks' > "$caption"
  fi
done

echo "[INFO] Dataset preparation complete."
echo "finished" > "$STATUS_FILE"
exit 0
