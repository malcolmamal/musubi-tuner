@echo off
setlocal EnableExtensions

cd /d "%~dp0\..\.."

if "%~1"=="" (
  echo Usage: %~nx0 ^<dataset_name^>
  echo Example: %~nx0 aubreyplaza
  exit /b 1
)

set "DATASET_NAME=%~1"
set "SOURCE_DATASET_DIR=C:\Development\ai-toolkit\datasets\%DATASET_NAME%"
set "CURRENTSET_DIR=C:\Development\trainers\musubi-tuner\datasets\currentset"
set "CACHE_DIR=C:\Development\trainers\musubi-tuner\datasets\cache"
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\sdxl_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\sdxl\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "SDXL_CHECKPOINT=C:/Development/ComfyUI/models/checkpoints/SDXL/bigLove_ultra3.safetensors"
set "SD_SCRIPTS_DIR=C:\Development\trainers\kohya_ss\sd-scripts"
set "COUNT_FILE=%TEMP%\musubi_sdxl_image_count.txt"
set "EXIT_CODE=0"
set "IMAGE_COUNT=0"
set "OUTPUT_NAME=sdxl_%DATASET_NAME%_v1"

if not exist "%SOURCE_DATASET_DIR%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Dataset directory not found: %SOURCE_DATASET_DIR%
  exit /b 1
)

if not exist "%PYTHON_EXE%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Python executable not found: %PYTHON_EXE%
  exit /b 1
)

"%PYTHON_EXE%" -c "from pathlib import Path; exts={'.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl'}; print(sum(1 for f in Path(r'%SOURCE_DATASET_DIR%').iterdir() if f.is_file() and f.suffix.lower() in exts))" > "%COUNT_FILE%"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to count supported image files in: %SOURCE_DATASET_DIR%
  exit /b 1
)

set /p IMAGE_COUNT=<"%COUNT_FILE%"
del /q "%COUNT_FILE%" >nul 2>nul

if "%IMAGE_COUNT%"=="0" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] No supported image files found in: %SOURCE_DATASET_DIR%
  exit /b 1
)

> "%STATUS_FILE%" echo starting

echo [INFO] Dataset name   : %DATASET_NAME%
echo [INFO] Source dataset : %SOURCE_DATASET_DIR%
echo [INFO] Staging dir    : %CURRENTSET_DIR%
echo [INFO] Cache dir      : %CACHE_DIR%
echo [INFO] Status file    : %STATUS_FILE%
echo [INFO] Dataset config : %DATASET_CONFIG%
echo [INFO] Output prefix  : %OUTPUT_NAME%
echo [INFO] Image count    : %IMAGE_COUNT%
echo [INFO] Base model     : %SDXL_CHECKPOINT%

if not exist "%CURRENTSET_DIR%" mkdir "%CURRENTSET_DIR%"
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath '%CACHE_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to clear staging or cache directories.
  exit /b 1
)

powershell -NoProfile -Command "Copy-Item -LiteralPath (Get-ChildItem -LiteralPath '%SOURCE_DATASET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | Select-Object -ExpandProperty FullName) -Destination '%CURRENTSET_DIR%' -Force"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to copy dataset images into currentset.
  exit /b 1
)

echo [INFO] Creating caption files with sks trigger word...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | ForEach-Object { $caption = [System.IO.Path]::ChangeExtension($_.FullName, '.txt'); if (-not (Test-Path -LiteralPath $caption)) { Set-Content -LiteralPath $caption -Value 'sks' -NoNewline } }"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to create caption files in currentset.
  set "EXIT_CODE=1"
  goto cleanup
)

pushd "%SD_SCRIPTS_DIR%"

> "%STATUS_FILE%" echo running
echo [INFO] Running SDXL character LoRA training...
"%PYTHON_EXE%" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 sdxl_train_network.py ^
  --pretrained_model_name_or_path "%SDXL_CHECKPOINT%" ^
  --dataset_config "%DATASET_CONFIG%" ^
  --output_dir "C:\Development\trainers\musubi-tuner\output" ^
  --output_name "%OUTPUT_NAME%" ^
  --save_model_as safetensors ^
  --mixed_precision bf16 ^
  --network_module networks.lora ^
  --network_dim 32 ^
  --network_alpha 16 ^
  --network_train_unet_only ^
  --learning_rate 1e-4 ^
  --lr_scheduler cosine_with_restarts ^
  --lr_warmup_steps 100 ^
  --optimizer_type AdamW8bit ^
  --max_train_epochs 100 ^
  --save_every_n_epochs 100 ^
  --gradient_checkpointing ^
  --cache_latents ^
  --cache_text_encoder_outputs ^
  --sdpa ^
  --max_data_loader_n_workers 2 ^
  --persistent_data_loader_workers ^
  --seed 42 ^
  --max_token_length 150
if errorlevel 1 (
  popd
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Training failed.
  set "EXIT_CODE=1"
  goto cleanup
)

popd

set "TRAINED_LORA=C:\Development\trainers\musubi-tuner\output\%OUTPUT_NAME%.safetensors"
set "RESIZED_LORA=C:\Development\trainers\musubi-tuner\output\%OUTPUT_NAME%_resized.safetensors"

if exist "%TRAINED_LORA%" (
  echo [INFO] Resizing LoRA via SVD compression...
  set "PYTHONPATH=%SD_SCRIPTS_DIR%"
  "%PYTHON_EXE%" "%SD_SCRIPTS_DIR%\networks\resize_lora.py" ^
    --model "%TRAINED_LORA%" ^
    --save_to "%RESIZED_LORA%" ^
    --new_rank 8 ^
    --save_precision bf16 ^
    --device cuda ^
    --dynamic_method sv_fro ^
    --dynamic_param 0.999
  if errorlevel 1 (
    echo [WARN] LoRA resize failed, original file still available.
  ) else (
    echo [INFO] Resized LoRA saved to: %RESIZED_LORA%
  )
)

:cleanup
echo [INFO] Cleaning staging and cache directories...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath '%CACHE_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"

if not "%EXIT_CODE%"=="0" (
  echo [ERROR] Wrapper finished with failures.
  exit /b %EXIT_CODE%
)

> "%STATUS_FILE%" echo finished
echo [INFO] Completed successfully.
exit /b 0
