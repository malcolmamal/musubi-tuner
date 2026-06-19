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
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\ideogram4_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\ideogram4\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "IDEOGRAM4_VAE=C:/Development/ComfyUI/models/vae/flux2_vae.safetensors"
set "IDEOGRAM4_TEXT_ENCODER=C:/Development/ComfyUI/models/diffusion_models/Ideogram4/qwen3vl_8b_fp8_scaled.safetensors"
set "COUNT_FILE=%TEMP%\musubi_ideogram4_image_count.txt"
set "EXIT_CODE=0"
set "IMAGE_COUNT=0"

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
echo [INFO] Image count    : %IMAGE_COUNT%

if not exist "%CURRENTSET_DIR%" mkdir "%CURRENTSET_DIR%"
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

echo [INFO] Clearing staging and cache directories...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath '%CACHE_DIR%' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to clear staging or cache directories.
  exit /b 1
)

echo [INFO] Copying dataset images to currentset...
powershell -NoProfile -Command "Copy-Item -LiteralPath (Get-ChildItem -LiteralPath '%SOURCE_DATASET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | Select-Object -ExpandProperty FullName) -Destination '%CURRENTSET_DIR%' -Force"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to copy dataset images into currentset.
  exit /b 1
)

echo [INFO] Creating empty caption files...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | ForEach-Object { $caption = [System.IO.Path]::ChangeExtension($_.FullName, '.txt'); if (-not (Test-Path -LiteralPath $caption)) { New-Item -ItemType File -Path $caption | Out-Null } }"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to create empty caption files in currentset.
  exit /b 1
)

echo [INFO] Running latent caching...
"%PYTHON_EXE%" src\musubi_tuner\ideogram4_cache_latents.py ^
  --dataset_config "%DATASET_CONFIG%" ^
  --vae "%IDEOGRAM4_VAE%" ^
  --vae_dtype bfloat16 ^
  --device cuda ^
  --skip_existing
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Latent caching failed.
  exit /b 1
)

echo [INFO] Running text encoder caching...
"%PYTHON_EXE%" src\musubi_tuner\ideogram4_cache_text_encoder_outputs.py ^
  --dataset_config "%DATASET_CONFIG%" ^
  --text_encoder "%IDEOGRAM4_TEXT_ENCODER%" ^
  --text_cache_dtype bf16 ^
  --device cuda ^
  --batch_size 1 ^
  --skip_existing
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Text encoder caching failed.
  exit /b 1
)

> "%STATUS_FILE%" echo prepared
echo [INFO] Dataset prepared. Run train_only_ideogram4.bat %DATASET_NAME% to start training.
exit /b 0
