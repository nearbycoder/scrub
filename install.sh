#!/bin/bash
# Scrub installer: downloads the latest release (signed with Developer ID and notarized by Apple)
# and installs it to /Applications.
#   curl -fsSL https://raw.githubusercontent.com/nearbycoder/scrub/main/install.sh | bash
set -euo pipefail

REPO="nearbycoder/scrub"
URL="https://github.com/$REPO/releases/latest/download/Scrub.zip"
DEST="/Applications"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

if [[ "$(uname)" != "Darwin" ]]; then echo "Scrub only runs on macOS."; exit 1; fi
major=$(sw_vers -productVersion | cut -d. -f1)
if (( major < 26 )); then echo "Scrub needs macOS 26 Tahoe or later (you have $(sw_vers -productVersion))."; exit 1; fi

[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold "Downloading Scrub…"
curl -fL --progress-bar "$URL" -o "$tmp/Scrub.zip"
ditto -x -k "$tmp/Scrub.zip" "$tmp"

if pgrep -x Scrub >/dev/null; then osascript -e 'quit app "Scrub"' || true; sleep 1; fi
rm -rf "$DEST/Scrub.app"
mv "$tmp/Scrub.app" "$DEST/Scrub.app"
spctl -a -t exec "$DEST/Scrub.app" 2>/dev/null || echo "Warning: Gatekeeper could not verify Scrub's notarization."

bold "Installed Scrub to $DEST/Scrub.app"
open "$DEST/Scrub.app"
