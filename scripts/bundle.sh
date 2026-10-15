#!/bin/zsh
set -e

cd "$(dirname "$0")/.."

echo "==> Building AppIcon..."
if [ ! -f "Resources/AppIcon.icns" ]; then
  ./scripts/make_icon.sh
fi

echo "==> Building Pulse (Release)..."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

swift build -c release

APP_DIR="build/Pulse.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/Pulse "$APP_DIR/Contents/MacOS/Pulse"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Pulse</string>
  <key>CFBundleDisplayName</key>
  <string>Pulse</string>
  <key>CFBundleIdentifier</key>
  <string>com.rizak.pulse</string>
  <key>CFBundleExecutable</key>
  <string>Pulse</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "==> Signing Pulse.app..."
codesign --force --sign - "$APP_DIR"

echo "✅ Successfully built $PWD/$APP_DIR"
