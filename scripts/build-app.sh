#!/bin/sh
# Build HerdrBar.app from the Swift package (no Xcode project needed).
#
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)" to sign for distribution.
#                   Unset = ad-hoc signature (runs locally; installers must clear quarantine).
set -eu
cd "$(dirname "$0")/.."
CONF="${1:-release}"
swift build -c "$CONF" >/dev/null 2>&1 || { swift build -c "$CONF" 2>&1 | tail -30; echo "BUILD FAILED"; exit 1; }
BIN="$(swift build -c "$CONF" --show-bin-path)/HerdrBar"
APP="build/Herdr Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HerdrBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Design/icons/app/HerdrBar.icns "$APP/Contents/Resources/HerdrBar.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --identifier me.bagus.herdrbar "$APP"
  echo "signed with: $SIGN_IDENTITY"
else
  codesign --force --sign - --identifier me.bagus.herdrbar "$APP"
  echo "signed: ad hoc (set SIGN_IDENTITY for Developer ID)"
fi
codesign --verify --strict "$APP"
echo "built: $APP"
