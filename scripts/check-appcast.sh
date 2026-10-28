#!/usr/bin/env bash
# Fail when the published appcast, or a file that it points at, is not available.
#
# Usage: scripts/check-appcast.sh [appcast-url]
#
# Run this after you upload the archives and publish docs/appcast.xml (see BUILD.md). It downloads the feed,
# reads every enclosure URL (the full archives and the delta files), and sends 1 HEAD request to each.
# The exit code is 0 only when the feed and all enclosures answer with a 2xx status after redirects.
#
# Settings:
#   APPCAST_URL  The feed to check. Default: the feed in SUFeedURL of project.yml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

URL="${1:-${APPCAST_URL:-}}"
if [ -z "$URL" ]; then
  URL="$(awk '/SUFeedURL:/{print $2; exit}' "$ROOT_DIR/project.yml")"
fi
[ -n "$URL" ] || { echo "error: No appcast URL." >&2; exit 2; }

feed="$(mktemp)"
trap 'rm -f "$feed"' EXIT

echo "feed  $URL"
if ! curl -fsSL --retry 2 -o "$feed" "$URL"; then
  echo "FAIL  the appcast is not available" >&2
  exit 1
fi

# Every enclosure has a url="..." attribute.
enclosures="$(grep -o '<enclosure[^>]*' "$feed" | sed -n 's/.*[[:space:]]url="\([^"]*\)".*/\1/p')"
if [ -z "$enclosures" ]; then
  echo "FAIL  the appcast has no enclosure" >&2
  exit 1
fi

failed=0
while IFS= read -r enclosure; do
  if curl -fsSIL --retry 2 -o /dev/null "$enclosure"; then
    echo "ok    $enclosure"
  else
    echo "FAIL  $enclosure" >&2
    failed=$((failed + 1))
  fi
done <<< "$enclosures"

if [ "$failed" -gt 0 ]; then
  echo "$failed enclosure URL(s) are not available." >&2
  exit 1
fi
echo "The appcast and all enclosures are available."
