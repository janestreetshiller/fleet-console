#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST=(--manifest-path rust/Cargo.toml --locked)
cd "$ROOT"

echo "== FleetConsole and controller protocol tests"
cargo test "${MANIFEST[@]}" -p fleet-console --bin FleetConsole
cargo test "${MANIFEST[@]}" -p fleet-proto --lib

echo "== source identity scan (same rules as Scripts/test-source-privacy.py)"
PATTERN="/Users/""main\\b|metal""-mini|tail8a""000f|100\\.98""\\.105\\.78"
FOUND=0
while IFS= read -r -d '' file; do
    case "$(basename "$file" | tr '[:lower:]' '[:upper:]')" in
        AGENTS.MD|LICENSE|LICENSE.MD|LICENSE.TXT) continue ;;
    esac
    [ -f "$file" ] || continue
    if grep -n -i -E "$PATTERN" "$file" >/dev/null 2>&1; then
        echo "identity finding in $file" >&2
        FOUND=1
    fi
done < <(git ls-files --cached --others --exclude-standard -z)
[ "$FOUND" -eq 0 ] || exit 1
echo "verify-rust-clients: all checks passed"
