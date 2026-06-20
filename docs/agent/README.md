# Local Flow Agent Context

This folder is the starting point for every AI session working on Local Flow.

## Start Here

Before changing Local Flow:

1. Read `../../CURRENT-STATE.md`.
2. Read `../../DISTRIBUTION.md` before changing packaging, versions or
   releases.
3. Read `../../VERSION` and inspect `git status`.

Do not reconstruct the project state from memory when these files provide the
current source of truth.

## Canonical Repository and Distribution

- Local repository: `~/Desktop/ArtMotion-Antigravity/docs/local-flow`
- Public repository: `https://github.com/BillMillWIll/local-flow`
- Permanent latest-download page:
  `https://github.com/BillMillWIll/local-flow/releases/latest`
- GitHub Releases are the canonical distribution channel for friends and
  colleagues.

Every finished user-facing update should be considered for a new semantic
version and GitHub Release. Do not leave a completed release only on the local
Mac.

## Required Release Flow

1. Update and test the implementation.
2. Update `../../VERSION`.
3. Update `../../CURRENT-STATE.md` and user-facing documentation when relevant.
4. Run `../../scripts/build-dmg.sh` from the repository root.
5. Verify the DMG, checksum, embedded app version and code signature.
6. Commit, tag `vVERSION`, and push `main` plus the tag.
7. Create the GitHub Release with the DMG and `.sha256` file.
8. Wait for `../../.github/workflows/release-check.yml` to pass.
9. Download the public release and verify it again as a recipient would.
10. Confirm that the repository is clean and report the latest-release link.

Do not state that a release is complete before both the public artifact and
the GitHub Actions release check have been verified.

## Privacy and Safety

Never commit models, recordings, DMGs, private keys, signing certificates,
credentials, `.env` files, personal data or local temporary files.

Preserve unrelated user changes and never publish the parent
`ArtMotion-Antigravity` repository as part of Local Flow.
