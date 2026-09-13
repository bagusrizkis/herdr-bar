#!/bin/sh
# Herdr Bar installer - curl -fsSL https://raw.githubusercontent.com/bagusrizkis/herdr-bar/main/install.sh | sh
# Downloads the latest release DMG, copies Herdr Bar.app to /Applications, and launches it.
set -eu

REPO="bagusrizkis/herdr-bar"
APP_NAME="Herdr Bar.app"
DEST="${HERDRBAR_INSTALL_DIR:-/Applications}"

say() { printf '%s\n' "$*"; }
fail() { say "error: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Herdr Bar is a macOS app."
[ "$(uname -m)" = "arm64" ] || fail "Herdr Bar ships Apple Silicon builds only for now."
command -v herdr >/dev/null 2>&1 || say "note: herdr was not found in PATH. Install it from https://herdr.dev first."

say "Looking up the latest release..."
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$TAG" ] || fail "could not determine the latest release."
VERSION="${TAG#v}"
URL="https://github.com/${REPO}/releases/download/${TAG}/HerdrBar-${VERSION}.dmg"

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

say "Downloading Herdr Bar ${VERSION}..."
curl -fsSL "$URL" -o "$TMP/HerdrBar.dmg"
MOUNT="$(hdiutil attach "$TMP/HerdrBar.dmg" -nobrowse -readonly -mountrandom "$TMP" | awk -F'\t' '/\/Volumes|\/private/ {print $NF}' | tail -1)"
[ -d "$MOUNT/$APP_NAME" ] || fail "DMG did not contain $APP_NAME."

if pgrep -x HerdrBar >/dev/null 2>&1; then
  say "Quitting the running Herdr Bar..."
  pkill -x HerdrBar || true
  sleep 1
fi

say "Installing to ${DEST}..."
rm -rf "$DEST/$APP_NAME"
cp -R "$MOUNT/$APP_NAME" "$DEST/"

open "$DEST/$APP_NAME"
say "Done. Herdr Bar ${VERSION} is in your menu bar."
