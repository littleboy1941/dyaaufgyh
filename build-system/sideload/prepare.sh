#!/bin/bash
# Prepares a sideload build: configuration with our own bundle id / API keys and
# fake provisioning profiles rewritten for that bundle id.
#
# Usage: prepare.sh <output-dir>
# Env:   TELEGRAM_API_ID, TELEGRAM_API_HASH
#
# Must run on macOS after ImportCertificates.py (needs the SelfSigned identity in temp.keychain).

set -euo pipefail

BUNDLE_ID="com.ayugram.client"
# Fake team id; SideStore re-signs the app with the user's personal team anyway.
TEAM_ID="C67CF9S4VU"
OFFICIAL_BUNDLE_ID="ph.telegra.Telegraph"

OUT="$1"
SRC="build-system/fake-codesigning"

: "${TELEGRAM_API_ID:?TELEGRAM_API_ID is not set}"
: "${TELEGRAM_API_HASH:?TELEGRAM_API_HASH is not set}"

rm -rf "$OUT"
mkdir -p "$OUT/codesigning/profiles" "$OUT/codesigning/certs"
cp "$SRC"/certs/* "$OUT/codesigning/certs/"

python3 - "$OUT/configuration.json" "$BUNDLE_ID" "$TEAM_ID" <<'EOF'
import json, os, sys
path, bundle_id, team_id = sys.argv[1:4]
json.dump({
    "bundle_id": bundle_id,
    "api_id": os.environ["TELEGRAM_API_ID"],
    "api_hash": os.environ["TELEGRAM_API_HASH"],
    "team_id": team_id,
    "app_center_id": "0",
    "is_internal_build": "false",
    "is_appstore_build": "false",
    "appstore_id": "0",
    "app_specific_url_scheme": "tg",
    "premium_iap_product_id": "",
    "enable_siri": False,
    "enable_icloud": False,
}, open(path, "w"), indent=2)
EOF

# Only the main app profile: extensions are disabled in .bazelrc.
PLIST="$(mktemp)"
security cms -D -i "$SRC/profiles/Telegram.mobileprovision" > "$PLIST"
sed -i '' "s/$OFFICIAL_BUNDLE_ID/$BUNDLE_ID/g" "$PLIST"
# No push notifications on a free Apple ID.
plutil -remove Entitlements.aps-environment "$PLIST" || true
plutil -remove DER-Encoded-Profile "$PLIST" || true

security find-identity -v temp.keychain
IDENTITY="$(security find-identity -v temp.keychain | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
echo "Signing profile with identity: $IDENTITY"
security cms -S -k temp.keychain -N "$IDENTITY" -i "$PLIST" -o "$OUT/codesigning/profiles/Telegram.mobileprovision"
rm -f "$PLIST"

openssl smime -inform der -verify -noverify -in "$OUT/codesigning/profiles/Telegram.mobileprovision" 2>/dev/null \
  | grep -A1 -E 'application-identifier|application-groups' | grep string
