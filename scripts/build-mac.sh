#!/usr/bin/env bash
# build-mac.sh — Build a universal-binary, ad-hoc-signed DMG of Nexus.
#
# Usage:
#   ./scripts/build-mac.sh                  # uses Info.plist's CFBundleShortVersionString
#   VERSION=1.0.0 ./scripts/build-mac.sh    # override version
#
# Output:
#   dist/Nexus-<version>.dmg
#   dist/Nexus-<version>.dmg.sha256
#
# Why no create-dmg dependency?
#   `hdiutil` ships with macOS and produces a fully valid DMG. create-dmg adds
#   nothing essential for a single-app drop install (and is a Homebrew dep we
#   don't want to require on CI).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/build"

# Resolve version: env var > project.yml > "0.0.0"
if [[ -z "${VERSION:-}" ]]; then
  VERSION=$(awk -F'"' '/CFBundleShortVersionString/ {print $2; exit}' \
    "$PROJECT_DIR/project.yml" 2>/dev/null || echo "")
  VERSION="${VERSION:-0.0.0}"
fi
echo "==> Building Nexus v$VERSION"

# Generate xcodeproj fresh so it tracks any new files since last build.
echo "==> xcodegen generate"
(cd "$PROJECT_DIR" && xcodegen generate >/dev/null)

# Downgrade objectVersion if XcodeGen emitted a "future" format. Newer Xcode
# (e.g. macOS 26 Tahoe beta ships format 77) generates a project that older
# Xcode on CI runners refuses with "future Xcode project file format".
# Pinning to 56 keeps compatibility with Xcode 15.0+.
PBXPROJ="$PROJECT_DIR/Nexus.xcodeproj/project.pbxproj"
if [[ -f "$PBXPROJ" ]]; then
  CURRENT=$(awk '/objectVersion = / {gsub(";",""); print $3; exit}' "$PBXPROJ")
  if [[ -n "$CURRENT" && "$CURRENT" -gt 56 ]]; then
    echo "==> Downgrading objectVersion $CURRENT → 56 for CI compat"
    sed -i.bak 's/objectVersion = [0-9]*;/objectVersion = 56;/' "$PBXPROJ"
    rm -f "$PBXPROJ.bak"
  fi
fi

# Clean previous build artifacts. Keep $DIST_DIR contents from earlier
# versions so the user can compare; we just overwrite our specific filename.
rm -rf "$BUILD_DIR/archive" "$BUILD_DIR/export"
mkdir -p "$DIST_DIR" "$BUILD_DIR/archive" "$BUILD_DIR/export"

# Archive (Release, universal). Using `archive` instead of `build` so the
# resulting .xcarchive is what xcodebuild -exportArchive expects.
echo "==> xcodebuild archive (Release, arm64+x86_64)"
xcodebuild \
  -project "$PROJECT_DIR/Nexus.xcodeproj" \
  -scheme Nexus \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/archive/Nexus.xcarchive" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  archive | grep -E "^\*\* |error:|warning:" || true

# Export from the archive into a plain .app bundle.
# We use a minimal exportOptions plist that asks for "developer-id" style
# layout but with no signing identity (so the existing ad-hoc signature stays).
EXPORT_OPTIONS="$BUILD_DIR/archive/exportOptions.plist"
cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>mac-application</string>
  <key>signingStyle</key>
  <string>manual</string>
</dict>
</plist>
PLIST

echo "==> xcodebuild -exportArchive"
xcodebuild \
  -exportArchive \
  -archivePath "$BUILD_DIR/archive/Nexus.xcarchive" \
  -exportPath  "$BUILD_DIR/export" \
  -exportOptionsPlist "$EXPORT_OPTIONS" >/dev/null

APP_PATH="$BUILD_DIR/export/Nexus.app"
[[ -d "$APP_PATH" ]] || { echo "Export failed: $APP_PATH not found"; exit 1; }

# Re-apply ad-hoc signature deeply. xcodebuild already signs but we re-sign
# explicitly so the resulting bundle is self-consistent regardless of whatever
# signing identity was active in the user's keychain.
echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH" || true   # sanity check

# Verify universal arch
echo "==> Architecture check"
lipo -info "$APP_PATH/Contents/MacOS/Nexus"

# --- DMG packaging ---
DMG_PATH="$DIST_DIR/Nexus-$VERSION.dmg"
STAGE_DIR="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/Nexus.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "Nexus $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

# Compute sha256 alongside the DMG so CI can post it without recomputing.
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA  $(basename "$DMG_PATH")" > "$DMG_PATH.sha256"

# Cleanup staging
rm -rf "$STAGE_DIR"

# Summary
echo ""
echo "  ✓ DMG:    $DMG_PATH"
echo "  ✓ size:   $(du -h "$DMG_PATH" | awk '{print $1}')"
echo "  ✓ sha256: $SHA"
