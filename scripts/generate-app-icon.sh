#!/usr/bin/env bash
# generate-app-icon.sh — Slice a 1024×1024 source PNG into the 10 sizes
# Xcode's AppIcon.appiconset expects, and rewrite Contents.json to reference
# them.
#
# Usage:
#   ./scripts/generate-app-icon.sh                     # uses ./build/icon.png
#   ./scripts/generate-app-icon.sh path/to/source.png  # custom source
#
# Source image must be ≥ 1024×1024 PNG. We use macOS's `sips` (pre-installed,
# zero deps) for resampling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="${1:-$PROJECT_DIR/build/icon.png}"
DEST="$PROJECT_DIR/Nexus/Resources/Assets.xcassets/AppIcon.appiconset"

[[ -f "$SRC" ]] || { echo "Source icon not found: $SRC"; exit 1; }
mkdir -p "$DEST"

# AppIcon spec: (logical_size, scale) → actual_pixels filename.
# Xcode expects exactly this set for a macOS appiconset.
declare -a SLICES=(
  "16  1x icon_16x16.png"
  "16  2x icon_16x16@2x.png"
  "32  1x icon_32x32.png"
  "32  2x icon_32x32@2x.png"
  "128 1x icon_128x128.png"
  "128 2x icon_128x128@2x.png"
  "256 1x icon_256x256.png"
  "256 2x icon_256x256@2x.png"
  "512 1x icon_512x512.png"
  "512 2x icon_512x512@2x.png"
)

echo "==> Slicing $SRC → $DEST"
for spec in "${SLICES[@]}"; do
  read -r LOGICAL SCALE FILENAME <<<"$spec"
  PIXELS=$LOGICAL
  [[ "$SCALE" == "2x" ]] && PIXELS=$((LOGICAL * 2))
  sips -s format png -z "$PIXELS" "$PIXELS" "$SRC" \
       --out "$DEST/$FILENAME" >/dev/null
  printf "    %-25s %dx%d\n" "$FILENAME" "$PIXELS" "$PIXELS"
done

# Rewrite Contents.json with filename references.
echo "==> Writing Contents.json"
cat > "$DEST/Contents.json" <<'JSON'
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16x16.png" },
    { "idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_16x16@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32x32.png" },
    { "idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_32x32@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png" },
    { "idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png" },
    { "idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png" },
    { "idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png" },
    { "idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON

echo ""
echo "  ✓ AppIcon assets written to $DEST"
echo "  ✓ Next: ./scripts/build-mac.sh   (or rebuild in Xcode) to bake icon into the .app"
