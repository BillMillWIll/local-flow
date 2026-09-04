# Security and Privacy

## Local Processing

Microphone recordings and transcripts are processed locally on the Mac.
Local Flow does not use a cloud transcription API.

## Network Access

Local Flow needs network access only for one-time downloads that depend on
the selected engine:

- Parakeet: the model from `ggml-org/parakeet-GGUF` on Hugging Face at
  revision `35156454d1a39de06863303dd209fd2bed6ee079`.
- Whisper Turbo: the model from `ggerganov/whisper.cpp` at revision
  `5359861c739e955e79d9a303bcbc70fb988958b1` and the Silero VAD model from
  `ggml-org/whisper-vad` at revision
  `9ffd54a1e1ee413ddf265af9913beaf518d1639b`.
- Apple: macOS downloads its own German speech asset through Apple if it is
  not installed yet.

Every model file from Hugging Face is verified with SHA-256 before it is used.

Local Flow also sends a metadata-only request to GitHub's public Releases API
to check whether a newer app version exists. No recording or transcript is
included in this request.

The optional clean-up step uses Apple's on-device language model
(Foundation Models framework). Text does not leave the Mac.

Recordings are deleted right after transcription. The last five transcripts
are kept in `UserDefaults` for the history menu.

## Repository Hygiene

The repository ignores:

- `.env` files
- keys, certificates and provisioning profiles
- credential and private directories
- downloaded models
- recordings
- generated applications, DMGs and archives

`./scripts/check-release.sh` scans tracked content for forbidden files and
common secret patterns, then runs the full test suite.

## Reporting

Do not post security reports containing personal data, recordings or secrets
in a public GitHub issue. Contact the repository owner privately instead.
