#!/bin/bash
# Notarizes the staged FleetConsole.app and staples the ticket to that artifact.
#
# Signing proves who built the app. Notarization is Apple confirming they have
# scanned that exact build — without it Gatekeeper reports "Unnotarized Developer
# ID" and refuses to open it on any Mac but the one that compiled it. Stapling
# attaches the result so the app opens even with no network.
#
# Credentials are never handled here. `notarytool` reads them from a keychain
# profile you create once, interactively, with your own Apple ID. This script
# refuses to run rather than prompting for a password.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${FLEETCONSOLE_OUTPUT_DIR:-$ROOT/build}"
case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;;
esac
APP="$OUTPUT_DIR/FleetConsole.app"
PROFILE="${FLEETCONSOLE_NOTARY_PROFILE:-FleetConsole}"
ARCHIVE="$OUTPUT_DIR/FleetConsole-notarize.zip"

[ -d "$APP" ] || { echo "✗ $APP does not exist — run Scripts/build-app.sh release first"; exit 1; }

# Refuse to submit an ad-hoc build: notarization requires a Developer ID signature
# with the hardened runtime, and failing here is clearer than failing at Apple.
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
    echo "✗ $APP is not signed with a Developer ID identity."
    echo "  Run Scripts/build-app.sh release on a machine with the certificate installed."
    exit 1
fi
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime"; then
    echo "✗ $APP is not signed with the hardened runtime; Apple will reject it."
    exit 1
fi

# Two credential types, in preference order. An App Store Connect API key is the
# better one: it is a file plus two identifiers, so it works unattended and in CI
# with no password anywhere. A keychain profile is fine but has to be created
# interactively first.
#
#   FLEETCONSOLE_ASC_KEY      path to AuthKey_XXXXXXXX.p8
#   FLEETCONSOLE_ASC_KEY_ID   the key ID (the XXXXXXXX in the filename)
#   FLEETCONSOLE_ASC_ISSUER   the issuer UUID from App Store Connect
AUTH=()
if [ -n "${FLEETCONSOLE_ASC_KEY:-}" ]; then
    [ -f "$FLEETCONSOLE_ASC_KEY" ] || { echo "✗ key not found: $FLEETCONSOLE_ASC_KEY"; exit 1; }
    KEY_ID="${FLEETCONSOLE_ASC_KEY_ID:-$(basename "$FLEETCONSOLE_ASC_KEY" | sed -E 's/^AuthKey_(.+)\.p8$/\1/')}"
    [ -n "${FLEETCONSOLE_ASC_ISSUER:-}" ] || { echo "✗ set FLEETCONSOLE_ASC_ISSUER (issuer UUID)"; exit 1; }
    AUTH=(--key "$FLEETCONSOLE_ASC_KEY" --key-id "$KEY_ID" --issuer "$FLEETCONSOLE_ASC_ISSUER")
    echo "▸ authenticating with App Store Connect API key $KEY_ID"
elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    AUTH=(--keychain-profile "$PROFILE")
    echo "▸ authenticating with keychain profile \"$PROFILE\""
else
    cat <<EOF
✗ No credential available. Either works — pick one:

  API key (unattended, CI-safe, no password):
    appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API
    Download AuthKey_XXXXXXXX.p8, then:

      export FLEETCONSOLE_ASC_KEY=/path/to/AuthKey_XXXXXXXX.p8
      export FLEETCONSOLE_ASC_ISSUER=<issuer UUID>
      Scripts/notarize.sh

  Keychain profile (one interactive setup):
      xcrun notarytool store-credentials "$PROFILE" \\
          --apple-id "<your Apple ID>" --team-id "<your Team ID>" \\
          --password "<app-specific password from appleid.apple.com>"
EOF
    exit 1
fi

echo "▸ archiving…"
rm -f "$ARCHIVE"
# ditto, not zip: it preserves the bundle's symlinks and extended attributes,
# which a plain zip silently mangles.
/usr/bin/ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "▸ submitting to Apple (this usually takes a few minutes)…"
xcrun notarytool submit "$ARCHIVE" "${AUTH[@]}" --wait

echo "▸ stapling the ticket…"
xcrun stapler staple "$APP"

echo "▸ verifying…"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

rm -f "$ARCHIVE"
echo
echo "✓ notarized and stapled — $APP will now open on any Mac"
