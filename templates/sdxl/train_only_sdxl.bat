@echo off
setlocal EnableExtensions

cd /d "%~dp0\..\.."

if "%~1"=="" (
  echo Usage: %~nx0 ^<dataset_name^>
  echo Example: %~nx0 aubreyplaza
  exit /b 1
)

set "DATASET_NAME=%~1"
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\sdxl_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\sdxl\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "SDXL_CHECKPOINT=C:/Development/ComfyUI/models/checkpoints/SDXL/bigLove_ultra3.safetensors"
set "SD_SCRIPTS_DIR=C:\Development\trainers\kohya_ss\sd-scripts"
set "OUTPUT_NAME=sdxl_%DATASET_NAME%_v1"

if not exist "%PYTHON_EXE%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Python executable not found: %PYTHON_EXE%
  exit /b 1
)

echo [INFO] Dataset name   : %DATASET_NAME%
echo [INFO] Dataset config : %DATASET_CONFIG%
echo [INFO] Output prefix  : %OUTPUT_NAME%
echo [INFO] Base model     : %SDXL_CHECKPOINT%

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
  exit /b 1
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

> "%STATUS_FILE%" echo finished
echo [INFO] Completed successfully.
exit /b 0
