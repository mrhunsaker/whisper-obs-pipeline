# Setting up whisper.cpp

The pipeline calls `build/bin/whisper-cli` from a whisper.cpp checkout, so you need to build it once and download at least one model. Upstream documentation: <https://github.com/ggml-org/whisper.cpp>.

## 1. Install build tools

Debian / Ubuntu:

```bash
sudo apt install git build-essential cmake ffmpeg python3
```

Fedora / RHEL family:

```bash
sudo dnf install git cmake gcc-c++ python3
# ffmpeg: install a full build (on Fedora and RHEL-family systems this typically
# comes from RPM Fusion; the stock ffmpeg-free package cannot decode H.264)
```

macOS (Homebrew): `brew install git cmake ffmpeg`.

## 2. Get the source

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp
```

The examples in this repo use `~/whisper.cpp`. Use any path you like and pass it as `--whisper-home`.

## 3. Build

Pick **one** backend. CPU-only works everywhere but is slow for large models.

**CPU only**

```bash
cmake -B build
cmake --build build -j --config Release
```

**NVIDIA GPU (CUDA)**

```bash
cmake -B build -DGGML_CUDA=1
cmake --build build -j --config Release
```

**AMD GPU (ROCm / HIP)**

Find your GPU architecture first (for example `gfx1102`) and pass it as the target:

```bash
rocminfo | grep gfx
cmake -B build -DGGML_HIP=1 -DAMDGPU_TARGETS="gfx1102"
cmake --build build -j --config Release
```

List several targets separated by semicolons (`"gfx1102;gfx1103"`) if you want the binary to run on more than one GPU. A binary only runs on the architectures it was built for.

**Any GPU with Vulkan** (needs the Vulkan headers and the `glslc` shader compiler)

```bash
cmake -B build -DGGML_VULKAN=1
cmake --build build -j --config Release
```

**macOS (Apple Silicon)**

Metal is used automatically; the CPU build command above is enough.

Add `-DGGML_CCACHE=OFF` to the first `cmake` command if you want to silence the "ccache not found" notice.

## 4. Download models

From the whisper.cpp directory:

```bash
./models/download-ggml-model.sh large-v3          # used by --split-speakers
./models/download-ggml-model.sh large-v3-turbo    # faster, slightly less accurate
./models/download-ggml-model.sh base.en           # small and quick for testing
```

Models range from about 75 MB (`tiny`) to about 3 GB (`large-v3`). The `.en` models are English-only and faster; the `large` models are multilingual. The files land in `models/` as `ggml-<name>.bin`, which is where the pipeline looks for them.

### Voice activity detection (recommended for split mode)

A small Silero VAD model lets whisper skip silence, which avoids invented text on silent channels:

```bash
./models/download-vad-model.sh silero-v5.1.2
```

Run the script with no arguments to see the other available names. The pipeline picks up any `ggml-silero*.bin` in `models/` automatically in split mode, or you can pass one with `--vad-model`.

## 5. Check the build

```bash
./build/bin/whisper-cli -h | head
./build/bin/whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav
```

With a GPU backend, the log near the top lists the detected devices (for example `ggml_cuda_init: found 1 ROCm devices`). If it lists several, `--device N` in the pipeline selects one using the same numbering.

## 6. Point the pipeline at it

```bash
./scripts/whisperCPPPipeline.sh --split-speakers \
  --folder-home ~/Videos/recordings \
  --whisper-home ~/whisper.cpp
```

The script checks that `build/bin/whisper-cli` and the model exist before it starts, and prints the download command if a model is missing.

## Updating

```bash
cd ~/whisper.cpp
git pull
cmake --build build -j --config Release
```

Re-run the `cmake -B build ...` line with your backend flags first if the update changes build options.
