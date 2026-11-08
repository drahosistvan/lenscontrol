#!/bin/sh
# Builds a release binary with SwiftPM and wraps it in a minimal .app bundle
# (needed for LSUIElement so the app lives in the menu bar without a Dock icon).
set -eu
cd "$(dirname "$0")"

swift build -c release --product LensControl

APP=build/LensControl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LensControl "$APP/Contents/MacOS/LensControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon: drawn as vector at every size by Tools/MakeIcon.swift, then packed.
ICONSET=build/LensControl.iconset
rm -rf "$ICONSET"
swift Tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS runs it locally without complaint.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
echo "Run:      open $APP"
echo "Install:  cp -R $APP /Applications/"
