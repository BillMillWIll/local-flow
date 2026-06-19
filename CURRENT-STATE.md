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
- Model URLs are pinned to Hugging Face repository revision
  `5359861c739e955e79d9a303bcbc70fb988958b1`.
- The UI displays percentage progress and exposes a retry button after errors.
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
- `scripts/test-portable-release.sh`: clean model-directory download and
  bundled-runtime transcription test
- `.github/workflows/release-check.yml`: fresh ARM64 macOS release validation
- `DISTRIBUTION.md`: release procedure
- `SECURITY.md`: privacy and reporting

## Release State

- Portable bundle no longer requires Homebrew on the recipient Mac.
- DMG generation is implemented.
- The DMG uses a fixed compact 660 x 400 Finder layout with a branded
  background, drag arrow and German installation instruction.
- Release artifacts are generated under `dist/` and are ignored by Git.
- Current signature is ad-hoc.
- Apple notarization is not configured.
- There is no automatic updater yet; updates are installed by replacing the
  application with the newer DMG.
- The app checks GitHub Releases automatically and links directly to a newer
  DMG when available.
- Models, settings and transcript history survive app replacement.
- The app has a generated native icon.
- Complete `whisper.cpp`, `ggml`, and `libomp` license texts are included.
- Local Flow source and release use are governed by the repository `LICENSE`.
- GitHub's virtualized ARM64 runner validates the clean download, checksum,
  executable runtime and DMG. Actual audio inference is tested locally because
  `whisper.cpp` inference is unstable inside GitHub's macOS virtualization.

## Safety Rules

- Never commit models, recordings, DMGs, private keys, signing certificates,
  `.env` files or credentials.
- Run `./scripts/check-release.sh` before every release.
- Keep Local Flow in its own Git repository. Do not publish the parent
  workspace repository.
- Do not add analytics, cloud transcription or external APIs without an
  explicit product decision and privacy review.

## Next Sensible Steps

1. Confirm first-run microphone and accessibility interaction with a friend.
2. Add Developer ID signing and notarization if distribution expands.
3. Consider Sparkle only when browser-based update installation becomes
   inconvenient.
