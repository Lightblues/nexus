#!/usr/bin/env bash
# ci-signing.sh — Import the stable self-signed identity (SADR-018) into a
# throwaway keychain on a CI runner and export SIGN_IDENTITY / SIGN_KEYCHAIN to
# later steps. Without the secrets (a fork's pull request) it does nothing and
# build-mac.sh signs ad-hoc.
#
# Env: NEXUS_SIGN_P12 (base64 of the .p12), NEXUS_SIGN_P12_PASSWORD, GITHUB_ENV.

set -euo pipefail

if [[ -z "${NEXUS_SIGN_P12:-}" ]]; then
  echo "No signing secret; the build is ad-hoc signed"
  exit 0
fi

DIR="${RUNNER_TEMP:-/tmp}/nexus-signing"
KC="$DIR/sign.keychain-db"
mkdir -p "$DIR" && chmod 700 "$DIR"
KC_PASS=$(openssl rand -hex 16)
echo "$NEXUS_SIGN_P12" | base64 --decode > "$DIR/sign.p12"

security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$DIR/sign.p12" -k "$KC" -P "$NEXUS_SIGN_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
rm -f "$DIR/sign.p12"

# The certificate is self-signed, so find-identity lists it as not trusted;
# codesign signs with it anyway, and the designated requirement pins its hash.
IDENTITY=$(security find-identity -p codesigning "$KC" | awk '/\)/ {print $2; exit}')
[[ -n "$IDENTITY" ]] || { echo "No identity in the imported .p12"; exit 1; }
echo "Signing identity $IDENTITY"
{ echo "SIGN_IDENTITY=$IDENTITY"; echo "SIGN_KEYCHAIN=$KC"; } >> "$GITHUB_ENV"
