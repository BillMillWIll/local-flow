# Current State

Updated: 4 September 2026

This is the first file to read in a new session before changing Local Flow.
Repository-wide AI instructions and the mandatory release workflow are defined
in `docs/agent/`.

## Product

- Native Swift 6 macOS application
- Minimum system: macOS 14; Apple engine and clean-up need macOS 26
- Architecture: Apple Silicon (`arm64`)
- Bundle identifier: `de.artmotion.localflow`
- Current version: read from `VERSION`
- Intended distribution: friends and colleagues through GitHub Releases
- Own Git repository at `~/Desktop/local-flow` since 2026-09-04; the ArtMotion
  monorepo only keeps a reference stub

## Runtime Architecture

- Three recognition engines behind `TranscriptionEngine`
  (`Sources/LocalFlow/Engines/`):
  - `apple`: `SpeechAnalyzer`/`SpeechTranscriber` de-DE, macOS 26, no
    download; default when supported.
  - `parakeet`: `parakeet-cli` with `ggml-parakeet-tdt-0.6b-v3-q8_0.bin`
    (670 MB); default on macOS 14/15.
  - `whisperTurbo`: `whisper-cli` with `ggml-large-v3-turbo-q5_0.bin`
    (550 MB) plus Silero VAD (1 MB); only engine that uses the custom word
    prompt directly.
- The app bundle includes `whisper-cli`, `parakeet-cli`, their libraries and
  all ggml backends (`libggml-*.so`). ggml 0.20 searches Homebrew's
  `libexec` first and then the tool's own folder, so the backends live next
  to the tools in `whisper/bin`. The portable test verifies this with a
  sandbox that hides `/opt/homebrew`.
- Every downloaded model is pinned to a Hugging Face revision and checked
  against a hard-coded SHA-256 checksum (`ModelCatalog` in
  `LocalFlowCore/Engines.swift`).
- Text pipeline after recognition: `TranscriptCleaner` (noise markers and
  Whisper hallucination phrases) → replacement rules → optional
  `TextCleanup` with the Foundation Models framework, guarded by
  `CleanupGuard` so an implausible result falls back to the raw text.
- Recording guards: recordings under 0.4 s are dropped as accidental taps,
  recordings stop automatically after 5 minutes, `Esc` cancels.
- Push-to-talk gestures: hold; double tap for hands-free; a menu item can
  start and stop hands-free recording too (`PushToTalkState`,
  `DoubleTapDetector`).
- The start sound plays before the recorder starts and the stop sound after
  it stops; otherwise the Apple engine transcribes the beep as a word.
- libggml's compiled-in Homebrew backend path is neutralised in the bundle
  (`build-app.sh`), because a Mac with Homebrew would otherwise load foreign
  backends and crash in the VAD path.
- Recording WAV and tool output files are deleted after each dictation.
- The start sound plays before the recorder starts and the stop sound after
  it stops; otherwise the Apple engine transcribes the sound as a word.
- Models are stored in `~/Library/Application Support/LocalFlow/`.
- App settings, dictionary and the last five transcripts are stored in macOS
  `UserDefaults`. The pre-2.0 `whisperModel` key is migrated to
  `recognitionEngine`.

## Main Files

- `Sources/LocalFlow/AppDelegate.swift`: menu bar, recording flow, engine
  preparation, updates
- `Sources/LocalFlow/SettingsWindowController.swift`: settings window with
  the tabs Sprechen, Text, Erweitert
- `Sources/LocalFlow/OnboardingWindowController.swift`: four-step setup
- `Sources/LocalFlow/Engines/`: engine protocol, runtime lookup, Whisper,
  Parakeet, Apple
- `Sources/LocalFlow/TextCleanup.swift`: Apple Intelligence clean-up
- `Sources/LocalFlow/SystemIntegration.swift`: sounds, login item
- `Sources/LocalFlowCore/`: testable logic (engines, dictionary, gestures,
  state machine, cleaner, history)
- `Tests/LocalFlowCoreTests/`: automated tests (66)
- `scripts/check-release.sh`: secret scan, tracked-file validation and tests
- `scripts/build-app.sh`: portable application bundle
- `scripts/build-dmg.sh`: final DMG and SHA-256 file
- `scripts/test-portable-release.sh`: bundled-runtime check (backends load
  from the bundle), pinned downloads and, locally, real inference with both
  command-line tools
- `.github/workflows/release-check.yml`: fresh ARM64 macOS 26 release check
- `AUDIT-2026-09.md`: measured engine comparison behind the 2.0 decisions

## Release State

- 2.0.0 is the first release with engine selection, clean-up, dictionary,
  hands-free mode and the hallucination guards.
- 2.0.1 fixes review findings: a double tap during recorder start-up now
  becomes hands-free instead of being swallowed, `Esc` during start-up no
  longer leaves the microphone running, the hallucination filter only removes
  known broadcaster credits or phrases with a year, switching engines during
  a download prepares the new engine afterwards, each recording uses its own
  temporary file, and the clean-up model is pre-warmed while enabled. Engine
  names say which one is new and which one is the previous recognition.
- 1.2.1 bundled whisper.cpp 1.8.6 with ggml 0.15.1, which linked its
  backends statically. Builds against ggml 0.20 need the bundled `.so`
  backends, otherwise the tools only work on Macs with Homebrew.
- Current signature is ad-hoc; Apple notarization is not configured.
- There is no automatic updater; the app links to the newest GitHub release.
- The GitHub runner (`macos-26`) validates build, bundled backends, the VAD
  download and the DMG. Real inference is tested locally.

## Safety Rules

- Never commit models, recordings, DMGs, private keys, signing certificates,
  `.env` files or credentials.
- Run `./scripts/check-release.sh` before every release.
- Do not add analytics, cloud transcription or external APIs without an
  explicit product decision and privacy review.

## Next Sensible Steps

1. Confirm the Apple engine and the clean-up with real microphone speech on
   a second Mac.
2. Add Developer ID signing and notarization if distribution expands.
3. Consider Sparkle only when browser-based update installation becomes
   inconvenient.
