#!/bin/zsh
set -e

cd "$(dirname "$0")/.."

echo "==> Building Pulse release..."
./scripts/bundle.sh

echo "==> Quitting existing Pulse..."
pkill -f "Pulse.app/Contents/MacOS/Pulse" || true
sleep 1

DEST="/Applications/Pulse.app"
echo "==> Installing to $DEST..."
rm -rf "$DEST"
cp -R build/Pulse.app "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "==> Launching $DEST..."
open "$DEST"

echo "🎉 Pulse is now installed in /Applications/Pulse.app and running!"
