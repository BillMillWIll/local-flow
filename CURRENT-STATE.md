# Current State

Updated: 19 June 2026

This is the first file to read in a new session before changing Local Flow.

## Product

- Native Swift 6 macOS application
- Minimum system: macOS 14
- Architecture: Apple Silicon (`arm64`)
- Bundle identifier: `de.artmotion.localflow`
- Current version: read from `VERSION`
- Intended distribution: friends and colleagues through GitHub Releases

## Runtime Architecture

- The app bundle includes `whisper-cli` and its required dynamic libraries.
- Friends do not need Homebrew, Xcode, Swift, or Terminal.
- Whisper models are not bundled in the DMG.
- The selected model downloads automatically on first use from:
  `ggerganov/whisper.cpp` on Hugging Face.
- Every downloaded model is checked against a hard-coded SHA-256 checksum.
- Models are stored in:
  `~/Library/Application Support/LocalFlow/`
- App settings and the last five transcripts are stored in macOS
  `UserDefaults`.

## Models

- `ggml-small-q5_1.bin`, approximately 181 MB, default
- `ggml-large-v3-turbo-q5_0.bin`, approximately 547 MB

Only the selected missing model is downloaded. Existing verified models from
older Local Flow installations remain usable.

## Main Files

- `Sources/LocalFlow/main.swift`: AppKit UI, recording, downloads, Whisper
  execution, history and paste behavior
- `Sources/LocalFlowCore/LocalFlowCore.swift`: testable model metadata,
  hotkey logic, state and transcript helpers
- `Tests/LocalFlowCoreTests/`: automated tests
- `scripts/check-release.sh`: secret scan, tracked-file validation and tests
- `scripts/build-app.sh`: portable application bundle
- `scripts/build-dmg.sh`: final DMG and SHA-256 file
- `DISTRIBUTION.md`: release procedure
- `SECURITY.md`: privacy and reporting

## Release State

- Portable bundle no longer requires Homebrew on the recipient Mac.
- DMG generation is implemented.
- Release artifacts are generated under `dist/` and are ignored by Git.
- Current signature is ad-hoc.
- Apple notarization is not configured.
- There is no automatic updater yet; updates are installed by replacing the
  application with the newer DMG.
- Models, settings and transcript history survive app replacement.

## Safety Rules

- Never commit models, recordings, DMGs, private keys, signing certificates,
  `.env` files or credentials.
- Run `./scripts/check-release.sh` before every release.
- Keep Local Flow in its own Git repository. Do not publish the parent
  workspace repository.
- Do not add analytics, cloud transcription or external APIs without an
  explicit product decision and privacy review.

## Next Sensible Steps

1. Test the DMG on a second Apple Silicon Mac without Homebrew.
2. Confirm first-run Gatekeeper, microphone and accessibility instructions.
3. Add Developer ID signing and notarization if distribution expands.
4. Consider Sparkle only when manual updates become inconvenient.
