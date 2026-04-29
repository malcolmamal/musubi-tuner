@echo off
setlocal EnableExtensions

cd /d "%~dp0\..\.."

if "%~1"=="" (
  echo Usage: %~nx0 ^<dataset_name^>
  echo Example: %~nx0 aubreyplaza
  exit /b 1
)

set "DATASET_NAME=%~1"
set "STATUS_FILE=C:\Development\trainers\musubi-tuner\datasets\ltx23_%DATASET_NAME%.txt"
set "DATASET_CONFIG=C:\Development\trainers\musubi-tuner\templates\ltx23\dataset.currentset.toml"
set "PYTHON_EXE=C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe"
set "LTX2_CHECKPOINT=C:/Development/ComfyUI/models/checkpoints/LTX2/ltx-2.3-22b-dev.safetensors"
set "GEMMA_SAFETENSORS=C:/Development/ComfyUI/models/text_encoders/gemma_3_12B_it_fp8_e4m3fn.safetensors"
set "OUTPUT_NAME=ltx23_%DATASET_NAME%_v1"

if not exist "%PYTHON_EXE%" (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Python executable not found: %PYTHON_EXE%
  exit /b 1
)

echo [INFO] Dataset name   : %DATASET_NAME%
echo [INFO] Dataset config : %DATASET_CONFIG%
echo [INFO] Output prefix  : %OUTPUT_NAME%

> "%STATUS_FILE%" echo running
echo [INFO] Running optimized training...
"%PYTHON_EXE%" -m accelerate.commands.launch --num_cpu_threads_per_process 1 --mixed_precision bf16 ltx2_train_network.py --mixed_precision bf16 --dataset_config "%DATASET_CONFIG%" --gemma_safetensors "%GEMMA_SAFETENSORS%" --ltx2_checkpoint "%LTX2_CHECKPOINT%" --ltx_version 2.3 --ltx_version_check_mode error --ltx2_mode video --lora_target_preset video_sa_ca_ff --fp8_base --fp8_scaled --blocks_to_swap 4 --use_pinned_memory_for_block_swap --sdpa --gradient_checkpointing --learning_rate 1e-4 --optimizer_type AdamW --lr_scheduler constant_with_warmup --lr_warmup_steps 100 --max_train_epochs 120 --max_data_loader_n_workers 8 --persistent_data_loader_workers --save_every_n_epochs 120 --network_module networks.lora_ltx2 --network_dim 32 --network_alpha 32 --no_save_original_lora --timestep_sampling shifted_logit_normal --output_dir output --output_name "%OUTPUT_NAME%"
if errorlevel 1 (
  > "%STATUS_FILE%" echo errored
  echo [ERROR] Training failed.
  exit /b 1
)

> "%STATUS_FILE%" echo finished
echo [INFO] Completed successfully.
exit /b 0
