#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

FORBIDDEN_TRACKED_PATTERN='(^|/)(\.env($|\.)|private|credentials|secrets|release-private)(/|$)|\.(key|pem|p12|mobileprovision|bin|wav|mp3|m4a)$'
SECRET_PATTERN='(api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd|private[_-]?key|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|sk-[A-Za-z0-9]{16,})'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tracked_files="$(git ls-files)"
    if print -r -- "$tracked_files" | grep -Eiq "$FORBIDDEN_TRACKED_PATTERN"; then
        echo "Abbruch: Eine private oder generierte Datei wird von Git verfolgt." >&2
        print -r -- "$tracked_files" | grep -Ei "$FORBIDDEN_TRACKED_PATTERN" >&2
        exit 1
    fi
fi

if rg --hidden -n -i "$SECRET_PATTERN" \
    -g '!/.git/**' \
    -g '!/.build/**' \
    -g '!/build/**' \
    -g '!/dist/**' \
    -g '!scripts/check-release.sh' \
    .; then
    echo "Abbruch: Möglicher Schlüssel oder Zugangswert gefunden." >&2
    exit 1
fi

swift test

echo "Release-Check bestanden."
