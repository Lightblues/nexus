#!/bin/bash
# Install Nexus from GitHub Release
# Usage: ./install-release.sh [version]
# If no version specified, reads from package.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_JSON="${SCRIPT_DIR}/../package.json"
REPO="Lightblues/easons_agent"
APP_NAME="Nexus"
DMG_NAME="Nexus"
INSTALL_PATH="/Applications/${APP_NAME}.app"
TMP_DIR=$(mktemp -d)

cleanup() {
  echo "Cleaning up..."
  hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Get version from argument or package.json
if [ -n "$1" ]; then
  VERSION="$1"
elif [ -f "$PACKAGE_JSON" ]; then
  VERSION=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
  echo "Read version ${VERSION} from package.json"
else
  echo "Error: No version specified and package.json not found"
  exit 1
fi

DMG_PATH="${TMP_DIR}/${DMG_NAME}.dmg"
ASSET_NAME="${DMG_NAME}-${VERSION}-arm64.dmg"
TAG="nexus-v${VERSION}"

echo "Installing ${APP_NAME} v${VERSION}..."

# Download using gh CLI (handles auth and redirects properly)
if command -v gh &>/dev/null; then
  echo "Downloading ${ASSET_NAME} via gh CLI..."
  gh release download "$TAG" --repo "$REPO" --pattern "$ASSET_NAME" --dir "$TMP_DIR"
  mv "${TMP_DIR}/${ASSET_NAME}" "$DMG_PATH"
else
  # Fallback to curl with proper headers
  echo "gh CLI not found, using curl..."
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
  echo "Downloading from: $DOWNLOAD_URL"
  curl -L -H "Accept: application/octet-stream" -o "$DMG_PATH" "$DOWNLOAD_URL"
fi

# Check file size
FILE_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH" 2>/dev/null)
if [ "$FILE_SIZE" -lt 1000000 ]; then
  echo "Error: Downloaded file too small (${FILE_SIZE} bytes). Release may not be ready."
  echo "Check: https://github.com/${REPO}/releases/tag/${TAG}"
  exit 1
fi
echo "Downloaded: $(echo "scale=1; $FILE_SIZE/1048576" | bc)MB"

# Mount DMG
echo "Mounting DMG..."
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse | grep "/Volumes" | cut -f3)
if [ -z "$MOUNT_POINT" ]; then
  echo "Error: Failed to mount DMG"
  exit 1
fi
echo "Mounted at: $MOUNT_POINT"

# Kill running app if exists
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "Stopping running ${APP_NAME}..."
  pkill -x "$APP_NAME" || true
  sleep 1
fi

# Remove old version
if [ -d "$INSTALL_PATH" ]; then
  echo "Removing old version..."
  rm -rf "$INSTALL_PATH"
fi

# Copy new version
echo "Installing to ${INSTALL_PATH}..."
cp -R "${MOUNT_POINT}/${APP_NAME}.app" /Applications/

# Clear quarantine attribute
echo "Clearing quarantine attribute..."
xattr -c "$INSTALL_PATH"

echo ""
echo "✅ ${APP_NAME} v${VERSION} installed successfully!"
echo "   You can now open it from Applications or run:"
echo "   open '/Applications/${APP_NAME}.app'"
