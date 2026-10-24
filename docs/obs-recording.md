# Recording two audio tracks in OBS Studio

Speaker-split mode needs the microphone and the desktop audio (for example your screen reader) stored as **separate audio tracks** in the recording file. OBS only does that in **Advanced** output mode. In Simple mode everything is mixed into Track 1, and the sources cannot be separated afterward.

Menu names can differ slightly between OBS versions.

## 1. Switch to Advanced output and enable tracks

1. Open Settings → Output and set **Output Mode** to **Advanced**.
2. Open the **Recording** tab and check **Audio Track 1 and 2**. Check a third track too if you want the combined-mix layout below.
3. Set **Recording Format** to **MKV**. It handles multiple tracks well and survives a crash. The pipeline can remux the result to MP4 afterward (`--to-mp4`).
4. Optionally set each track's bitrate on the **Audio** tab in the same Output settings.

## 2. Assign each source to its own track

1. In the Audio Mixer dock, open the menu on any source and choose **Advanced Audio Properties** (also under the Edit menu).
2. Find the row for your **Audio Input Capture** (microphone) and the row for your **Audio Output Capture** (desktop or screen reader audio). Each row has checkboxes for tracks 1 to 6.
3. Choose a layout:

| Layout | Mic | Desktop audio | Pipeline options |
|---|---|---|---|
| **Simple split** | track 1 only | track 2 only | defaults (`--mic-track 0 --nvda-track 1`) |
| **Mix plus split** (recommended) | tracks 1 and 2 | tracks 1 and 3 | `--mic-track 1 --nvda-track 2` |

In "mix plus split", track 1 is the full mix, so the video sounds normal in every player; tracks 2 and 3 are the isolated sources. In "simple split", most players play only the first track, which is just the microphone.

4. Make sure no source is captured twice. If a global Desktop Audio device is set in Settings → Audio and you also added an Audio Output Capture source, you will get two copies on Track 1.

## 3. Test before a real session

1. Record about 10 seconds while speaking, with the screen reader talking at the same time.
2. Check the file has more than one audio stream:

   ```bash
   ffmpeg -i test.mkv
   ```

   You should see more than one `Audio` stream. In VLC, **Audio → Audio Track** lists them too.
3. To identify which track is which, play each one in VLC, or mute your mic in OBS during a second test and see which track goes quiet.
4. Run the pipeline on the test file and read `test.merged.txt`. If the labels are swapped, reverse `--mic-track` and `--nvda-track`.

## Tips

- **Use headphones.** If the screen reader plays through speakers, your mic picks it up and the same speech shows up under both labels.
- Keep other sources (browser, music, game audio) on track 1 only, or out of the recording. Anything on the mic or desktop track is transcribed under that label.
- Recordings made before you changed these settings cannot be split.
