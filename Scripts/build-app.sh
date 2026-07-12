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

# 配布用 zip(GitHub Release / 自動アップデートのアセット)
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ZIP="build/QRScope-$VERSION.zip"
rm -f "$ZIP"
ditto -ck --keepParent "$APP" "$ZIP"

echo "✅ Built: $APP"
echo "✅ Zipped: $ZIP"
echo "起動: open $APP"
