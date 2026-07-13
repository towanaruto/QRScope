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

# 署名。安定した自己署名アイデンティティがあればそれで署名する。
# こうすると署名要件が証明書リーフに紐付くため、自動アップデートで
# バンドルが入れ替わっても TCC(画面収録などの権限)が維持される。
# 無い場合は ad-hoc にフォールバック(この場合は更新のたびに権限が外れる)。
SIGN_IDENTITY="QRScope Self-Signed"
SIGN_KEYCHAIN="$HOME/Library/Keychains/qrscope-signing.keychain-db"
if [ -f "$SIGN_KEYCHAIN" ] && security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  security unlock-keychain -p "qrscope-build" "$SIGN_KEYCHAIN" 2>/dev/null || true
  codesign --force --identifier com.qrscope.app --keychain "$SIGN_KEYCHAIN" \
    --sign "$SIGN_IDENTITY" "$APP"
  echo "🔏 Signed with stable identity: $SIGN_IDENTITY (permissions persist across updates)"
else
  codesign --force --sign - "$APP"
  echo "⚠️  Ad-hoc signed. Permissions will reset on each update."
  echo "    Run ./Scripts/create-signing-cert.sh once for persistent permissions."
fi

# 配布用 zip(GitHub Release / 自動アップデートのアセット)
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ZIP="build/QRScope-$VERSION.zip"
rm -f "$ZIP"
ditto -ck --keepParent "$APP" "$ZIP"

echo "✅ Built: $APP"
echo "✅ Zipped: $ZIP"
echo "起動: open $APP"
