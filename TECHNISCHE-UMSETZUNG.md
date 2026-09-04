# Technische Umsetzung

Local Flow ist eine native Swift-6-App für macOS 14 und Apple Silicon. Die
Apple-Engine und die Bereinigung brauchen macOS 26.

## Komponenten

- AppKit: Fenster (drei Tabs) und Menüleisten-App
- AVFoundation: Mikrofonaufnahme als 16-kHz-Mono-WAV
- CoreAudio: optionale manuelle Mikrofon-Auswahl
- NSEvent: globale Sprechtaste, Doppeltipp-Erkennung, Esc-Abbruch
- Speech (macOS 26): `SpeechAnalyzer` mit `SpeechTranscriber` de-DE
- whisper.cpp: `whisper-cli` (Whisper Turbo + Silero VAD) und `parakeet-cli`
  (Parakeet TDT v3), je als eigener Prozess; die ggml-Backends liegen neben
  den Tools im Bundle
- FoundationModels (macOS 26): optionale Bereinigung mit dem On-Device-LLM
- CryptoKit: SHA-256-Prüfung heruntergeladener Modelle
- URLSession-Delegate: sichtbarer Download-Fortschritt
- ServiceManagement: Start bei Anmeldung
- ApplicationServices/CGEvent: Einfügen per `Cmd+V`
- UserDefaults: Einstellungen, Wörterbuch und Historie der letzten fünf
  Transkripte
- GitHub Releases API: automatische Prüfung auf eine neuere Version

## Ablauf

```text
Sprechtaste halten (oder doppelt tippen für freihändig)
→ Audio lokal aufnehmen (Esc bricht ab, Stopp nach 5 Minuten)
→ kürzer als 0,4 s? verwerfen, sonst gewählte Engine lokal ausführen
→ Störmarker und Whisper-Halluzinationen entfernen
→ Ersetzungsregeln anwenden
→ optional mit Apple Intelligence bereinigen (Plausibilitätsprüfung)
→ in die 5er-Historie speichern
→ per Zwischenablage einfügen
→ Aufnahme löschen
```

## Portable Distribution

Der Release-Build enthält:

```text
Local Flow.app/
└── Contents/
    ├── MacOS/LocalFlow
    └── Resources/
        ├── whisper/bin/whisper-cli
        ├── whisper/bin/parakeet-cli
        ├── whisper/bin/libggml-*.so (Metal-, CPU- und BLAS-Backends)
        ├── whisper/lib/*.dylib      (libwhisper, libparakeet, libggml, libomp)
        └── licenses/
```

Die dynamischen Bibliothekspfade werden beim Build auf relative `@rpath`
Verweise umgestellt. Empfänger benötigen deshalb kein Homebrew.

Die Modelle liegen bewusst nicht im App-Bundle. Beim ersten Start wird nur,
was die gewählte Engine braucht, heruntergeladen, per SHA-256 geprüft und unter
`~/Library/Application Support/LocalFlow/` gespeichert. Die Apple-Engine nutzt
das deutsche Sprachpaket von macOS; fehlt es, lädt macOS es einmalig selbst.

Ein interner Diagnosemodus ermöglicht Release-Tests mit einem leeren
Modellordner:

```bash
LOCAL_FLOW_MODEL_DIRECTORY=/tmp/local-flow-models \
  LocalFlow --download-model parakeet   # auch: whisperTurbo, vad, small
```

## Tests

Die Tests decken unter anderem ab:

- Modell-Dateien, Download-URLs und Prüfsummen aller Engines
- Engine-Auswahl, Standardwahl je macOS und Migration der alten Einstellung
- Push-to-talk-Zustandsautomat inklusive Freihand-Modus, Abbruch und Stopp
- Doppeltipp-Erkennung
- Ersetzungsregeln, eigene Wörter, Whisper-Prompt
- Aufnahme-Grenzen und Plausibilitätsprüfung der Bereinigung
- Halluzinations-Filter
- freie Tasten, Modifier, `fn`/Globe und Medientasten
- Mikrofon-Auswahl, Transkriptbereinigung und 5er-Historie
- Whisper- und Parakeet-Kommandozeilenargumente

Vor jedem Release:

```bash
./scripts/check-release.sh
./scripts/test-portable-release.sh
./scripts/build-dmg.sh
```
