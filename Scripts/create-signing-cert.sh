#!/bin/bash
# QRScope 配布用の「安定した」自己署名コード署名証明書を作成する。
#
# なぜ必要か:
#   ad-hoc 署名(codesign -s -)はビルドごとに cdhash が変わるため、macOS の
#   TCC が毎回「別アプリ」と見なし、自動アップデートのたびに画面収録などの
#   権限が失われる。安定した証明書で署名すると、署名要件が証明書リーフに
#   紐付くので再ビルドしても同一とみなされ、権限が維持される。
#
# 使い方: リリースをビルドするマシンで一度だけ実行する(冪等)。
#   秘密鍵は専用キーチェーンに残り、以降 build-app.sh が自動で使う。
set -euo pipefail

IDENTITY="QRScope Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/qrscope-signing.keychain-db"
KEYCHAIN_PASSWORD="qrscope-build"

if [ -f "$KEYCHAIN" ] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✅ Signing identity already exists: $IDENTITY"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# コード署名用途の自己署名証明書(20年)を生成
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 7300 -config "$TMP/openssl.cnf" >/dev/null 2>&1
# 空パスワードの p12 は macOS の security import が MAC 検証に失敗するため、
# 実パスワードを付ける
P12_PASSWORD="qrscope"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

# login キーチェーンには触れず、専用キーチェーンに入れる
# (パスワードが分かっているので partition list を無対話で設定できる)
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" 2>/dev/null || true
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # 自動ロックを無効化

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -A
# codesign が鍵を無警告で使えるようにする
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1

# codesign が見つけられるよう検索リストへ追加(既存はそのまま残す)
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo "✅ Created signing identity: $IDENTITY"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY" || true
