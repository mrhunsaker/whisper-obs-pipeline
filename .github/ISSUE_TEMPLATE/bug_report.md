---
name: Bug report
about: Something does not work as documented
title: ""
labels: bug
assignees: ""
---

**What happened, and what you expected**

**Command you ran**

```
./scripts/whisperCPPPipeline.sh ...
```

**Output** (trim repeated whisper init lines if you like)

```
```

**Environment**

- OS / distribution:
- Script version or commit:
- whisper.cpp commit (`git -C <whisper.cpp> rev-parse --short HEAD`):
- whisper.cpp backend (CPU / CUDA / ROCm / Vulkan / Metal):
- `ffmpeg -version | head -1`:

**For split-mode problems:** the audio streams in the file (`ffmpeg -i yourfile.mkv`, the `Stream #` lines)

```
```

Please do not attach recordings with private audio. For security issues, use the private reporting described in SECURITY.md instead of this form.
