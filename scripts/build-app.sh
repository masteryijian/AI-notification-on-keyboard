#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_DESTINATION:-$PROJECT_ROOT/dist/Pixiu Agent LED.app}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$PROJECT_ROOT"
swift build -c release

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
install -m 755 ".build/release/pixiu-led" "$APP_PATH/Contents/MacOS/pixiu-led"
install -m 644 "AppBundle/Info.plist" "$APP_PATH/Contents/Info.plist"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "App erstellt: $APP_PATH"

