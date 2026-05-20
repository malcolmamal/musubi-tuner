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

echo [INFO] Creating caption files with sks trigger word...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%CURRENTSET_DIR%' -File | Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.webp','.bmp','.avif','.jxl' } | ForEach-Object { $caption = [System.IO.Path]::ChangeExtension($_.FullName, '.txt'); if (-not (Test-Path -LiteralPath $caption)) { Set-Content -LiteralPath $caption -Value 'sks' -NoNewline } }"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Failed to create caption files in currentset.
  exit /b 1
)

> "%STATUS_FILE%" echo prepared
echo [INFO] Dataset prepared. Run train_only_sdxl.bat %DATASET_NAME% to start training.
exit /b 0
