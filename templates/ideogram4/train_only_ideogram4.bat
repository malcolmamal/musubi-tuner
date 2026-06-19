@echo off
setlocal EnableExtensions

cd /d "%~dp0\..\.."

if "%~1"=="" (
  echo Usage: %~nx0 ^<dataset_name^>
  echo Example: %~nx0 aubreyplaza
  exit /b 1
)

set "DATASET_NAME=%~1"
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\ideogram4_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\ideogram4\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "IDEOGRAM4_DIT=C:/Development/ComfyUI/models/diffusion_models/Ideogram4/ideogram4_fp8_scaled.safetensors"
set "OUTPUT_NAME=ideogram4_%DATASET_NAME%_v1"

if not exist "%PYTHON_EXE%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Python executable not found: %PYTHON_EXE%
  exit /b 1
)

echo [INFO] Dataset name   : %DATASET_NAME%
echo [INFO] Dataset config : %DATASET_CONFIG%
echo [INFO] Output prefix  : %OUTPUT_NAME%

> "%STATUS_FILE%" echo running
echo [INFO] Running Ideogram 4 LoRA training...
"%PYTHON_EXE%" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 src\musubi_tuner\ideogram4_train_network.py ^
  --mixed_precision bf16 ^
  --dataset_config "%DATASET_CONFIG%" ^
  --dit "%IDEOGRAM4_DIT%" ^
  --sdpa ^
  --timestep_sampling ideogram4_shift ^
  --weighting_scheme none ^
  --optimizer_type adamw8bit ^
  --learning_rate 1e-4 ^
  --gradient_checkpointing ^
  --max_data_loader_n_workers 2 ^
  --persistent_data_loader_workers ^
  --blocks_to_swap 4 ^
  --network_module networks.lora_ideogram4 ^
  --network_dim 32 ^
  --network_alpha 32 ^
  --max_train_epochs 100 ^
  --save_every_n_epochs 100 ^
  --seed 42 ^
  --output_dir output ^
  --output_name "%OUTPUT_NAME%"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Training failed.
  exit /b 1
)

> "%STATUS_FILE%" echo finished
echo [INFO] Completed successfully.
exit /b 0
