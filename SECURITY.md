# Security and Privacy

## Local Processing

Microphone recordings and transcripts are processed locally on the Mac.
Local Flow does not use a cloud transcription API.

## Network Access

The application only needs network access to download a selected Whisper
model from the official `ggerganov/whisper.cpp` Hugging Face repository.
The download URL is pinned to repository revision
`5359861c739e955e79d9a303bcbc70fb988958b1`, and the model is verified with
SHA-256 before it is installed.

Local Flow also sends a metadata-only request to GitHub's public Releases API
to check whether a newer app version exists. No recording or transcript is
included in this request.

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
