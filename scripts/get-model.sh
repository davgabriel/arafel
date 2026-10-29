#!/bin/zsh
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"   # started with bash or sh: rerun in zsh
# Downloads the depth model (Apple Depth Pro, Core ML, 1.29 GB) from a fixed commit.
# Safe to rerun: complete files are skipped, partial ones resume.
set -euo pipefail
REPO="https://huggingface.co/coreml-projects/DepthPro-coreml-normalized-inverse-depth/resolve/0b779b462b9941e28d411f87e41f9bc80ed7e5d7"
PKG="DepthProNormalizedInverseDepth.mlpackage"
DEST="$HOME/Library/Application Support/Arafel/Models/$PKG"
WEIGHTS_SHA256=93de544fafed202ba499c56a993287de7d348f1db020a414cd8ad10ffeb46390
# path|expected size in bytes
FILES=(
  "Manifest.json|617"
  "Data/com.apple.CoreML/model.mlmodel|740951"
  "Data/com.apple.CoreML/weights/weight.bin|1293014720"
)
for entry in $FILES; do
  rel=${entry%%|*}; want=${entry##*|}
  out="$DEST/$rel"; mkdir -p "${out:h}"
  have=$( [[ -f "$out" ]] && stat -f %z "$out" || echo 0 )
  if [[ "$have" == "$want" ]]; then echo "ok    $rel"; continue; fi
  echo "fetch $rel"
  curl -fL --retry 5 -C - -o "$out" "$REPO/$PKG/$rel"
  have=$(stat -f %z "$out")
  [[ "$have" == "$want" ]] || { echo "FAILED $rel: $have bytes, expected $want"; exit 1; }
done
# Right size, wrong bytes: delete it, or every later run would skip it as complete.
weights="$DEST/Data/com.apple.CoreML/weights/weight.bin"
echo "check weight.bin (about a minute)"
if [[ "$(shasum -a 256 "$weights")" != "$WEIGHTS_SHA256 "* ]]; then
  rm "$weights"
  echo "FAILED weight.bin: checksum mismatch, deleted. Run the script again."; exit 1
fi
echo "Model ready: $DEST"
