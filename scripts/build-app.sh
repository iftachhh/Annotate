#!/bin/bash
# Builds build/Annotate.app for this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Annotate.app"
BIN="Annotate"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/* "$APP/Contents/Resources/"
# Liquid Glass icon (Assets.car) on macOS 26+, plus an .icns fallback for older systems
xcrun actool icon/AnnotationPen.icon --compile "$APP/Contents/Resources" --app-icon AnnotationPen \
    --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist /dev/null >/dev/null

echo "Built $APP"
