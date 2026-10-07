#!/bin/zsh
set -eu
cd "${0:A:h:h}"
ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) print -u2 "Usage: $0 [arm64|x86_64]"; exit 1 ;;
esac
swift build --scratch-path ".build/$ARCH" -c release --triple "$ARCH-apple-macosx14.0"
BIN_DIR="$(swift build --scratch-path ".build/$ARCH" -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)"
VERSION="$(tr -d '\n' < VERSION)"
APP="$PWD/dist/Memory Atlas.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MemoryAtlas" "$APP/Contents/MacOS/MemoryAtlas"
cp Resources/atlas.py Resources/demo.json "$APP/Contents/Resources/"
cp scripts/fixtures/claude-mem-13.29.0.sql "$APP/Contents/Resources/demo-schema.sql"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/licenses"
cp docs/licenses/* "$APP/Contents/Resources/licenses/"
mkdir -p .build/Atlas.iconset
swift scripts/icon.swift "$PWD/.build/Atlas.iconset"
iconutil -c icns .build/Atlas.iconset -o "$APP/Contents/Resources/Atlas.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.huy.memory-atlas</string>
<key>CFBundleName</key><string>Memory Atlas</string>
<key>CFBundleDisplayName</key><string>Memory Atlas</string>
<key>CFBundleExecutable</key><string>MemoryAtlas</string>
<key>CFBundleIconFile</key><string>Atlas</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
print "Built $APP"
