@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0\..\.."

REM ============================================================
REM  Merge multiple character LoRAs into a single LoRA via SVD
REM
REM  Usage:
REM    merge_character_loras.bat <output_name> <lora1:strength> <lora2:strength> [lora3:strength] ...
REM
REM  Example:
REM    merge_character_loras.bat sdxl_feliciaday_merged ^
REM      "sdxl_feliciaday_v1.safetensors:0.7" ^
REM      "sdxl_feliciaday_v1_onetrainer.safetensors:0.5" ^
REM      "sdxl_feliciaday_v1_resized.safetensors:0.3"
REM
REM  LoRA files are looked up in these directories (first match wins):
REM    1. C:\Development\trainers\musubi-tuner\output
REM    2. C:\Development\trainers\OneTrainer\models
REM    3. C:\Development\ComfyUI\models\loras\sdxl
REM    4. Absolute path (if provided)
REM
REM  Output is saved to: output\<output_name>.safetensors
REM ============================================================

set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "SD_SCRIPTS_DIR=C:\Development\trainers\kohya_ss\sd-scripts"
set "MERGE_SCRIPT=%SD_SCRIPTS_DIR%\networks\svd_merge_lora.py"
set "OUTPUT_DIR=C:\Development\trainers\musubi-tuner\output"
set "NEW_RANK=64"

set "SEARCH_DIR1=%OUTPUT_DIR%"
set "SEARCH_DIR2=C:\Development\trainers\OneTrainer\models"
set "SEARCH_DIR3=C:\Development\ComfyUI\models\loras\sdxl"

if "%~1"=="" (
  echo Usage: %~nx0 ^<output_name^> ^<lora1:strength^> ^<lora2:strength^> [lora3:strength] ...
  echo.
  echo Example:
  echo   %~nx0 sdxl_feliciaday_merged "sdxl_feliciaday_v1.safetensors:0.7" "sdxl_feliciaday_v1_onetrainer.safetensors:0.5"
  exit /b 1
)

set "OUTPUT_NAME=%~1"
shift

if "%~1"=="" (
  echo [ERROR] Need at least two lora:strength pairs.
  exit /b 1
)

set "MODELS="
set "RATIOS="
set "COUNT=0"

:parse_args
if "%~1"=="" goto done_parsing

set "ARG=%~1"

REM Split on last colon to get lora_file and strength
for /f "tokens=1,* delims=:" %%a in ("%ARG%") do (
  set "LORA_FILE=%%a"
  set "STRENGTH=%%b"
)

if "!STRENGTH!"=="" (
  echo [ERROR] Invalid format: %ARG% — expected lora_file:strength
  exit /b 1
)

REM Resolve lora file path
set "RESOLVED="

REM Check if it's already an absolute path
if exist "!LORA_FILE!" (
  set "RESOLVED=!LORA_FILE!"
  goto found_lora
)

REM Search directories
if exist "%SEARCH_DIR1%\!LORA_FILE!" (
  set "RESOLVED=%SEARCH_DIR1%\!LORA_FILE!"
  goto found_lora
)
if exist "%SEARCH_DIR2%\!LORA_FILE!" (
  set "RESOLVED=%SEARCH_DIR2%\!LORA_FILE!"
  goto found_lora
)
if exist "%SEARCH_DIR3%\!LORA_FILE!" (
  set "RESOLVED=%SEARCH_DIR3%\!LORA_FILE!"
  goto found_lora
)

echo [ERROR] LoRA file not found: !LORA_FILE!
echo         Searched: %SEARCH_DIR1%, %SEARCH_DIR2%, %SEARCH_DIR3%
exit /b 1

:found_lora
echo [INFO] LoRA: !RESOLVED! @ strength !STRENGTH!
set "MODELS=!MODELS! "!RESOLVED!""
set "RATIOS=!RATIOS! !STRENGTH!"
set /a COUNT+=1

shift
goto parse_args

:done_parsing

if %COUNT% LSS 2 (
  echo [ERROR] Need at least two lora:strength pairs, got %COUNT%.
  exit /b 1
)

set "SAVE_TO=%OUTPUT_DIR%\%OUTPUT_NAME%.safetensors"

echo.
echo [INFO] Merging %COUNT% LoRAs into: %SAVE_TO%
echo [INFO] Output rank: %NEW_RANK%
echo.

set "PYTHONPATH=%SD_SCRIPTS_DIR%"
"%PYTHON_EXE%" "%MERGE_SCRIPT%" ^
  --models%MODELS% ^
  --ratios%RATIOS% ^
  --save_to "%SAVE_TO%" ^
  --new_rank %NEW_RANK% ^
  --save_precision bf16 ^
  --precision float ^
  --device cuda

if errorlevel 1 (
  echo [ERROR] Merge failed.
  exit /b 1
)

echo.
echo [INFO] Merged LoRA saved to: %SAVE_TO%

REM Show file size
for %%F in ("%SAVE_TO%") do (
  set "SIZE=%%~zF"
  set /a "SIZE_MB=!SIZE! / 1048576"
  echo [INFO] File size: !SIZE_MB! MB
)

exit /b 0
