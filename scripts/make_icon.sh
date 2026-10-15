#!/bin/zsh
# Builds Resources/AppIcon.icns from scripts/make_icon.swift.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

mkdir -p Resources
swiftc -O scripts/make_icon.swift -o .build/make_icon
.build/make_icon Resources/AppIcon-1024.png

SET=.build/AppIcon.iconset
rm -rf $SET && mkdir -p $SET
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out $SET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon-1024.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $SET -o Resources/AppIcon.icns
echo "✅ Resources/AppIcon.icns"
