#!/usr/bin/env bash
# Build a Release copy of Picnest and pack it into a DMG in build/.
# The DMG holds "Picnest.app", a link to /Applications (for drag and drop), and the license files.
#
# Usage: scripts/make-dmg.sh
#
# Without settings, the app keeps the project's "Sign to Run Locally" signature (ad hoc).
# macOS blocks such a DMG on other Macs until the user clicks Open Anyway (see BUILD.md).
#
# Optional settings (environment variables):
#   SIGN_IDENTITY   "Developer ID Application: <Name> (<TEAMID>)". Signs the app and the DMG.
#   NOTARY_PROFILE  Keychain profile from `xcrun notarytool store-credentials`.
#                   Needs SIGN_IDENTITY. Notarizes and staples the DMG.
#
# The models must be in Models/ first: scripts/fetch-models.sh s2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE="$BUILD_DIR/Picnest.xcarchive"
STAGE="$BUILD_DIR/dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "error: NOTARY_PROFILE needs SIGN_IDENTITY. Apple notarizes only Developer ID signatures." >&2
  exit 1
fi

SIGN_ARGS=()
if [ -n "$SIGN_IDENTITY" ]; then
  # --timestamp is required for notarization. The hardened runtime is already on in project.yml.
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp")
fi

echo "build Release archive"
rm -rf "$ARCHIVE"
xcodebuild archive -quiet \
  -project "$ROOT_DIR/Picnest.xcodeproj" \
  -scheme Picnest \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}

APP="$ARCHIVE/Products/Applications/Picnest.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD_DIR/Picnest $VERSION.dmg"

echo "pack $(basename "$DMG")"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Picnest.app"
ln -s /Applications "$STAGE/Applications"
# The model license requires its notice in each copy of the model files.
cp "$ROOT_DIR/LICENSE" "$STAGE/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGE/THIRD_PARTY_NOTICES.md"
# hdiutil guesses a too small size for the model files ("No space left on device"), so give it 20% more.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) * 12 / 10 + 20 ))
hdiutil create -quiet -volname "Picnest" -srcfolder "$STAGE" -size "${SIZE_MB}m" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ -n "$SIGN_IDENTITY" ]; then
  echo "sign DMG"
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "notarize DMG (this can take some minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "DMG: $DMG"
shasum -a 256 "$DMG"
