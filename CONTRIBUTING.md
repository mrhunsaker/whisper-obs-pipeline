# Contributing

Thanks for your interest in improving whisper-obs-pipeline. Bug reports, fixes, docs improvements and well-scoped features are all welcome. Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first; it applies to every project space.

## Scope

This project is a thin, dependable Bash wrapper around [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and ffmpeg for batch transcription and for splitting OBS microphone and desktop-audio tracks into a labeled transcript. Good fits:

- Reliability, error messages and edge cases in the script
- Support for more recording layouts or input formats
- Documentation and examples

Probably out of scope: a GUI, cloud transcription, reimplementing whisper.cpp features, or anything that needs a dependency beyond bash, ffmpeg and the Python standard library. If you are unsure, open an issue and ask before writing code.

Bugs in whisper.cpp or ffmpeg themselves belong in those projects' trackers.

## Reporting bugs

Open an issue using the bug report template. The most useful reports include:

- The exact command you ran, and the full output (trim the repeated whisper init lines if you like)
- Your OS and distribution, the script version or commit, and the whisper.cpp commit (`git -C <whisper.cpp> rev-parse --short HEAD`)
- The backend you built whisper.cpp with (CPU, CUDA, ROCm/HIP, Vulkan, Metal)
- `ffmpeg -version | head -1`
- For split-mode problems: the audio stream layout of the file, from `ffmpeg -i yourfile.mkv`

Please do not attach recordings that contain private or sensitive audio. A short synthetic reproduction is better.

Security problems should not go in public issues; see [SECURITY.md](SECURITY.md).

## Suggesting features

Open an issue describing the problem you are trying to solve before the solution. Include a sample of your input (for example, how many audio streams and channels your recordings have) when it matters.

## Development setup

You need `bash` 4.4 or newer, `ffmpeg`, `python3` (standard library only), and [ShellCheck](https://www.shellcheck.net/).

```bash
git clone https://github.com/<your-username>/whisper-obs-pipeline.git
cd whisper-obs-pipeline
```

You do **not** need whisper.cpp, a GPU or any model to run the tests. The smoke test uses a stub `whisper-cli` and short synthetic recordings.

## Checks to run before opening a pull request

```bash
bash -n scripts/whisperCPPPipeline.sh                    # syntax
shellcheck scripts/whisperCPPPipeline.sh tests/smoke-test.sh
bash tests/smoke-test.sh                                 # end-to-end, about 3 seconds
```

CI runs the same three checks on every push and pull request. If you change behavior, add or adjust a case in `tests/smoke-test.sh`. If you can, also try the change once against a real whisper.cpp build and say so in the pull request.

## Code style (the script)

- Keep `set -Eeuo pipefail`. Quote every expansion. Build commands as arrays (`args+=(--flag "$value")`), never as strings.
- No `eval`. Paths are expanded with the `expand_path` helper.
- Under `set -e`, avoid `[[ ... ]] && cmd` as the last command in a block and avoid `((i++))` (it returns 1 when `i` is 0). Use `if` statements and `i=$((i + 1))`.
- Write outputs atomically: write to `name.part`, then `mv` into place, and delete the `.part` file on failure. This keeps interrupted runs from leaving half-written files that later look finished.
- Print problems to stderr with `warn` or `die`. A failed file must not stop the rest of the batch, but it must make the final exit code non-zero.
- Functions run through `xargs` must be exported (`export -f`) and take everything they need from arguments or exported variables.
- Detect optional whisper.cpp flags (for example `--device`) from `--help` rather than assuming them, since flags vary between versions.
- ShellCheck must be clean. If you disable a rule, add a comment saying why.
- Keep the `--help` text, `README.md` and `CHANGELOG.md` in sync with any option you add, remove or rename.

## Documentation

Docs live in `README.md` and `docs/`. Keep instructions copy-pasteable, show the command and what you should see, and avoid fixing distribution-specific problems in the main docs; link to the upstream documentation for those.

## Changelog

Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the right section (Added, Changed, Fixed, Removed, Security). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Commits and pull requests

- Keep each pull request focused on one change.
- Write commit messages in the imperative mood with a short summary line ("Fix track swap not re-splitting"), and explain the why in the body when it is not obvious.
- Fill in the pull request template. Mark it as a draft if it is not ready for review.
- By contributing, you agree that your contribution is licensed under the project's [MIT License](LICENSE).

## Releasing (maintainers)

1. Move the `[Unreleased]` entries into a new version section in `CHANGELOG.md` with the date, and update the comparison links at the bottom.
2. Commit, then tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin main vX.Y.Z`.
3. Create a GitHub release from the tag and paste in the changelog section.
