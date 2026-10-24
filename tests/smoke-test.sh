#!/usr/bin/env bash
#
# End-to-end smoke test for whisperCPPPipeline.sh.
# Uses synthetic OBS-style recordings and a stub whisper-cli, so it needs only
# bash, ffmpeg and python3: no GPU, no models, no real transcription.
#
set -Eeuo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$here/scripts/whisperCPPPipeline.sh"

for tool in ffmpeg python3 md5sum; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 2; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
wcpp="$tmp/whisper.cpp"
media="$tmp/media"
mkdir -p "$wcpp/build/bin" "$wcpp/models" "$media"
: > "$wcpp/models/ggml-large-v3.bin"

# Stub whisper-cli: answers --help and writes canned JSON for each channel.
cat > "$wcpp/build/bin/whisper-cli" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == --help ]]; then echo "--device --carry-initial-prompt"; exit 0; fi
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-file) out=$2; shift 2 ;;
        --file) f=$2; shift 2 ;;
        *) shift ;;
    esac
done
if [[ $f == *.nvda.wav ]]; then
    echo '{"transcription":[{"offsets":{"from":4000,"to":6000},"text":" Link, heading level two."}]}' > "$out.json"
elif [[ $f == *.mic.wav ]]; then
    echo '{"transcription":[{"offsets":{"from":1000,"to":3000},"text":" Hello, can you hear it?"},{"offsets":{"from":9000,"to":11000},"text":" Next link."},{"offsets":{"from":12000,"to":13000},"text":" [BLANK_AUDIO]"}]}' > "$out.json"
else
    echo " normal mode transcript" > "$out.txt"
fi
STUB
chmod +x "$wcpp/build/bin/whisper-cli"

pass=0
fail=0
check() {   # check "description" command...
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1)); echo "  ok   $desc"
    else
        fail=$((fail + 1)); echo "  FAIL $desc"
    fi
}
run() { bash "$script" --folder-home "$media" --whisper-home "$wcpp" "$@"; }
audio_streams() { ffmpeg -hide_banner -i "$1" 2>&1 | grep -c 'Stream #0:.*Audio:' || true; }

echo "Creating synthetic recordings..."
# OBS-style MKV: video + two audio tracks (440 Hz = mic, 880 Hz = desktop)
ffmpeg -loglevel error -f lavfi -i testsrc=d=2:s=64x64:r=5 \
    -f lavfi -i sine=f=440:d=2 -f lavfi -i sine=f=880:d=2 \
    -map 0:v -map 1:a -map 2:a -c:v mpeg4 -c:a aac "$media/twotracks.mkv"
# One stereo stream (left = 440 Hz, right = 880 Hz)
ffmpeg -loglevel error -f lavfi -i sine=f=440:d=2 -f lavfi -i sine=f=880:d=2 \
    -filter_complex "[0][1]amerge=inputs=2" -c:a aac "$media/stereo.m4a"
# Mono file: cannot be split
ffmpeg -loglevel error -f lavfi -i sine=f=440:d=2 -c:a aac "$media/mono.m4a"

echo
echo "Split mode"
rm -f "$media/mono.m4a"   # keep the first run clean; mono is tested separately below
check "split run succeeds" run --split-speakers
check "mic WAV written"  test -s "$media/twotracks.mic.wav"
check "nvda WAV written" test -s "$media/twotracks.nvda.wav"
check "stereo file split into channels" test -s "$media/stereo.nvda.wav"
check "merged txt has both labels" bash -c "grep -q '^\[MRH\]' '$media/twotracks.merged.txt' && grep -q '^\[NVDA\]' '$media/twotracks.merged.txt'"
check "merged txt is ordered by time" bash -c "[[ \"\$(sed -n 2p '$media/twotracks.merged.txt')\" == '[NVDA] Link, heading level two.' ]]"
check "annotations like [BLANK_AUDIO] are dropped" bash -c "! grep -q BLANK_AUDIO '$media/twotracks.merged.txt'"
check "merged srt written" test -s "$media/twotracks.merged.srt"
check "MP4 remux keeps both audio tracks" bash -c "[[ \$(ffmpeg -hide_banner -i '$media/twotracks.mp4' 2>&1 | grep -c 'Stream #0:.*Audio:') -eq 2 ]]"

echo
echo "Re-runs"
out=$(run --split-speakers 2>&1)
check "second run skips finished work" bash -c "grep -q 'Skipping (already transcribed)' <<<'$out'"

mic_before=$(md5sum < "$media/twotracks.mic.wav")
nvda_before=$(md5sum < "$media/twotracks.nvda.wav")
run --split-speakers --mic-track 1 --nvda-track 0 >/dev/null 2>&1
check "swapping tracks re-splits" bash -c "[[ '$(md5sum < "$media/twotracks.mic.wav")' == '$nvda_before' && '$(md5sum < "$media/twotracks.nvda.wav")' == '$mic_before' ]]"

echo
echo "Edge cases"
ffmpeg -loglevel error -f lavfi -i sine=f=440:d=2 -c:a aac "$media/mono.m4a"
if run --split-speakers >/dev/null 2>&1; then
    fail=$((fail + 1)); echo "  FAIL mono file should make the run fail"
else
    pass=$((pass + 1)); echo "  ok   mono file is rejected with a non-zero exit"
fi
rm -f "$media/mono.m4a"

if run >/dev/null 2>&1; then
    fail=$((fail + 1)); echo "  FAIL non-interactive run without --model should fail"
else
    pass=$((pass + 1)); echo "  ok   non-interactive run without --model fails clearly"
fi

echo
echo "Normal mode"
rm -f "$media"/*.txt "$media"/*.srt
run --model ggml-large-v3.bin --convert --outputs txt >/dev/null 2>&1 || true
check "normal mode transcribes converted WAV" test -s "$media/twotracks.txt"
check "normal mode ignores *.mic.wav / *.nvda.wav" bash -c "[[ ! -e '$media/twotracks.mic.txt' ]]"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
