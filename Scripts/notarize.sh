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
exec python3 "$ROOT/Scripts/release-staging.py" notarize "$OUTPUT_DIR" "$ROOT"

# PINNED NOTARY WORKER
# The helper reads this section; it is unreachable via script CLI arguments.
# All artifact operations use '.', never the replaceable supplied pathname.
set -euo pipefail
APP="."
PROFILE="${FLEETCONSOLE_NOTARY_PROFILE:-FleetConsole}"
ARCHIVE="$1"        # inherited open archive file, not an output pathname
SCRATCH_FD="$2"     # inherited private directory identity
ARCHIVE_NAME="$3"

# Refuse to submit an ad-hoc build: notarization requires a Developer ID signature
# with the hardened runtime, and failing here is clearer than failing at Apple.
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep "Developer ID Application" >/dev/null; then
    echo "✗ $APP is not signed with a Developer ID identity."
    echo "  Run Scripts/build-app.sh release on a machine with the certificate installed."
    exit 1
fi
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep "flags=.*runtime" >/dev/null; then
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
# ditto, not zip: it preserves the bundle's symlinks and extended attributes,
# which a plain zip silently mangles.
/usr/bin/ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "▸ submitting to Apple (this usually takes a few minutes)…"
# Switch the submission child by directory identity; its relative ZIP name
# survives repository, ancestor and private-scratch renames/replacements.
python3 -c 'import os, sys
os.fchdir(int(sys.argv[1]))
os.execv("/bin/bash", ["/bin/bash", "-c", "xcrun notarytool submit \"$@\" --wait",
                     "fleet-notary-submit", *sys.argv[2:]])
' "$SCRATCH_FD" "$ARCHIVE_NAME" "${AUTH[@]}"

echo "▸ stapling the ticket…"
xcrun stapler staple "$APP"

echo "▸ verifying…"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

# The helper cleans the archive through its pinned private directory.
echo
echo "✓ notarized and stapled — $APP will now open on any Mac"
