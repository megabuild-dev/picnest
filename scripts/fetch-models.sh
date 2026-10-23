#!/usr/bin/env bash
# Download the MobileCLIP Core ML models from Hugging Face (apple/coreml-mobileclip)
# into Models/. Files that already exist are skipped.
#
# Usage: scripts/fetch-models.sh [s0 s1 s2 blt]   (default: all four sizes)
#
# The Hugging Face repo stores each model as an unzipped .mlpackage directory:
#   mobileclip_<size>_<image|text>.mlpackage/
#     Manifest.json
#     Data/com.apple.CoreML/model.mlmodel
#     Data/com.apple.CoreML/weights/weight.bin
# The "B" size is published as "blt" (MobileCLIP-B with LT training).
set -euo pipefail

REPO_URL="https://huggingface.co/apple/coreml-mobileclip/resolve/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$SCRIPT_DIR/../Models}"
FILES=(
  "Manifest.json"
  "Data/com.apple.CoreML/model.mlmodel"
  "Data/com.apple.CoreML/weights/weight.bin"
)

if [ "$#" -gt 0 ]; then SIZES=("$@"); else SIZES=(s0 s1 s2 blt); fi

mkdir -p "$MODELS_DIR"

for size in "${SIZES[@]}"; do
  for kind in image text; do
    pkg="mobileclip_${size}_${kind}.mlpackage"
    for file in "${FILES[@]}"; do
      dest="$MODELS_DIR/$pkg/$file"
      if [ -s "$dest" ]; then
        echo "skip  $pkg/$file"
        continue
      fi
      mkdir -p "$(dirname "$dest")"
      echo "fetch $pkg/$file"
      curl -fL --retry 3 -o "$dest.part" "$REPO_URL/$pkg/$file"
      mv "$dest.part" "$dest"
    done
  done
done

echo "Models are in $(cd "$MODELS_DIR" && pwd)"
