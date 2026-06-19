# Local Flow

Local Flow is a small native macOS push-to-talk app. Hold a configurable key,
speak, release the key, and the locally transcribed German text is inserted
into the active text field.

## Download

Download the latest `Local-Flow-*.dmg` from:

<https://github.com/BillMillWIll/local-flow/releases/latest>

Installation:

1. Open the DMG.
2. Drag `Local Flow` into `Programme`.
3. Open Local Flow.
4. On the first start, macOS may require right-clicking the app and selecting
   `Open` because the current friend release is not Apple-notarized.
5. Grant microphone and accessibility permissions.
6. Wait while the selected speech model is downloaded once and verified.

After setup, transcription runs locally. Audio and transcripts are not sent
to a transcription API.

## Features

- configurable push-to-talk key, including `fn`/Globe
- local German transcription with `whisper.cpp`
- selectable Small Q5_1 and Large v3 Turbo Q5_0 models
- automatic, revision-pinned and checksum-verified model download
- visible download progress and retry action
- system-default or manually selected microphone
- test recording
- local history of the last five transcripts
- automatic paste with clipboard restoration
- automatic update check with a direct link to the newest GitHub release
- native application icon

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- internet connection for the one-time model download

## Development

```bash
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
```

Release builds require Homebrew installations of `whisper-cpp`, `ggml`, and
`libomp` on the build Mac. Users do not need Homebrew.

Read [CURRENT-STATE.md](CURRENT-STATE.md) before changing release behavior.
Distribution details are in [DISTRIBUTION.md](DISTRIBUTION.md).

The source code is publicly visible but is not open source. See [LICENSE](LICENSE).

## Privacy

Recordings are created temporarily on the Mac and processed locally. The
selected Whisper model is downloaded from the official `whisper.cpp`
repository on Hugging Face at a fixed repository revision. See
[SECURITY.md](SECURITY.md).

## Current Limitation

The current builds are ad-hoc signed, not Apple-notarized. They are intended
for a small circle of friends and colleagues. Public commercial distribution
should use a Developer ID signature and Apple notarization.
