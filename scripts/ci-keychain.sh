#!/usr/bin/env bash
# Imports the release signing identity into a throwaway keychain and prints its
# path, for build.sh to read as CLIPSTACK_SIGN_KEYCHAIN.
#
# Inputs (GitHub secrets in CI):
#   CLIPSTACK_CERT_P12        base64 of the "Clipstack Release" .p12
#   CLIPSTACK_CERT_PASSWORD   its password
#
# The identity is self-signed, so it buys no Gatekeeper trust. What it buys is a
# code identity that stays the same from one release to the next, which is what
# macOS keys the Accessibility grant on.
set -euo pipefail

KEYCHAIN="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/clipstack-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
P12="$(mktemp)"
trap 'rm -f "$P12"' EXIT

printf '%s' "$CLIPSTACK_CERT_P12" | base64 --decode > "$P12"

rm -f "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security set-keychain-settings -lut 3600 "$KEYCHAIN" >&2
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$CLIPSTACK_CERT_PASSWORD" -T /usr/bin/codesign >&2
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo "$KEYCHAIN"
