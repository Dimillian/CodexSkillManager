#!/usr/bin/env bash
set -euo pipefail

APP_NAME=${APP_NAME:-CodexSkillManager}
APP_IDENTITY=${APP_IDENTITY:-"Developer ID Application: Example (TEAMID)"}
APP_BUNDLE="${APP_NAME}.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-"https://raw.githubusercontent.com/Dimillian/CodexSkillManager/main/appcast.xml"}

if [[ -z "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  echo "Missing SPARKLE_PUBLIC_KEY env var. Sparkle will not be enabled without it." >&2
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi

if [[ -f "$APP_STORE_CONNECT_API_KEY_P8" ]]; then
  cp "$APP_STORE_CONNECT_API_KEY_P8" /tmp/app-store-connect-key.p8
else
  echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/app-store-connect-key.p8
fi
trap 'rm -f /tmp/app-store-connect-key.p8 /tmp/${APP_NAME}Notarize.zip' EXIT

ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
ARCHES="${ARCHES_VALUE}" \
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY}" \
SPARKLE_FEED_URL="${SPARKLE_FEED_URL}" \
"$ROOT/Scripts/package_app.sh" release

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-${ENTITLEMENTS_DIR}/${APP_NAME}.entitlements}"

codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_BUNDLE"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
  --key /tmp/app-store-connect-key.p8 \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_BUNDLE"

xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Done: $ZIP_NAME"
