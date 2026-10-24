#!/usr/bin/env bash
#
# whisperCPPPipeline.sh - batch-convert and transcribe media with whisper.cpp
#
# Normal mode : one transcript per file.
# Split mode  : (--split-speakers) separates the mic and desktop-audio tracks
#               of OBS recordings, transcribes each, and merges them by time
#               into a transcript with [MRH] / [NVDA] style speaker labels.
#
set -Eeuo pipefail

prog=${0##*/}
ncpu=$(nproc 2>/dev/null || echo 2)

folder_home=""
whisper_home=""
model_name=""
convert_audio=false
ask_prompt=false
initial_prompt=""
language="en"
device=""
threads=""
beam_size=""
vad_model=""
no_gpu=false
force=false
split_speakers=false
convert_failed=false
to_mp4=""
mic_track=0
nvda_track=1
mic_label="MRH"
nvda_label="NVDA"
jobs=$(( ncpu > 4 ? 4 : ncpu ))
outputs="txt,srt,vtt,json-full,csv,lrc,words"
font_path="$HOME/.local/share/fonts/AtkynsonMonoNerdFont-Regular.otf"

usage() {
cat <<EOF
Usage:
  $prog [options]

Options:
  --folder-home PATH     Folder containing media/WAV files
  --whisper-home PATH    whisper.cpp directory
  --model MODEL          Model filename (in <whisper-home>/models) or a full path
  --convert              Convert video/audio files (mp4, mkv, mov, m4a, mp3, ...)
                         to 16 kHz mono WAV with ffmpeg (skips up-to-date WAVs)
  --to-mp4               Remux each .mkv to a same-named .mp4 (no re-encode; all
                         audio tracks kept) so it plays in VLC and other players.
                         The .mkv is kept. Implied by --split-speakers.
  --no-mp4               Turn off the MP4 remux, even with --split-speakers
  --prompt               After model selection, ask for an initial prompt to pass
                         to whisper (vocabulary/style hint, not an instruction)
  --language LANG        Spoken language code, or "auto" (default: en)
  --device N             GPU device index (default: whisper.cpp's default, 0)
  --no-gpu               Force CPU-only inference
  --threads N            CPU threads (default: whisper.cpp's default)
  --beam-size N          Beam size; 1 = greedy, much faster/lighter (default: 5)
  --vad-model PATH       Enable VAD with this model (skips silence; strongly
                         recommended with --split-speakers)
  --outputs LIST         Comma-separated: txt,srt,vtt,json,json-full,csv,lrc,words
                         (default: $outputs; ignored by --split-speakers)
  --font-path PATH       Font used for the "words" output
  --jobs N               Parallel ffmpeg conversions (default: $jobs)
  --force                Re-transcribe even if output already exists
  -h, --help             Show help

Speaker-split mode (OBS: mic capture + desktop/screen-reader audio capture):
  --split-speakers       Implies --convert. Writes <name>.mic.wav and
                         <name>.nvda.wav, transcribes both, and writes
                         <name>.merged.txt and <name>.merged.srt with a label
                         before each line, plus <name>.mic.json / .nvda.json.
                         Uses ggml-large-v3.bin unless --model is given.
  --mic-track N          Where the microphone is (default: $mic_track)
  --nvda-track N         Where the screen reader/desktop audio is (default: $nvda_track)
                         N is the 0-based audio stream if the file has 2+ audio
                         streams (OBS tracks), or the channel (0=left, 1=right)
                         if it has one multi-channel stream.
  --mic-label TEXT       Label for the human speaker (default: $mic_label)
  --nvda-label TEXT      Label for the screen reader (default: $nvda_label)

Example:
  $prog \\
    --folder-home ~/Videos/recordings \\
    --whisper-home ~/whisper.cpp \\
    --model ggml-large-v3-turbo.bin \\
    --split-speakers --device 0

Download a model first, e.g.:
  cd ~/whisper.cpp && ./models/download-ggml-model.sh large-v3-turbo
EOF
}

die()  { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

# Safe ~ expansion (no eval), absolute path, no trailing slash.
expand_path() {
    local p=$1
    p=${p/#\~/$HOME}
    realpath -m -- "$p"
}

###############################################################################
# Parse command-line arguments
###############################################################################

need_val() { [[ $# -ge 2 && -n ${2:-} ]] || die "$1 requires a value"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder-home)  need_val "$@"; folder_home=$2; shift 2 ;;
        --whisper-home) need_val "$@"; whisper_home=$2; shift 2 ;;
        --model)        need_val "$@"; model_name=$2; shift 2 ;;
        --language)     need_val "$@"; language=$2; shift 2 ;;
        --device)       need_val "$@"; device=$2; shift 2 ;;
        --threads)      need_val "$@"; threads=$2; shift 2 ;;
        --beam-size)    need_val "$@"; beam_size=$2; shift 2 ;;
        --vad-model)    need_val "$@"; vad_model=$2; shift 2 ;;
        --outputs)      need_val "$@"; outputs=$2; shift 2 ;;
        --font-path)    need_val "$@"; font_path=$2; shift 2 ;;
        --jobs)         need_val "$@"; jobs=$2; shift 2 ;;
        --mic-track)    need_val "$@"; mic_track=$2; shift 2 ;;
        --nvda-track)   need_val "$@"; nvda_track=$2; shift 2 ;;
        --mic-label)    need_val "$@"; mic_label=$2; shift 2 ;;
        --nvda-label)   need_val "$@"; nvda_label=$2; shift 2 ;;
        --convert)      convert_audio=true; shift ;;
        --prompt)       ask_prompt=true; shift ;;
        --split-speakers) split_speakers=true; shift ;;
        --to-mp4)       to_mp4=true; shift ;;
        --no-mp4)       to_mp4=false; shift ;;
        --no-gpu)       no_gpu=true; shift ;;
        --force)        force=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 1 ;;
    esac
done

###############################################################################
# Prompt for missing values (interactive only)
###############################################################################

if [[ -z $folder_home ]]; then
    [[ -t 0 ]] || die "--folder-home is required when not running interactively"
    read -erp "Folder containing media files: " folder_home
fi

if [[ -z $whisper_home ]]; then
    [[ -t 0 ]] || die "--whisper-home is required when not running interactively"
    read -erp "Path to whisper.cpp: " whisper_home
fi

folder_home=$(expand_path "$folder_home")
whisper_home=$(expand_path "$whisper_home")

[[ -d $folder_home ]] || die "Folder not found: $folder_home"
cli="$whisper_home/build/bin/whisper-cli"
[[ -x $cli ]] || die "whisper-cli not found at $cli (build whisper.cpp first)"

# Split-speaker mode defaults to large-v3 (no menu); --model still overrides.
if [[ -z $model_name && $split_speakers == true ]]; then
    model_name="ggml-large-v3.bin"
    echo "Split-speaker mode: using $model_name (override with --model)"
fi

# Offer only the models that are actually downloaded.
if [[ -z $model_name ]]; then
    [[ -t 0 ]] || die "--model is required when not running interactively"
    mapfile -t available < <(
        if cd "$whisper_home/models" 2>/dev/null; then
            compgen -G 'ggml-*.bin' | grep -Ev 'for-tests|silero' | sort || true
        fi
    )
    [[ ${#available[@]} -gt 0 ]] ||
        die "No models in $whisper_home/models. Run: ./models/download-ggml-model.sh large-v3-turbo"
    echo
    echo "Select a Whisper model:"
    select model_name in "${available[@]}"; do
        [[ -n $model_name ]] && break
        echo "Invalid selection."
    done
fi

if [[ $model_name == */* ]]; then
    model_path=$(expand_path "$model_name")
else
    model_path="$whisper_home/models/$model_name"
fi
if [[ ! -f $model_path ]]; then
    short=${model_name##*/}; short=${short#ggml-}; short=${short%.bin}
    die "Model not found: $model_path
       Download with: (cd \"$whisper_home\" && ./models/download-ggml-model.sh $short)"
fi

if [[ $model_path == *.en.bin && $language != en ]]; then
    warn "'.en' models are English-only but --language is '$language'"
fi
if [[ -n ${ROCR_VISIBLE_DEVICES:-} || -n ${HIP_VISIBLE_DEVICES:-} || -n ${GGML_VK_VISIBLE_DEVICES:-} ]]; then
    warn "GPU visibility env vars are set (ROCR/HIP/GGML_VK_VISIBLE_DEVICES); they change which GPUs whisper sees"
fi

###############################################################################
# Optional initial prompt (asked after the model is chosen)
###############################################################################

if [[ $ask_prompt == true ]]; then
    [[ -t 0 ]] || die "--prompt needs an interactive terminal"
    echo
    echo "Initial prompt: text whisper treats as preceding context (names, jargon, style)."
    echo "It biases the output; it does not follow instructions. Leave blank for none."
    read -erp "Prompt: " initial_prompt
    if (( ${#initial_prompt} > 800 )); then
        warn "prompt is long; whisper only uses roughly the last 220 tokens of it"
    fi
fi

###############################################################################
# Speaker-split mode checks
###############################################################################

if [[ $split_speakers == true ]]; then
    convert_audio=true
    if [[ -z $to_mp4 ]]; then to_mp4=true; fi
    command -v python3 >/dev/null || die "python3 is required to merge the two transcripts"
    [[ $mic_track =~ ^[0-9]+$ && $nvda_track =~ ^[0-9]+$ ]] ||
        die "--mic-track and --nvda-track must be non-negative integers"
    [[ $mic_track != "$nvda_track" ]] || die "--mic-track and --nvda-track must differ"

    # A silent channel makes whisper hallucinate text, so VAD matters here.
    if [[ -z $vad_model ]]; then
        vad_guess=$(compgen -G "$whisper_home/models/ggml-silero*.bin" | sort | tail -n1 || true)
        if [[ -n $vad_guess ]]; then
            vad_model=$vad_guess
            echo "Using VAD model: $vad_model"
        else
            warn "no VAD model found; silent stretches on each channel may produce hallucinated text."
            warn "Get one with: (cd \"$whisper_home\" && ./models/download-vad-model.sh silero-v5.1.2)"
        fi
    fi
fi

###############################################################################
# Build whisper-cli arguments
###############################################################################

args=(--model "$model_path" --language "$language")

if [[ $no_gpu == true ]]; then args+=(--no-gpu); fi
if [[ -n $threads ]];     then args+=(--threads "$threads"); fi
if [[ -n $beam_size ]];   then args+=(--beam-size "$beam_size"); fi
if [[ -t 1 ]];            then args+=(--print-colors); fi

if [[ -n $vad_model ]]; then
    vad_model=$(expand_path "$vad_model")
    [[ -f $vad_model ]] || die "VAD model not found: $vad_model"
    args+=(--vad --vad-model "$vad_model")
fi

if [[ -n $device ]]; then
    if "$cli" --help 2>&1 | grep -q -- '--device'; then
        args+=(--device "$device")
    else
        warn "this whisper-cli has no --device flag; ignoring --device $device"
    fi
fi

if [[ -n $initial_prompt ]]; then
    args+=(--prompt "$initial_prompt")
    # Newer builds can re-apply the prompt to every 30 s window, not just the first.
    if "$cli" --help 2>&1 | grep -q -- '--carry-initial-prompt'; then
        args+=(--carry-initial-prompt)
    fi
fi

if [[ -z $to_mp4 ]]; then to_mp4=false; fi

# Output flags (kept separate so split mode can use its own).
out_args=()
marker_ext=""
if [[ $split_speakers == true ]]; then
    out_args=(--output-json)     # per-channel JSON feeds the merge step
    marker_ext="merged.txt"
else
    IFS=',' read -ra out_list <<<"$outputs"
    for o in "${out_list[@]}"; do
        case "$o" in
            txt)       out_args+=(--output-txt);       ext=txt ;;
            srt)       out_args+=(--output-srt);       ext=srt ;;
            vtt)       out_args+=(--output-vtt);       ext=vtt ;;
            json)      out_args+=(--output-json);      ext=json ;;
            json-full) out_args+=(--output-json-full); ext=json ;;
            csv)       out_args+=(--output-csv);       ext=csv ;;
            lrc)       out_args+=(--output-lrc);       ext=lrc ;;
            words)
                if [[ -f $font_path ]]; then
                    out_args+=(--output-words --font-path "$font_path"); ext=wts
                else
                    warn "font not found ($font_path); skipping 'words' output"
                    continue
                fi
                ;;
            *) die "Unknown output type: $o" ;;
        esac
        if [[ -z $marker_ext ]]; then marker_ext=$ext; fi
    done
    [[ -n $marker_ext ]] || die "No outputs selected"
fi

###############################################################################
# Summary
###############################################################################

echo
echo "Configuration"
echo "-------------"
echo "Folder Home : $folder_home"
echo "Whisper Home: $whisper_home"
echo "Model       : $model_path"
echo "Language    : $language"
echo "Device      : $([[ $no_gpu == true ]] && echo CPU || echo "GPU ${device:-default}")"
if [[ $split_speakers == true ]]; then
    echo "Mode        : split speakers ([$mic_label] = track/channel $mic_track, [$nvda_label] = track/channel $nvda_track)"
else
    echo "Outputs     : $outputs"
fi
echo "Convert     : $convert_audio"
echo "MKV -> MP4   : $to_mp4"
echo "Prompt      : ${initial_prompt:-<none>}"
echo

###############################################################################
# Conversion helpers (exported so xargs can run them in parallel)
###############################################################################

# ffmpeg builds that decode H.264 through Cisco OpenH264 print "Unable to create
# decoder" when that library is missing. We never decode video, so it's noise.
ff_filter() { grep -vE 'libopenh264|Unable to create decoder|Last message repeated' || true; }

# Number of audio streams in a file. Uses ffmpeg only (ffprobe can fail outright
# on files whose video decoder is unavailable): a stream "exists" if mapping it works.
count_audio_streams() {
    local src=$1 k=0
    while (( k < 16 )) && ffmpeg -nostdin -v quiet -i "$src" -map "0:a:$k" \
            -t 0.05 -f null - >/dev/null 2>&1; do
        k=$((k + 1))
    done
    echo "$k"
}

# Lists media files for audio conversion (NUL-separated). A same-named .mp4 next
# to an .mkv is that file's remux, so it is skipped to avoid duplicate work.
list_media() {
    local f
    local -a find_expr=()
    for e in mp4 mkv mov webm m4a mp3 aac flac ogg opus; do
        find_expr+=(-o -iname "*.$e")
    done
    unset 'find_expr[0]'   # drop the leading -o
    while IFS= read -r -d '' f; do
        if [[ ${f,,} == *.mp4 && -e ${f%.*}.mkv ]]; then continue; fi
        printf '%s\0' "$f"
    done < <(find "$folder_home" -maxdepth 1 -type f \( "${find_expr[@]}" \) -print0)
}

# <name>.mkv -> <name>.mp4 without re-encoding. Keeps every video and audio
# track (OBS multi-track audio) and moves the index to the front for easy playback.
# If an audio codec cannot live in MP4 (e.g. PCM), audio is re-encoded to AAC and
# the video stream is still copied untouched.
remux_one() {
    local src=$1 dst tmp err
    dst="${src%.*}.mp4"
    tmp="$dst.part"
    if [[ ${FORCE:-false} != true && -s $dst && $dst -nt $src ]]; then
        echo "Skipping (MP4 up to date): ${src##*/}"
        return 0
    fi
    echo "Remuxing to MP4: ${src##*/}"
    if err=$(ffmpeg -nostdin -hide_banner -loglevel error -y -i "$src" \
            -map '0:v?' -map '0:a?' -c copy -movflags +faststart -f mp4 "$tmp" 2>&1); then
        mv -f -- "$tmp" "$dst"
    elif err=$(ffmpeg -nostdin -hide_banner -loglevel error -y -i "$src" \
            -map '0:v?' -map '0:a?' -c:v copy -c:a aac -b:a 192k -movflags +faststart -f mp4 "$tmp" 2>&1); then
        mv -f -- "$tmp" "$dst"
        echo "  (audio re-encoded to AAC: ${src##*/})"
    else
        rm -f -- "$tmp"
        echo "MP4 remux failed: ${src##*/}" >&2
        printf '%s\n' "$err" | ff_filter >&2
        return 1
    fi
}

# Single track -> <name>.wav (16 kHz mono)
convert_one() {
    local src=$1 dst tmp err
    dst="${src%.*}.wav"
    tmp="$dst.part"
    if [[ ${FORCE:-false} != true && -s $dst && $dst -nt $src ]]; then
        echo "Skipping (WAV up to date): ${src##*/}"
        return 0
    fi
    echo "Converting: ${src##*/}"
    if err=$(ffmpeg -nostdin -hide_banner -loglevel error -y \
            -i "$src" -vn -ar 16000 -ac 1 -c:a pcm_s16le -f wav "$tmp" 2>&1); then
        mv -f -- "$tmp" "$dst"
    else
        rm -f -- "$tmp"
        echo "ffmpeg failed: ${src##*/}" >&2
        printf '%s\n' "$err" | ff_filter >&2
        return 1
    fi
}

# Two sources -> <name>.mic.wav and <name>.nvda.wav (16 kHz mono each).
# Uses separate audio streams (OBS tracks) if present, otherwise splits the
# channels of a single stereo stream. Needs MIC_TRACK / NVDA_TRACK.
convert_split_one() {
    local src=$1 base mic nv map err n_streams layout
    base="${src%.*}"
    mic="$base.mic.wav"
    nv="$base.nvda.wav"
    map="$base.split-tracks"   # remembers which tracks were used

    if [[ ${FORCE:-false} != true && -s $mic && -s $nv && $mic -nt $src && $nv -nt $src \
          && "$(cat "$map" 2>/dev/null)" == "mic=$MIC_TRACK nvda=$NVDA_TRACK" ]]; then
        echo "Skipping (split WAVs up to date): ${src##*/}"
        return 0
    fi

    n_streams=$(count_audio_streams "$src")

    local -a maps
    if (( n_streams >= 2 )); then
        if (( MIC_TRACK >= n_streams || NVDA_TRACK >= n_streams )); then
            echo "Error: ${src##*/} has $n_streams audio streams; track index out of range" >&2
            return 1
        fi
        echo "Splitting: ${src##*/} ($n_streams audio streams: mic=a:$MIC_TRACK, nvda=a:$NVDA_TRACK)"
        maps=( -vn -map "0:a:$MIC_TRACK"  -ar 16000 -ac 1 -c:a pcm_s16le -f wav "$mic.part"
               -vn -map "0:a:$NVDA_TRACK" -ar 16000 -ac 1 -c:a pcm_s16le -f wav "$nv.part" )
    elif (( n_streams == 1 )); then
        # pan silently yields junk for a missing channel, so check for mono first.
        layout=$(ffmpeg -nostdin -hide_banner -i "$src" 2>&1 | grep -m1 -E 'Stream #0:[0-9]+.*Audio:' || true)
        if [[ $layout == *mono* || $layout == *"1 channels"* ]] || (( MIC_TRACK > 1 || NVDA_TRACK > 1 )); then
            echo "Error: ${src##*/} has a single mono audio stream (or an invalid channel); cannot split" >&2
            return 1
        fi
        echo "Splitting: ${src##*/} (1 audio stream: mic=channel $MIC_TRACK, nvda=channel $NVDA_TRACK)"
        maps=( -vn -map 0:a:0 -af "pan=mono|c0=c$MIC_TRACK"  -ar 16000 -c:a pcm_s16le -f wav "$mic.part"
               -vn -map 0:a:0 -af "pan=mono|c0=c$NVDA_TRACK" -ar 16000 -c:a pcm_s16le -f wav "$nv.part" )
    else
        echo "Error: ffmpeg found no audio stream in ${src##*/} (check with: ffmpeg -i \"$src\")" >&2
        return 1
    fi

    if err=$(ffmpeg -nostdin -hide_banner -loglevel error -y -i "$src" "${maps[@]}" 2>&1); then
        mv -f -- "$mic.part" "$mic"
        mv -f -- "$nv.part" "$nv"
        echo "mic=$MIC_TRACK nvda=$NVDA_TRACK" > "$map"
    else
        rm -f -- "$mic.part" "$nv.part"
        echo "ffmpeg failed: ${src##*/}" >&2
        printf '%s\n' "$err" | ff_filter >&2
        return 1
    fi
}
export -f ff_filter count_audio_streams convert_one convert_split_one remux_one
export MIC_TRACK=$mic_track NVDA_TRACK=$nvda_track FORCE=$force

###############################################################################
# Convert media
###############################################################################

if [[ $convert_audio == true ]]; then
    command -v ffmpeg >/dev/null || die "ffmpeg not found"
    echo "Converting media to WAV ($jobs parallel)..."

    conv_fn=convert_one
    if [[ $split_speakers == true ]]; then conv_fn=convert_split_one; fi

    # shellcheck disable=SC2016  # $1/$@ are meant to expand in the child shell
    list_media |
        xargs -0 -r -n1 -P "$jobs" bash -c 'fn=$1; shift; "$fn" "$@"' _ "$conv_fn" ||
        { warn "some conversions failed"; convert_failed=true; }
    echo
fi

###############################################################################
# Remux MKV -> MP4 (after audio is extracted, so WAVs come from the original)
###############################################################################

if [[ $to_mp4 == true ]]; then
    command -v ffmpeg >/dev/null || die "ffmpeg not found"
    echo "Remuxing MKV to MP4 ($jobs parallel)..."
    # shellcheck disable=SC2016  # $1 is meant to expand in the child shell
    find "$folder_home" -maxdepth 1 -type f -iname '*.mkv' -print0 |
        xargs -0 -r -n1 -P "$jobs" bash -c 'remux_one "$1"' _ ||
        { warn "some MP4 remuxes failed"; convert_failed=true; }
    echo
fi

###############################################################################
# Transcription helpers
###############################################################################

# transcribe_one WAV OUTPUT_PREFIX [extra whisper-cli args...]
transcribe_one() {
    local wav=$1 prefix=$2
    shift 2
    "$cli" "${args[@]}" "$@" --file "$wav" --output-file "$prefix"
}

# Merge <base>.mic.json and <base>.nvda.json by time into labeled txt/srt.
merge_transcripts() {
    python3 - "$1" "$mic_label" "$nvda_label" <<'PY'
import json, re, sys

base, mic_label, nvda_label = sys.argv[1:4]
# Drop segments that are only an annotation, e.g. [BLANK_AUDIO] or (silence).
annotation = re.compile(r'^\s*[\[\(].*[\]\)]\s*$')

def load(path, label, order):
    with open(path, encoding='utf-8', errors='replace') as f:
        data = json.load(f)
    segs = []
    for seg in data.get('transcription', []):
        text = ' '.join(seg.get('text', '').split())
        if not text or annotation.match(text):
            continue
        off = seg['offsets']
        segs.append((off['from'], off['to'], order, label, text))
    return segs

segs = load(base + '.mic.json', mic_label, 0) + load(base + '.nvda.json', nvda_label, 1)
segs.sort(key=lambda s: (s[0], s[2]))

def ts(ms):
    h, rem = divmod(int(ms), 3600000)
    m, rem = divmod(rem, 60000)
    s, ms = divmod(rem, 1000)
    return f'{h:02d}:{m:02d}:{s:02d},{ms:03d}'

with open(base + '.merged.txt', 'w', encoding='utf-8') as t, \
     open(base + '.merged.srt', 'w', encoding='utf-8') as r:
    for i, (start, end, _, label, text) in enumerate(segs, 1):
        line = f'[{label}] {text}'
        t.write(line + '\n')
        r.write(f'{i}\n{ts(start)} --> {ts(end)}\n{line}\n\n')

print(f'Merged {len(segs)} segments -> {base}.merged.txt and {base}.merged.srt')
PY
}

###############################################################################
# Transcribe
###############################################################################

if [[ $split_speakers == true ]]; then
    mapfile -d '' -t items < <(find "$folder_home" -maxdepth 1 -type f -name '*.mic.wav' -print0 | sort -z)
    [[ ${#items[@]} -gt 0 ]] || die "No split audio found in $folder_home (no media converted?)"
else
    # Split-mode files (*.mic.wav / *.nvda.wav) are not transcribed as standalone audio.
    mapfile -d '' -t items < <(find "$folder_home" -maxdepth 1 -type f -iname '*.wav' \
        ! -name '*.mic.wav' ! -name '*.nvda.wav' -print0 | sort -z)
    [[ ${#items[@]} -gt 0 ]] || die "No WAV files found in $folder_home (use --convert for video/other audio)"
fi

done_count=0
skipped=0
failed=()
total_start=$SECONDS

for wav in "${items[@]}"; do
    nvwav=""
    if [[ $split_speakers == true ]]; then
        base=${wav%.mic.wav}
        nvwav="$base.nvda.wav"
        name=${base##*/}
        if [[ ! -f $nvwav ]]; then
            echo "FAILED: $name (missing ${nvwav##*/})" >&2
            failed+=("$name")
            continue
        fi
    else
        base=${wav%.*}
        name=${wav##*/}
    fi

    fresh=false
    if [[ -s $base.$marker_ext && $base.$marker_ext -nt $wav ]]; then
        fresh=true
        if [[ -n $nvwav && ! $base.$marker_ext -nt $nvwav ]]; then fresh=false; fi
    fi
    if [[ $force == false && $fresh == true ]]; then
        echo "Skipping (already transcribed): $name"
        skipped=$((skipped + 1))
        continue
    fi

    echo "Transcribing: $name"
    start=$SECONDS
    ok=true
    if [[ $split_speakers == true ]]; then
        echo "  [$mic_label] channel..."
        transcribe_one "$wav" "$base.mic" "${out_args[@]}" &&
        { echo "  [$nvda_label] channel..."; transcribe_one "$nvwav" "$base.nvda" "${out_args[@]}"; } &&
        merge_transcripts "$base" || ok=false
    else
        transcribe_one "$wav" "$base" "${out_args[@]}" || ok=false
    fi

    if [[ $ok == true ]]; then
        t=$((SECONDS - start))
        printf 'Finished %s in %dm%02ds\n\n' "$name" $((t / 60)) $((t % 60))
        done_count=$((done_count + 1))
    else
        echo "FAILED: $name" >&2
        failed+=("$name")
    fi
done

t=$((SECONDS - total_start))
echo
printf 'Done in %dm%02ds: %d transcribed, %d skipped, %d failed\n' \
    $((t / 60)) $((t % 60)) "$done_count" "$skipped" "${#failed[@]}"

if [[ ${#failed[@]} -gt 0 || $convert_failed == true ]]; then
    if [[ ${#failed[@]} -gt 0 ]]; then
        printf '  failed: %s\n' "${failed[@]}" >&2
    fi
    if [[ $convert_failed == true ]]; then
        echo "  some conversions or MP4 remuxes failed (see messages above)" >&2
    fi
    exit 1
fi