#!/bin/bash
# Drift installer: downloads the latest release, puts it in Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/sparsh1802/drift/main/install.sh | bash
set -euo pipefail

URL="${DRIFT_URL:-https://github.com/sparsh1802/drift/releases/latest/download/Drift.zip}"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "↓ Downloading Drift…"
curl -fsSL "$URL" -o "$TMP/Drift.zip"
ditto -x -k "$TMP/Drift.zip" "$TMP"

pkill -x Drift 2>/dev/null || true
rm -rf "$DEST/Drift.app"
mv "$TMP/Drift.app" "$DEST/"
# Drift isn't notarized by Apple, so clear the download flag that would block it from opening.
xattr -dr com.apple.quarantine "$DEST/Drift.app" 2>/dev/null || true

open "$DEST/Drift.app"
echo "❄ Drift is installed in $DEST and running. Look for the snowflake in your menu bar."
