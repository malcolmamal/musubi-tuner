@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0\..\.."

REM ============================================================
REM  Resize a LoRA to a lower rank via SVD compression
REM
REM  Usage:
REM    resize_lora.bat <lora_file> [new_rank]
REM
REM  Examples:
REM    resize_lora.bat sdxl_feliciaday_v1.safetensors
REM    resize_lora.bat sdxl_feliciaday_v1.safetensors 16
REM    resize_lora.bat "C:\full\path\to\lora.safetensors" 4
REM
REM  Output: <original_name>_resized.safetensors in same directory
REM  Default rank: 8
REM ============================================================

set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "SD_SCRIPTS_DIR=C:\Development\trainers\kohya_ss\sd-scripts"
set "RESIZE_SCRIPT=%SD_SCRIPTS_DIR%\networks\resize_lora.py"

set "SEARCH_DIR1=C:\Development\trainers\musubi-tuner\output"
set "SEARCH_DIR2=C:\Development\trainers\OneTrainer\models"
set "SEARCH_DIR3=C:\Development\ComfyUI\models\loras\sdxl"

if "%~1"=="" (
  echo Usage: %~nx0 ^<lora_file^> [new_rank]
  echo.
  echo Examples:
  echo   %~nx0 sdxl_feliciaday_v1.safetensors
  echo   %~nx0 sdxl_feliciaday_v1.safetensors 16
  exit /b 1
)

set "LORA_FILE=%~1"
set "NEW_RANK=8"
if not "%~2"=="" set "NEW_RANK=%~2"

REM Resolve lora file path
set "RESOLVED="

if exist "%LORA_FILE%" (
  set "RESOLVED=%LORA_FILE%"
  goto found
)
if exist "%SEARCH_DIR1%\%LORA_FILE%" (
  set "RESOLVED=%SEARCH_DIR1%\%LORA_FILE%"
  goto found
)
if exist "%SEARCH_DIR2%\%LORA_FILE%" (
  set "RESOLVED=%SEARCH_DIR2%\%LORA_FILE%"
  goto found
)
if exist "%SEARCH_DIR3%\%LORA_FILE%" (
  set "RESOLVED=%SEARCH_DIR3%\%LORA_FILE%"
  goto found
)

echo [ERROR] LoRA file not found: %LORA_FILE%
echo         Searched: %SEARCH_DIR1%, %SEARCH_DIR2%, %SEARCH_DIR3%
exit /b 1

:found

REM Build output path: same directory, _resized suffix
for %%F in ("!RESOLVED!") do (
  set "LORA_DIR=%%~dpF"
  set "LORA_NAME=%%~nF"
  set "LORA_EXT=%%~xF"
)
set "SAVE_TO=!LORA_DIR!!LORA_NAME!_resized!LORA_EXT!"

echo [INFO] Input:  !RESOLVED!
echo [INFO] Output: !SAVE_TO!
echo [INFO] New rank: %NEW_RANK%
echo.

set "PYTHONPATH=%SD_SCRIPTS_DIR%"
"%PYTHON_EXE%" "%RESIZE_SCRIPT%" ^
  --model "!RESOLVED!" ^
  --save_to "!SAVE_TO!" ^
  --new_rank %NEW_RANK% ^
  --save_precision bf16 ^
  --device cuda ^
  --dynamic_method sv_fro ^
  --dynamic_param 0.999

if errorlevel 1 (
  echo [ERROR] Resize failed.
  exit /b 1
)

echo.

REM Show sizes
for %%A in ("!RESOLVED!") do set /a "ORIG_MB=%%~zA / 1048576"
for %%B in ("!SAVE_TO!") do set /a "NEW_MB=%%~zB / 1048576"
echo [INFO] Original: !ORIG_MB! MB -^> Resized: !NEW_MB! MB
echo [INFO] Saved to: !SAVE_TO!

exit /b 0
