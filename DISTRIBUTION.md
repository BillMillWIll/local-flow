# Distribution

## Build a Friend Release

Prerequisites on the build Mac:

```bash
brew install whisper-cpp libomp
```

Create the checked DMG:

```bash
./scripts/build-dmg.sh
```

Artifacts:

```text
dist/Local-Flow-VERSION.dmg
dist/Local-Flow-VERSION.dmg.sha256
```

The DMG contains:

- the portable `Local Flow.app`
- a link to the macOS Applications folder
- bundled `whisper-cli` runtime and third-party notices
- the Local Flow app icon

It does not contain Whisper models, recordings, settings or credentials.

## Publish a GitHub Release

1. Update `VERSION`.
2. Update `CURRENT-STATE.md` when architecture or release behavior changed.
3. Run:

```bash
./scripts/build-dmg.sh
```

4. Commit and tag the release:

```bash
git add .
git commit -m "Release VERSION"
git tag "vVERSION"
git push origin main --tags
```

5. Upload the DMG:

```bash
gh release create "vVERSION" \
  "dist/Local-Flow-VERSION.dmg" \
  "dist/Local-Flow-VERSION.dmg.sha256" \
  --title "Local Flow VERSION" \
  --notes "Friend release for Apple Silicon Macs running macOS 14 or newer."
```

## Recipient Update Process

1. Download the newest DMG from GitHub Releases.
2. Open it.
3. Drag Local Flow into `Programme`.
4. Choose `Replace`.

Downloaded models, selected settings and transcript history remain in the
user's Library and are not removed by replacing the app.

Local Flow checks the latest GitHub release on startup. If a newer semantic
version exists, the settings window and menu-bar menu link to that release.
Installation still uses the explicit DMG replacement flow; the app does not
silently replace itself.

## Gatekeeper

The current friend builds are ad-hoc signed but not Apple-notarized. On first
launch, a recipient may need:

1. right-click `Local Flow`
2. choose `Open`
3. confirm `Open`

For normal double-click installation without this warning, use an Apple
Developer ID certificate and notarize the DMG.
