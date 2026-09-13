#!/bin/sh
# Package build/Herdr Bar.app into a DMG with an Applications shortcut.
#
#   SIGN_IDENTITY   Developer ID identity; when set, the DMG itself is signed too.
#   NOTARY_PROFILE  notarytool keychain profile name (created once with
#                   `xcrun notarytool store-credentials <name> --apple-id ... --team-id ... --password <app-specific>`).
#                   When set, the DMG is submitted for notarization and stapled.
set -eu
cd "$(dirname "$0")/.."
APP="build/Herdr Bar.app"
[ -d "$APP" ] || scripts/build-app.sh release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="build/HerdrBar-$VERSION.dmg"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Herdr Bar" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "notarizing (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
  spctl -a -t open --context context:primary-signature -v "$OUT" 2>&1 | tail -1
fi

shasum -a 256 "$OUT" | tee "$OUT.sha256"
echo "dmg: $OUT"
