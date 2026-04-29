@echo off
setlocal EnableExtensions

cd /d "%~dp0\..\.."

if "%~1"=="" (
  echo Usage: %~nx0 ^<dataset_name^>
  echo Example: %~nx0 aubreyplaza
  exit /b 1
)

set "DATASET_NAME=%~1"
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\ernie_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\ernie\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "ERNIE_DIT=C:/Development/ComfyUI/models/diffusion_models/Ernie/ernie-image.safetensors"
set "ERNIE_VAE=C:/Development/ComfyUI/models/vae/flux2_vae.safetensors"
set "ERNIE_TEXT_ENCODER=C:/Development/ComfyUI/models/text_encoders/ministral-3-3b.safetensors"
set "OUTPUT_NAME=ernie_%DATASET_NAME%_v1"

if not exist "%PYTHON_EXE%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Python executable not found: %PYTHON_EXE%
  exit /b 1
)

echo [INFO] Dataset name   : %DATASET_NAME%
echo [INFO] Dataset config : %DATASET_CONFIG%
echo [INFO] Output prefix  : %OUTPUT_NAME%

> "%STATUS_FILE%" echo running
echo [INFO] Running ERNIE-Image LoRA training...
"%PYTHON_EXE%" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 src\musubi_tuner\ernie_image_train_network.py ^
  --mixed_precision bf16 ^
  --dataset_config "%DATASET_CONFIG%" ^
  --dit "%ERNIE_DIT%" ^
  --vae "%ERNIE_VAE%" ^
  --text_encoder "%ERNIE_TEXT_ENCODER%" ^
  --sdpa ^
  --timestep_sampling shift ^
  --weighting_scheme none ^
  --discrete_flow_shift 4.0 ^
  --optimizer_type adamw8bit ^
  --learning_rate 1e-4 ^
  --gradient_checkpointing ^
  --max_data_loader_n_workers 2 ^
  --persistent_data_loader_workers ^
  --fp8_base --fp8_scaled ^
  --fp8_text_encoder ^
  --blocks_to_swap 4 ^
  --use_pinned_memory_for_block_swap ^
  --network_module networks.lora_ernie_image ^
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
