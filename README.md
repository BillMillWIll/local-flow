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
3. Open Local Flow. Because the friend release is not Apple-notarized, macOS
   blocks the first start. Open System Settings, choose Privacy & Security,
   scroll down to Security and click `Open Anyway` next to Local Flow.
4. Grant microphone and accessibility permissions.
5. Let the app prepare the selected speech engine once.

After setup, transcription runs locally. Audio and transcripts are not sent
to a transcription API.

## Features

- configurable push-to-talk key, including `fn`/Globe
- double-tap the key for hands-free dictation, tap again to insert
- `Esc` cancels a running recording, nothing is inserted
- three local engines: Apple speech recognition (macOS 26, no download),
  NVIDIA Parakeet v3 and Whisper Large v3 Turbo
- optional clean-up with Apple Intelligence: removes filler words and fixes
  punctuation on-device, switchable in the settings and the menu bar
- searchable personal dictionary with preferred spellings and observed
  recognition errors, editing, undo, examples and a live correction preview
- paste several words at once, one per line; existing comma lists migrate
  automatically, without losing words
- corrections work with all three engines; Whisper also receives spelling
  hints (hints improve recognition but do not guarantee it)
- spoken commands and text snippets such as `neue Zeile = \n`
- protection against Whisper's silence hallucinations: minimum recording
  length, voice activity detection and a phrase filter
- automatic, revision-pinned and checksum-verified model download
- system-default or manually selected microphone
- test recording, local history of the last five transcripts
- automatic paste with clipboard restoration
- optional start and stop sounds, optional start at login
- automatic update check with a direct link to the newest GitHub release
- guided four-step first-run setup
- resizable native settings with live status and four scrollable tabs
- dynamic menu-bar feedback while recording, transcribing and cleaning

## Requirements

- Apple Silicon Mac
- macOS 14 or newer; the Apple engine and the clean-up need macOS 26
- internet connection for the one-time model download

## Words that are repeatedly misrecognized

Open **Wörterbuch → Wort hinzufügen…**. Enter the desired spelling and one
actual recognition error, for example `Crockbot → GrokBot`. Save other
variants, such as `Krugbot` and `Grockbot`, as additional entries with the
same desired spelling. These exact corrections work with Apple, Parakeet
and Whisper, regardless of capitalization. They do not change parts of
longer words or identifiers.

Use **Beispiele** to fill an example before saving it, or **Mehrere Wörter
einfügen…** to paste a list with one preferred word per line. The old
comma-separated list is imported automatically. A word saved without an
error variant fixes capitalization when the word is already recognized;
only Whisper also uses it as a recognition hint. This does not train the
Apple or Parakeet models.

The correction preview checks your dictionary and the text replacements
immediately, without recording. **Sprechen → Aufnahme testen** checks the
microphone and selected engine. **Text** contains optional Apple
Intelligence clean-up and advanced spoken commands / text snippets.
Clean-up cannot remove your protected names or spoken commands.

## Development

```bash
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
```

Release builds require Xcode 26 and Homebrew installations of `whisper-cpp`,
`ggml`, and `libomp` on the build Mac. Users do not need Homebrew.

Read [CURRENT-STATE.md](CURRENT-STATE.md) before changing release behavior.
Distribution details are in [DISTRIBUTION.md](DISTRIBUTION.md). Measured
engine comparisons are in [AUDIT-2026-09.md](AUDIT-2026-09.md).

The source code is publicly visible but is not open source. See [LICENSE](LICENSE).

## Privacy

Recordings are created temporarily on the Mac, processed locally and deleted
right after transcription. Model files are downloaded from pinned Hugging
Face revisions and checksum-verified. See [SECURITY.md](SECURITY.md).

## Current Limitation

The current builds are ad-hoc signed, not Apple-notarized. They are intended
for a small circle of friends and colleagues. Public commercial distribution
should use a Developer ID signature and Apple notarization.
