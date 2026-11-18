#!/bin/bash
# Builds DragFreezeRepro.app next to this script (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=DragFreezeRepro.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/DragFreezeRepro "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DragFreezeRepro</string>
<key>CFBundleIdentifier</key><string>example.DragFreezeRepro</string>
<key>CFBundleName</key><string>DragFreezeRepro</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
