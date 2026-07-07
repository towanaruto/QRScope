#!/bin/bash
# QRScope.app バンドルをビルドする
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/QRScope.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/QRScope "$APP/Contents/MacOS/QRScope"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# ad-hoc 署名(再ビルド後は画面収録の許可が再度必要になる場合あり)
codesign --force --sign - "$APP"

echo "✅ Built: $APP"
echo "起動: open $APP"
