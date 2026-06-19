# Security and Privacy

## Local Processing

Microphone recordings and transcripts are processed locally on the Mac.
Local Flow does not use a cloud transcription API.

## Network Access

The application only needs network access to download a selected Whisper
model from the official `ggerganov/whisper.cpp` Hugging Face repository.
The model is verified with SHA-256 before it is installed.

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
