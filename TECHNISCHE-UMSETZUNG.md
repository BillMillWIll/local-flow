# Technische Umsetzung

Local Flow ist eine native Swift-6-App für macOS 14 und Apple Silicon.

## Komponenten

- AppKit: Fenster und Menüleisten-App
- AVFoundation: Mikrofonaufnahme als 16-kHz-Mono-WAV
- CoreAudio: optionale manuelle Mikrofon-Auswahl
- NSEvent: globale Push-to-talk-Taste und Tastenlernen
- whisper.cpp: lokale deutsche Transkription
- CryptoKit: SHA-256-Prüfung heruntergeladener Modelle
- URLSession-Delegate: sichtbarer Download-Fortschritt
- ApplicationServices/CGEvent: Einfügen per `Cmd+V`
- UserDefaults: Einstellungen und Historie der letzten fünf Transkripte
- GitHub Releases API: automatische Prüfung auf eine neuere Version

## Ablauf

```text
Sprechtaste halten
→ Audio lokal aufnehmen
→ ausgewähltes Whisper-Modell lokal ausführen
→ Transkript bereinigen
→ in die 5er-Historie speichern
→ per Zwischenablage einfügen
```

## Portable Distribution

Der Release-Build enthält:

```text
Local Flow.app/
└── Contents/
    ├── MacOS/LocalFlow
    └── Resources/
        ├── whisper/bin/whisper-cli
        ├── whisper/lib/*.dylib
        └── licenses/
```

Die dynamischen Bibliothekspfade werden beim Build auf relative `@rpath`
Verweise umgestellt. Empfänger benötigen deshalb kein Homebrew.

Die Modelle liegen bewusst nicht im App-Bundle. Beim ersten Start wird nur das
ausgewählte fehlende Modell heruntergeladen, per SHA-256 geprüft und unter
`~/Library/Application Support/LocalFlow/` gespeichert.

Die Download-Adresse enthält eine feste Hugging-Face-Commit-ID. Fehler zeigen
einen erneuten Download-Button. Ein interner Diagnosemodus ermöglicht
Release-Tests mit einem leeren Modellordner:

```bash
LOCAL_FLOW_MODEL_DIRECTORY=/tmp/local-flow-models \
  LocalFlow --download-model small
```

## Tests

Die Tests decken unter anderem ab:

- Modell-Dateien, Download-URLs und Prüfsummen
- Push-to-talk-Zustandsautomat
- freie Tasten, Modifier, `fn`/Globe und Medientasten
- Mikrofon-Auswahl
- Transkriptbereinigung und 5er-Historie
- Whisper-Kommandozeilenargumente

Vor jedem Release:

```bash
./scripts/check-release.sh
./scripts/test-portable-release.sh
./scripts/build-dmg.sh
```
