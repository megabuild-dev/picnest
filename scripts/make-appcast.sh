#!/usr/bin/env bash
# Build docs/appcast.xml, the update feed that Sparkle reads, from the update archives in build/updates/.
#
# Usage: scripts/make-appcast.sh
#
# Put every new DMG in build/updates/. This script copies the newest one from build/ for you.
# Keep the old DMGs in that folder: Sparkle builds the delta files from them, so an update stays small.
# After this script runs, upload every file in build/updates/ to the GitHub release that
# DOWNLOAD_URL_PREFIX points at. See BUILD.md.
#
# The script signs each item with the EdDSA key in the login Keychain, so it may ask for the Keychain password.
#
# Settings (environment variables):
#   DOWNLOAD_URL_PREFIX  Where the archives are hosted. Default: the "updates" release of this repo.
#   SPARKLE_BIN          The folder with generate_appcast. Default: the package folder in Xcode's build folder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATES_DIR="$ROOT_DIR/build/updates"
APPCAST="$ROOT_DIR/docs/appcast.xml"
PROJECT_URL="https://github.com/megabuild-dev/picnest"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/megabuild-dev/picnest/releases/download/updates/}"
SPARKLE_BIN="${SPARKLE_BIN:-}"

if [ -z "$SPARKLE_BIN" ]; then
  # Xcode writes the package artifacts next to its build folder.
  BUILD_DIR="$(xcodebuild -project "$ROOT_DIR/Picnest.xcodeproj" -scheme Picnest -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/ BUILD_DIR = /{print $2; exit}')"
  SPARKLE_BIN="$BUILD_DIR/../../SourcePackages/artifacts/sparkle/Sparkle/bin"
fi

GENERATE="$SPARKLE_BIN/generate_appcast"
if [ ! -x "$GENERATE" ]; then
  echo "error: No generate_appcast at $GENERATE." >&2
  echo "Run this first, or set SPARKLE_BIN to the bin folder of a Sparkle release:" >&2
  echo "  xcodebuild -resolvePackageDependencies -project Picnest.xcodeproj -scheme Picnest" >&2
  exit 1
fi

mkdir -p "$UPDATES_DIR"

# Keep the published feed, so a fresh clone with an empty build folder still lists the old versions.
if [ ! -f "$UPDATES_DIR/appcast.xml" ] && [ -f "$APPCAST" ]; then
  echo "seed  appcast.xml from docs/"
  cp "$APPCAST" "$UPDATES_DIR/appcast.xml"
fi

# The DMG that scripts/make-dmg.sh wrote in build/, if the archive folder does not hold it yet.
for dmg in "$ROOT_DIR"/build/*.dmg; do
  [ -e "$dmg" ] || continue
  name="$(basename "$dmg")"
  if [ ! -e "$UPDATES_DIR/$name" ]; then
    echo "add   $name"
    cp "$dmg" "$UPDATES_DIR/$name"
  fi
done

# A <name>.md file beside an archive becomes the release notes of that item.
echo "sign  the archives and generate the appcast"
"$GENERATE" --download-url-prefix "$DOWNLOAD_URL_PREFIX" --link "$PROJECT_URL" "$UPDATES_DIR"

echo "copy  appcast.xml to docs/"
cp "$UPDATES_DIR/appcast.xml" "$APPCAST"

echo "Appcast: $APPCAST"
echo "Upload every file below to $DOWNLOAD_URL_PREFIX"
ls -1 "$UPDATES_DIR"
