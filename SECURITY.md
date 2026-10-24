# Security Policy

## Supported versions

Only the latest release and the current `main` branch receive security fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private reporting: open the repository's **Security** tab, choose **Report a vulnerability**, and describe the issue there. If that option is not available, email `<your-email>` instead.

Helpful details:

- What the problem is and what an attacker could do with it
- The exact command, option values, and a minimal input (file name or file) that triggers it
- Your OS, `bash --version | head -1` and `ffmpeg -version | head -1`

This is a volunteer-run project, so responses are best-effort. You can expect an acknowledgment, a discussion of severity and a fix or mitigation as time allows, and credit in the release notes if you want it.

## What is in scope

This repository contains a Bash script and documentation. Relevant issues include:

- Command or option injection through file names, folder names, paths or option values
- Unsafe handling of temporary or output files (for example, writing outside the target folder)
- Behavior that could cause the script to overwrite or delete files it should not touch
- Documentation that tells users to do something unsafe

## What is out of scope

- Vulnerabilities in [whisper.cpp](https://github.com/ggml-org/whisper.cpp), ffmpeg, Python or other dependencies. Report those to the respective projects.
- Issues that require an attacker to already control your shell or the script itself.

## Notes for users

- The script runs `ffmpeg` and `whisper-cli` on every media file in the folder you give it. Media parsers have had vulnerabilities in the past, so process recordings from sources you trust, keep ffmpeg and whisper.cpp up to date, and avoid running the script as root.
- The script never uses `eval` and quotes file names, but you should still review any change you pull in, as with any script you run on your own files.
- Transcription runs locally. Nothing is uploaded anywhere by this script.
