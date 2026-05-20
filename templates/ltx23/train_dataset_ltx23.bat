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
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\ltx23_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\ltx23\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "LTX2_CHECKPOINT=C:/Development/ComfyUI/models/checkpoints/LTX2/ltx-2.3-22b-dev.safetensors"
set "GEMMA_SAFETENSORS=C:/Development/ComfyUI/models/text_encoders/gemma_3_12B_it_fp8_e4m3fn.safetensors"
set "COUNT_FILE=%TEMP%\musubi_ltx23_image_count.txt"
set "EXIT_CODE=0"
set "IMAGE_COUNT=0"
set "OUTPUT_NAME=ltx23_%DATASET_NAME%_v1"

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

powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | ForEach-Object { $caption = [System.IO.Path]::ChangeExtension($_.FullName, '.txt'); if (-not (Test-Path -LiteralPath $caption)) { New-Item -ItemType File -Path $caption | Out-Null } }"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to create empty caption files in currentset.
  set "EXIT_CODE=1"
  goto cleanup
)

echo [INFO] Running latent caching...
"%PYTHON_EXE%" ltx2_cache_latents.py ^
  --dataset_config "%DATASET_CONFIG%" ^
  --ltx2_checkpoint "%LTX2_CHECKPOINT%" ^
  --device cuda ^
  --vae_dtype bf16 ^
  --ltx2_mode video ^
  --skip_existing
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Latent caching failed.
  set "EXIT_CODE=1"
  goto cleanup
)

echo [INFO] Running text encoder caching...
"%PYTHON_EXE%" ltx2_cache_text_encoder_outputs.py ^
  --dataset_config "%DATASET_CONFIG%" ^
  --ltx2_checkpoint "%LTX2_CHECKPOINT%" ^
  --gemma_safetensors "%GEMMA_SAFETENSORS%" ^
  --device cuda ^
  --mixed_precision bf16 ^
  --ltx2_mode video ^
  --batch_size 1 ^
  --skip_existing
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Text encoder caching failed.
  set "EXIT_CODE=1"
  goto cleanup
)

> "%STATUS_FILE%" echo running
echo [INFO] Running optimized training...
"%PYTHON_EXE%" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 ltx2_train_network.py --mixed_precision bf16 --dataset_config "%DATASET_CONFIG%" --gemma_safetensors "%GEMMA_SAFETENSORS%" --ltx2_checkpoint "%LTX2_CHECKPOINT%" --ltx_version 2.3 --ltx_version_check_mode error --ltx2_mode video --lora_target_preset video_sa_ca_ff --fp8_base --fp8_scaled --blocks_to_swap 4 --use_pinned_memory_for_block_swap --sdpa --gradient_checkpointing --learning_rate 1e-4 --optimizer_type AdamW --lr_scheduler constant_with_warmup --lr_warmup_steps 100 --max_train_epochs 120 --max_data_loader_n_workers 8 --persistent_data_loader_workers --save_every_n_epochs 120 --network_module networks.lora_ltx2 --network_dim 32 --network_alpha 32 --no_save_original_lora --timestep_sampling shifted_logit_normal --output_dir output --output_name "%OUTPUT_NAME%"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Training failed.
  set "EXIT_CODE=1"
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