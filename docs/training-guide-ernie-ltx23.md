# Training Guide: ERNIE-Image & LTX-2.3 LoRA (Windows)

This is a step-by-step guide for setting up and running LoRA training for **ERNIE-Image** (text-to-image) and **LTX-2.3** (text-to-video) on Windows using the template scripts in this repository.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Repository Setup](#repository-setup)
- [Model Downloads](#model-downloads)
  - [ERNIE-Image models](#ernie-image-models)
  - [LTX-2.3 models](#ltx-23-models)
- [Dataset Preparation](#dataset-preparation)
- [Path Configuration](#path-configuration)
  - [Where paths are defined](#where-paths-are-defined)
  - [Changing paths for your setup](#changing-paths-for-your-setup)
- [Template Scripts Reference](#template-scripts-reference)
  - [ERNIE-Image](#ernie-image-templates)
  - [LTX-2.3](#ltx-23-templates)
- [Running a Training — Step by Step](#running-a-training--step-by-step)
  - [Option A: Full run (prepare + train in one go)](#option-a-full-run-prepare--train-in-one-go)
  - [Option B: Prepare once, train multiple times](#option-b-prepare-once-train-multiple-times)
- [Training Parameters](#training-parameters)
  - [ERNIE-Image key parameters](#ernie-image-key-parameters)
  - [LTX-2.3 key parameters](#ltx-23-key-parameters)
- [Output Files](#output-files)
- [Status Files](#status-files)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows 10/11 | Linux works too but paths in the scripts are Windows-style |
| Python 3.10+ | Verified with 3.10 |
| NVIDIA GPU | 16 GB+ VRAM recommended (scripts use fp8 + block swap to run on 12 GB) |
| CUDA 12.4+ | Match your PyTorch build |
| Git | To clone the repository |

---

## Repository Setup

> **If you already have the venv set up and training working, skip to [Path Configuration](#path-configuration).**

1. **Clone the repository** (or use your existing fork):

   ```bat
   git clone -b ernie-on-ltx https://github.com/malcolmamal/musubi-tuner C:\Development\trainers\musubi-tuner
   cd C:\Development\trainers\musubi-tuner
   ```

2. **Create and activate the virtual environment:**

   ```bat
   python -m venv venv
   venv\Scripts\activate
   ```

3. **Install PyTorch** matching your CUDA version (example for CUDA 12.4):

   ```bat
   pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
   ```

4. **Install the project dependencies:**

   ```bat
   pip install -e .
   ```

5. **Install bitsandbytes** (required for `adamw8bit` optimizer used in ERNIE scripts):

   ```bat
   pip install bitsandbytes
   ```

6. **Verify the install** — the following should complete without errors:

   ```bat
   python -c "import torch; print(torch.cuda.is_available())"
   ```

---

## Model Downloads

### ERNIE-Image models

Download from the ComfyUI-repackaged collection at [Comfy-Org/ERNIE-Image](https://huggingface.co/Comfy-Org/ERNIE-Image):

| File | Save to |
|---|---|
| `diffusion_models/ernie-image.safetensors` | `ComfyUI\models\diffusion_models\Ernie\ernie-image.safetensors` |
| `diffusion_models/ernie-image-turbo.safetensors` | `ComfyUI\models\diffusion_models\Ernie\ernie-image-turbo.safetensors` |
| `text_encoders/ministral-3-3b.safetensors` | `ComfyUI\models\text_encoders\ministral-3-3b.safetensors` |
| `vae/flux2-vae.safetensors` | `ComfyUI\models\vae\flux2_vae.safetensors` |

> **Note:** The VAE (`flux2-vae.safetensors`) is shared with FLUX.2. If you already have it under a different name, point the scripts at your existing copy — see [Path Configuration](#path-configuration).

The training scripts use `ernie-image.safetensors` (non-turbo) by default for training. Turbo is faster for inference but the base model trains more reliably.

### LTX-2.3 models

| File | Save to |
|---|---|
| `ltx-2.3-22b-dev.safetensors` | `ComfyUI\models\checkpoints\LTX2\ltx-2.3-22b-dev.safetensors` |
| `gemma_3_12B_it_fp8_e4m3fn.safetensors` | `ComfyUI\models\text_encoders\gemma_3_12B_it_fp8_e4m3fn.safetensors` |

LTX-2.3 checkpoints are available at [Lightricks/LTX-Video](https://huggingface.co/Lightricks/LTX-Video).
The Gemma fp8 text encoder is available at [hugging-quants/gemma-3-12b-it-fp8](https://huggingface.co/hugging-quants/gemma-3-12b-it-fp8) or similar community repacks.

---

## Dataset Preparation

Your images live in their own named folder. The scripts call this the **source dataset directory**.

**Default source path:** `C:\Development\ai-toolkit\datasets\<dataset_name>\`

> **This is malcolmrey's personal setup.** If your datasets live somewhere else (e.g. `D:\datasets\`, `C:\Users\you\pictures\training\`, etc.), update the `SOURCE_DATASET_DIR` variable at the top of each `.bat` script — see [Path Configuration](#path-configuration).

Put your training images (`.png`, `.jpg`, `.jpeg`, `.webp`, `.bmp`, `.avif`, `.jxl`) directly in that folder. No sub-folders needed. Caption `.txt` files will be generated automatically (empty — fill them in if you want captioned training, leave them empty for uncaptioned).

**Example layout:**
```
C:\Development\ai-toolkit\datasets\
└── aubreyplaza\
    ├── img_001.jpg
    ├── img_002.jpg
    └── img_003.png
```

The scripts stage images into a `currentset` working directory and write latent/text-encoder cache files alongside them. These are cleaned up at the end of a full run, or left in place after `prepare_dataset_*.bat` so `train_only_*.bat` can reuse them.

---

## Path Configuration

### Where paths are defined

All hardcoded paths are defined as `set` variables at the top of each `.bat` script. There is one consistent location for each type of path:

**ERNIE-Image scripts** — `templates\ernie\*.bat`:

| Variable | Default value | What it points to |
|---|---|---|
| `SOURCE_DATASET_DIR` | `C:\Development\ai-toolkit\datasets\%DATASET_NAME%` | Your source images — **change this if your datasets are elsewhere** |
| `CURRENTSET_DIR` | `C:\Development\trainers\musubi-tuner\datasets\currentset` | Working copy of images |
| `CACHE_DIR` | `C:\Development\trainers\musubi-tuner\datasets\cache` | Latent & text encoder cache |
| `STATUS_FILE` | `C:\Development\trainers\musubi-tuner\datasets\ernie_%DATASET_NAME%.txt` | Training status |
| `DATASET_CONFIG` | `C:\Development\trainers\musubi-tuner\templates\ernie\dataset.currentset.toml` | Dataset TOML |
| `PYTHON_EXE` | `C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe` | venv Python |
| `ERNIE_DIT` | `C:/Development/ComfyUI/models/diffusion_models/Ernie/ernie-image.safetensors` | DiT model |
| `ERNIE_VAE` | `C:/Development/ComfyUI/models/vae/flux2_vae.safetensors` | VAE |
| `ERNIE_TEXT_ENCODER` | `C:/Development/ComfyUI/models/text_encoders/ministral-3-3b.safetensors` | Text encoder |

**LTX-2.3 scripts** — `templates\ltx23\*.bat`:

| Variable | Default value | What it points to |
|---|---|---|
| `SOURCE_DATASET_DIR` | `C:\Development\ai-toolkit\datasets\%DATASET_NAME%` | Your source images — **change this if your datasets are elsewhere** |
| `CURRENTSET_DIR` | `C:\Development\trainers\musubi-tuner\datasets\currentset` | Working copy of images |
| `CACHE_DIR` | `C:\Development\trainers\musubi-tuner\datasets\cache` | Latent & text encoder cache |
| `PYTHON_EXE` | `C:\Development\trainers\musubi-tuner\venv\Scripts\python.exe` | venv Python |
| `LTX2_CHECKPOINT` | `C:/Development/ComfyUI/models/checkpoints/LTX2/ltx-2.3-22b-dev.safetensors` | LTX-2.3 model |
| `GEMMA_SAFETENSORS` | `C:/Development/ComfyUI/models/text_encoders/gemma_3_12B_it_fp8_e4m3fn.safetensors` | Gemma text encoder |

**Dataset TOML files** — `templates\ernie\dataset.currentset.toml` and `templates\ltx23\dataset.currentset.toml`:

| Field | Default value | What it controls |
|---|---|---|
| `image_directory` | `C:/Development/trainers/musubi-tuner/datasets/currentset` | Must match `CURRENTSET_DIR` in the bat files |
| `cache_directory` | `C:/Development/trainers/musubi-tuner/datasets/cache` | Must match `CACHE_DIR` in the bat files |
| `resolution` | `[512, 512]` | Training resolution |
| `num_repeats` | `1` | How many times each image is repeated per epoch |

### Changing paths for your setup

> **All default paths in these scripts reflect malcolmrey's local setup.** If anything lives in a different location on your machine, edit the relevant `set` lines at the top of each `.bat` file before running.

**Dataset location** — the most commonly changed path. If your images are not under `C:\Development\ai-toolkit\datasets\`, update `SOURCE_DATASET_DIR` in every bat file:

```bat
rem Example: datasets stored in D:\training\datasets
set "SOURCE_DATASET_DIR=D:\training\datasets\%DATASET_NAME%"
```

**ComfyUI location** — if your ComfyUI is at a different drive or path, update the model variables. Example for `D:\ComfyUI`:

```bat
set "ERNIE_DIT=D:/ComfyUI/models/diffusion_models/Ernie/ernie-image.safetensors"
set "ERNIE_VAE=D:/ComfyUI/models/vae/flux2_vae.safetensors"
set "ERNIE_TEXT_ENCODER=D:/ComfyUI/models/text_encoders/ministral-3-3b.safetensors"
```

> **Tip:** The bat files use forward slashes (`/`) for Python-facing paths and backslashes (`\`) for Windows shell commands — keep that convention when editing.

If you move the musubi-tuner repo itself, also update `image_directory` and `cache_directory` in both TOML files, and update `CURRENTSET_DIR`, `CACHE_DIR`, `STATUS_FILE`, `DATASET_CONFIG`, and `PYTHON_EXE` in the bat files.

---

## Template Scripts Reference

### ERNIE-Image templates

All scripts live in `templates\ernie\` and are run from anywhere — they `cd` to the repo root automatically.

| Script | Purpose |
|---|---|
| `train_dataset_ernie.bat <name>` | **Full pipeline**: copy images → generate captions → cache latents → cache text encoders → train → clean up |
| `prepare_dataset_ernie.bat <name>` | **Prepare only**: copy images → generate captions → cache latents → cache text encoders (no training, no cleanup) |
| `train_only_ernie.bat <name>` | **Train only**: run training against already-prepared `currentset` and `cache` |

### LTX-2.3 templates

All scripts live in `templates\ltx23\`.

| Script | Purpose |
|---|---|
| `train_dataset_ltx23.bat <name>` | **Full pipeline**: copy images → generate captions → cache latents → cache text encoders → train → clean up |
| `prepare_dataset_ltx23.bat <name>` | **Prepare only**: copy images → generate captions → cache latents → cache text encoders (no training, no cleanup) |
| `train_only_ltx23.bat <name>` | **Train only**: run training against already-prepared `currentset` and `cache` |

---

## Running a Training — Step by Step

### Option A: Full run (prepare + train in one go)

This runs everything end-to-end and cleans up afterward.

**ERNIE-Image:**
```bat
cd C:\Development\trainers\musubi-tuner
templates\ernie\train_dataset_ernie.bat aubreyplaza
```

**LTX-2.3:**
```bat
cd C:\Development\trainers\musubi-tuner
templates\ltx23\train_dataset_ltx23.bat aubreyplaza
```

The output LoRA file will be in `output\` when training completes.

---

### Option B: Prepare once, train multiple times

Useful when you want to experiment with different training parameters without re-running the expensive caching step.

**Step 1 — Prepare the dataset** (copies images, creates captions, caches latents and text encoders):

```bat
templates\ernie\prepare_dataset_ernie.bat aubreyplaza
```

The status file will read `prepared` when done.

**Step 2 — Run training** (reads from existing cache, no copy/cache steps):

```bat
templates\ernie\train_only_ernie.bat aubreyplaza
```

You can re-run Step 2 as many times as you like — just edit training parameters in the bat file between runs. The cache stays valid as long as you don't change the images or resolution.

> **Important:** `train_only_*.bat` does **not** clear or re-prepare `currentset` or `cache`. If you switch to a different dataset, run `prepare_dataset_*.bat` for the new one first — it will wipe the old cache.

---

## Training Parameters

### ERNIE-Image key parameters

Defined inside `train_only_ernie.bat` and `train_dataset_ernie.bat`:

| Parameter | Default | Notes |
|---|---|---|
| `--max_train_epochs` | `100` | Total training epochs. Increase for more training. Start with 20–50 for a quick test |
| `--save_every_n_epochs` | `100` | How often intermediate checkpoints are saved. Set to e.g. `10` to get checkpoints during a long run |
| `--network_dim` | `32` | LoRA rank. Higher = more expressive but more VRAM. Common values: 16, 32, 64 |
| `--network_alpha` | `32` | Should usually match `network_dim` |
| `--learning_rate` | `1e-4` | Learning rate. Lower (e.g. `5e-5`) for more stable training on small datasets |
| `--blocks_to_swap` | `4` | Number of transformer blocks offloaded to CPU. Increase if you get OOM |
| `--fp8_base` | enabled | Quantize base model to fp8. Saves significant VRAM |
| `--optimizer_type` | `adamw8bit` | 8-bit AdamW, memory efficient |
| `--seed` | `42` | Random seed for reproducibility |
| `--output_name` | `ernie_<name>_v1` | Output filename (without extension) |

### LTX-2.3 key parameters

Defined inside `train_only_ltx23.bat` and `train_dataset_ltx23.bat`:

| Parameter | Default | Notes |
|---|---|---|
| `--max_train_epochs` | `120` | Total training epochs |
| `--save_every_n_epochs` | `120` | Checkpoint save frequency |
| `--network_dim` | `32` | LoRA rank |
| `--network_alpha` | `32` | Should usually match `network_dim` |
| `--learning_rate` | `1e-4` | Learning rate |
| `--lr_warmup_steps` | `100` | Linear warmup steps at training start |
| `--blocks_to_swap` | `4` | Increase if you get OOM (LTX-2.3 is 22B, needs more swapping than ERNIE) |
| `--lora_target_preset` | `video_sa_ca_ff` | Which layers to apply LoRA to |
| `--timestep_sampling` | `shifted_logit_normal` | Timestep distribution for training |
| `--output_name` | `ltx23_<name>_v1` | Output filename |

**Resolution:** Edit `templates\ltx23\dataset.currentset.toml` (or `templates\ernie\dataset.currentset.toml`):
```toml
[general]
resolution = [512, 512]   # change to e.g. [768, 768] or [1024, 1024]
```

Higher resolution needs more VRAM and longer caching. Re-run `prepare_dataset_*.bat` after changing resolution — the old cache is invalid.

---

## Output Files

Trained LoRA files are saved to:

```
C:\Development\trainers\musubi-tuner\output\
    ernie_aubreyplaza_v1.safetensors         ← final model
    ernie_aubreyplaza_v1-step-XXXXX.safetensors  ← intermediate (if save_every_n_epochs < max_train_epochs)
```

To use in ComfyUI, copy the `.safetensors` file to:
- **ERNIE:** `ComfyUI\models\loras\Ernie\`
- **LTX-2.3:** `ComfyUI\models\loras\LTX2\` (or wherever your LTX loras live)

---

## Status Files

Each script writes a status file to `datasets\` so automated tools (like sd-backend) can track progress:

| Value | Meaning |
|---|---|
| `starting` | Validation passed, about to begin |
| `prepared` | Dataset staged and cached, ready for `train_only_*.bat` |
| `running` | Training in progress |
| `finished` | Completed successfully |
| `errored` | A step failed — check console output for details |

Status file location:
- ERNIE: `datasets\ernie_<name>.txt`
- LTX-2.3: `datasets\ltx23_<name>.txt`

---

## Troubleshooting

**`[ERROR] Python executable not found`**
→ The venv hasn't been created yet, or is in a different location. Run the [Repository Setup](#repository-setup) steps, or update `PYTHON_EXE` in the bat file.

**`[ERROR] Dataset directory not found`**
→ The source dataset folder doesn't exist at the expected path. Check `SOURCE_DATASET_DIR` in the bat file and create the folder with your images in it.

**`[ERROR] No supported image files found`**
→ The source folder exists but contains no `.png`/`.jpg`/`.jpeg`/`.webp`/`.bmp`/`.avif`/`.jxl` files.

**`[ERROR] Latent caching failed`**
→ Usually a model path issue (model file not found) or VRAM OOM. Check that the model path variables point to existing files. For OOM, the caching scripts run on CPU by default in the config; the `--device cuda` flag moves them to GPU for speed.

**`TypeError: enable_gradient_checkpointing() got an unexpected keyword argument 'blocks_to_checkpoint'`**
→ This was a known issue with the ERNIE-Image trainer. Make sure you are using the version of musubi-tuner that has the ERNIE fixes applied (this fork).

**OOM during training**
→ Increase `--blocks_to_swap` (try `8` or `12`). Lower `--network_dim`. Reduce resolution in the TOML. For LTX-2.3, the model is 22B parameters — even with fp8 and block swap, 12 GB VRAM is very tight; 16–24 GB is recommended.

**Cache from a previous dataset is being used**
→ If you switch datasets without running `prepare_dataset_*.bat`, the old cache will still be there. `prepare_dataset_*.bat` clears `currentset` and `cache` at the start — run it for the new dataset before training.

**Output LoRA file is empty / very small**
→ Training likely errored before saving. Check the status file and console output. Common cause: `--max_train_epochs` was reached before a checkpoint was written because `--save_every_n_epochs` was set equal to `--max_train_epochs` and training failed partway through. Lower `save_every_n_epochs` to get partial saves.
