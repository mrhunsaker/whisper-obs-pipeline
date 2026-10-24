# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-24

First public release.

### Added

- Batch transcription of every WAV file in a folder with whisper.cpp, producing TXT, SRT, VTT, JSON, CSV, LRC and karaoke-script (`words`) outputs, selectable with `--outputs`.
- `--convert`: ffmpeg conversion of mp4, mkv, mov, webm, m4a, mp3, aac, flac, ogg and opus to 16 kHz mono WAV, run in parallel (`--jobs`), skipping WAVs that are already up to date, and written atomically.
- Interactive model menu that lists only the models actually downloaded, with a download hint when a model is missing.
- **Speaker-split mode** (`--split-speakers`) for OBS recordings:
  - Separates the microphone and desktop/screen-reader audio from separate audio tracks, or from the left and right channels of a single stereo stream.
  - Transcribes each source and merges the results by time into `name.merged.txt` and `name.merged.srt` with a label before each line (default `[MRH]` and `[NVDA]`).
  - `--mic-track`, `--nvda-track`, `--mic-label` and `--nvda-label` options.
  - Defaults to `ggml-large-v3.bin`.
  - Uses a Silero VAD model automatically when one is present, and warns when none is.
  - Remembers the track mapping, so changing it re-splits and re-transcribes.
- `--to-mp4` / `--no-mp4`: remux `.mkv` to `.mp4` without re-encoding, keeping all audio tracks (audio falls back to AAC when the codec cannot be stored in MP4). Implied by `--split-speakers`.
- `--prompt`: asks for an initial prompt after model selection and passes it to whisper, adding `--carry-initial-prompt` when the build supports it.
- Options for `--language`, `--device`, `--no-gpu`, `--threads`, `--beam-size`, `--vad-model` and `--force`.
- Skips files that are already transcribed, prints per-file timing and a final summary, and exits non-zero if any file fails to convert, remux or transcribe.
- Documentation (`README.md`, `docs/`), an end-to-end smoke test (`tests/smoke-test.sh`) and CI.

### Security

- Paths are expanded without `eval`, so file and folder names cannot inject commands.

[Unreleased]: https://github.com/<your-username>/whisper-obs-pipeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<your-username>/whisper-obs-pipeline/releases/tag/v0.1.0
