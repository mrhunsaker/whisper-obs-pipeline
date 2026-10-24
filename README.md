# whisper-obs-pipeline

Batch-transcribe screen recordings with [whisper.cpp](https://github.com/ggml-org/whisper.cpp), with an optional **speaker-split mode** for OBS recordings that have separate microphone and desktop-audio (for example, screen reader) tracks. The result is one transcript with a label before every line:

```
[MRH] Okay, I'm starting on the worksheet now.
[NVDA] Heading level one, Beginning Worksheet.
[NVDA] Link, Question one.
[MRH] Let me open the first question.
```

It is a single Bash script. The only Python used is the standard-library `python3` that ships with Linux, to merge transcripts; there is nothing to `pip install`.

## What it does

- Converts video or audio files to 16 kHz mono WAV with ffmpeg (the format whisper.cpp wants).
- Transcribes every file in a folder with whisper.cpp, producing TXT, SRT, VTT, JSON, CSV and LRC.
- **Speaker-split mode:** separates the mic track from the desktop-audio track, transcribes each on its own, and merges them by timestamp with labels (default `[MRH]` and `[NVDA]`, configurable).
- Optionally remuxes `.mkv` recordings to `.mp4` (no re-encode, all audio tracks kept) so they play in more players.
- Skips work that is already done, so you can re-run it safely after a failure.

## Repository layout

```
whisper-obs-pipeline/
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── LICENSE
├── .editorconfig
├── .gitignore
├── .github/
│   ├── workflows/ci.yml           # syntax check, ShellCheck, smoke test
│   ├── ISSUE_TEMPLATE/            # bug report and feature request forms
│   └── PULL_REQUEST_TEMPLATE.md
├── scripts/
│   └── whisperCPPPipeline.sh      # the pipeline
├── tests/
│   └── smoke-test.sh              # end-to-end test (stub whisper-cli, no GPU or models)
├── docs/
│   ├── setup-whisper-cpp.md       # build whisper.cpp, download models
│   └── obs-recording.md           # configure OBS for two audio tracks
└── examples/
    ├── sample-merged.txt          # what split-mode output looks like
    └── sample-merged.srt
```

## Requirements

| Tool | Used for |
|---|---|
| [whisper.cpp](docs/setup-whisper-cpp.md), built | transcription (`build/bin/whisper-cli`) |
| a Whisper model (`ggml-*.bin`) | split mode defaults to `ggml-large-v3.bin` |
| `ffmpeg` | audio extraction and MKV to MP4 remux |
| `python3` (standard library only) | merging the two transcripts in split mode |
| `bash` 4.4+, `find`, `xargs`, `realpath` | the script itself (standard on Linux) |

If you want to *play* H.264 video files with ffmpeg-based tools, use an ffmpeg build with H.264 decoding. Audio extraction and remuxing do not decode video.

## Quick start

```bash
git clone https://github.com/<your-username>/whisper-obs-pipeline.git
cd whisper-obs-pipeline
```

1. **Set up whisper.cpp and download a model:** see [docs/setup-whisper-cpp.md](docs/setup-whisper-cpp.md).
2. **Record with two audio tracks in OBS:** see [docs/obs-recording.md](docs/obs-recording.md).
3. **Run the pipeline:**

```bash
./scripts/whisperCPPPipeline.sh --split-speakers \
  --folder-home ~/Videos/recordings \
  --whisper-home ~/whisper.cpp
```

If you leave out `--folder-home` or `--whisper-home`, the script asks for them. Without `--split-speakers` and `--model`, it shows a menu of the models you have downloaded.

## Modes

### Normal mode

One transcript per file. Convert video to WAV first if needed:

```bash
./scripts/whisperCPPPipeline.sh --convert \
  --folder-home ~/Videos/recordings \
  --whisper-home ~/whisper.cpp \
  --model ggml-medium.en.bin
```

Files that are already WAV are used as they are. Outputs are written next to each input (`name.txt`, `name.srt`, and so on).

### Speaker-split mode

For OBS recordings with the mic and the desktop audio (for example NVDA) on separate tracks.

```bash
./scripts/whisperCPPPipeline.sh --split-speakers \
  --folder-home ~/Videos/recordings \
  --whisper-home ~/whisper.cpp
```

What happens for each recording:

1. ffmpeg writes `name.mic.wav` and `name.nvda.wav` in a single pass.
2. whisper.cpp transcribes each one separately (large-v3 unless you pass `--model`).
3. The two transcripts are merged by start time into `name.merged.txt` and `name.merged.srt`, with a label before each line. See [examples/](examples/).
4. The `.mkv` is remuxed to `.mp4` (turn off with `--no-mp4`).

Output files in split mode:

| File | Contents |
|---|---|
| `name.merged.txt` | labeled lines, no timestamps |
| `name.merged.srt` | the same lines with timestamps |
| `name.mic.json`, `name.nvda.json` | per-channel transcripts with timestamps |
| `name.mic.wav`, `name.nvda.wav` | the separated audio |
| `name.split-tracks` | remembers which tracks were used, so changing them re-splits |
| `name.mp4` | remuxed copy of an `.mkv` (all audio tracks kept) |

Notes:

- `--outputs` is ignored in split mode; the merged files are the deliverable.
- Bracketed annotations such as `[BLANK_AUDIO]` or `(silence)` are dropped when merging.

**Which track is which.** `--mic-track` and `--nvda-track` are 0-based. If the file has two or more audio streams (OBS tracks), they pick streams. If it has one stereo stream, they pick channels (0 = left, 1 = right). The defaults are mic = 0 and NVDA = 1. If you use the "mix plus split" layout from the [OBS guide](docs/obs-recording.md), the first stream is the full mix, so run with `--mic-track 1 --nvda-track 2`. If the labels come out swapped, rerun with the numbers reversed; the script re-splits automatically.

## Options

| Option | Description |
|---|---|
| `--folder-home PATH` | Folder containing the media or WAV files |
| `--whisper-home PATH` | whisper.cpp directory (must contain `build/bin/whisper-cli`) |
| `--model NAME` | Model filename in `<whisper-home>/models`, or a full path |
| `--convert` | Convert mp4, mkv, mov, webm, m4a, mp3, aac, flac, ogg and opus to 16 kHz mono WAV |
| `--split-speakers` | Speaker-split mode (implies `--convert` and `--to-mp4`) |
| `--mic-track N` / `--nvda-track N` | Which stream or channel is the mic / the desktop audio (default 0 / 1) |
| `--mic-label TEXT` / `--nvda-label TEXT` | Labels in the merged transcript (default `MRH` / `NVDA`) |
| `--to-mp4` / `--no-mp4` | Remux `.mkv` to `.mp4` without re-encoding / turn that off |
| `--prompt` | After model selection, ask for an initial prompt to pass to whisper |
| `--language LANG` | Language code, or `auto` (default `en`) |
| `--device N` | GPU device index (default: whisper.cpp's default) |
| `--no-gpu` | Force CPU-only inference |
| `--threads N` | CPU threads |
| `--beam-size N` | Beam size; `1` is much faster and lighter than the default 5 |
| `--vad-model PATH` | Enable voice activity detection with this model |
| `--outputs LIST` | Normal mode only: any of `txt,srt,vtt,json,json-full,csv,lrc,words` |
| `--font-path PATH` | Font for the `words` output |
| `--jobs N` | Parallel ffmpeg conversions (default: up to 4) |
| `--force` | Redo conversions and transcripts even if outputs exist |
| `-h`, `--help` | Show help |

The `words` output is whisper.cpp's karaoke-script feature (`.wts`). It needs a font, and the script skips it with a warning if the font file is not found.

## Tips

- **Use a VAD model in split mode.** Each channel is silent while the other speaker talks, and Whisper tends to invent text on silence. If a Silero model such as `ggml-silero-v5.1.2.bin` is in `<whisper-home>/models`, the script uses it automatically. Download steps are in [docs/setup-whisper-cpp.md](docs/setup-whisper-cpp.md).
- **The prompt is a vocabulary hint, not an instruction.** `--prompt` is good for names and jargon (`NVDA, JAWS, ARIA`). It will not reliably make Whisper insert speaker labels; that is what split mode is for.
- **Faster runs:** use `ggml-large-v3-turbo.bin` and/or `--beam-size 1`.
- **Re-runs are cheap.** Finished conversions and transcripts are skipped unless the input is newer, the track mapping changed, or you pass `--force`.
- **One failed file does not stop the batch.** The script prints a summary and exits non-zero if anything failed.

## Limitations

- Split mode needs the sources on **separate tracks or channels** at recording time. A recording where everything was mixed into one track cannot be separated afterward.
- If the desktop audio leaks into the mic (speakers instead of headphones), the same speech appears under both labels.
- Anything else you put on the mic or desktop track (browser, music) is transcribed under that label.
- Timestamps are segment-level. Overlapping speech from both sources is interleaved by start time.

## Troubleshooting

| Message or symptom | Cause and fix |
|---|---|
| `has a single mono audio stream ... cannot split` | OBS wrote one mixed track. Set up two tracks as described in [docs/obs-recording.md](docs/obs-recording.md). |
| `track index out of range` | The file has fewer audio streams than `--mic-track` / `--nvda-track` expects. Check with `ffmpeg -i file.mkv`. |
| `ffmpeg found no audio stream` | The file has no audio, or ffmpeg cannot read it. |
| Labels are swapped | Rerun with `--mic-track` and `--nvda-track` reversed. |
| Both labels show the same text | Both sources were on the same track, or the mic is picking up the desktop audio. |
| Repeated "Thank you." or similar on silence | Add a VAD model (see Tips). |
| `No WAV files found` | Pass `--convert` (or `--split-speakers`) so media files are converted first. |
| Out of GPU memory | Use a smaller model, `--beam-size 1`, or `--no-gpu`. The script runs one processor at a time. |
| Nothing happens on a re-run | Outputs are up to date. Use `--force` to redo them. |

## Contributing and support

Bug reports and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in [SECURITY.md](SECURITY.md). Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

To check your changes locally (no GPU or models needed):

```bash
shellcheck scripts/whisperCPPPipeline.sh tests/smoke-test.sh
bash tests/smoke-test.sh
```

## License

MIT. See [LICENSE](LICENSE).
