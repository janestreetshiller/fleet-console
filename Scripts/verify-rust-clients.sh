#!/bin/bash
# Local verification for the Rust clients on macOS or Linux. No controller is
# started, no network is used beyond Cargo's cache, nothing is installed.
# Usage: Scripts/verify-rust-clients.sh [--skip-gpui]
#   --skip-gpui  for a host without GPUI's system libraries (the terminal client
#                and the core are still checked).
# CARGO_TARGET_DIR is respected. The pinned toolchain comes from
# rust-toolchain.toml.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_GPUI=0
for arg in "$@"; do
    case "$arg" in
        --skip-gpui) SKIP_GPUI=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done
cd "$ROOT"
MANIFEST=(--manifest-path rust/Cargo.toml --locked)
PACKAGES=(-p fleet-proto -p fleet-ui-core -p fleet-tui)
CLIENTS=(-p fleet-tui)
if [ "$SKIP_GPUI" -eq 0 ]; then
    PACKAGES+=(-p fleet-gpui)
    CLIENTS+=(-p fleet-gpui)
fi
TARGET="${CARGO_TARGET_DIR:-$ROOT/rust/target}"

echo "toolchain: $(rustc --version)"
echo "== tests"
cargo test "${MANIFEST[@]}" "${PACKAGES[@]}"
echo "== clippy"
cargo clippy "${MANIFEST[@]}" "${PACKAGES[@]}" --all-targets -- -D warnings
echo "== release builds without fixtures"
cargo build "${MANIFEST[@]}" "${CLIENTS[@]}" --release

# Fixture snapshots report this controller version. A default release binary
# that contains it has synthetic data compiled in. The marker is assembled so
# this script itself does not contain it verbatim.
MARKER="synthetic-fixture-""4c1e"
BINARIES=("$TARGET/release/fleet-tui")
[ "$SKIP_GPUI" -eq 0 ] && BINARIES+=("$TARGET/release/fleet-gpui")
for binary in "${BINARIES[@]}"; do
    if grep -q -a "$MARKER" "$binary"; then
        echo "FAIL: $binary contains fixture data" >&2
        exit 1
    fi
    echo "no fixture data in $(basename "$binary")"
done

echo "== fixture builds still compile"
cargo build "${MANIFEST[@]}" "${CLIENTS[@]}" --release --features fixtures
for binary in "${BINARIES[@]}"; do
    grep -q -a "$MARKER" "$binary" || { echo "FAIL: marker check is not detecting fixtures" >&2; exit 1; }
done
# Leave default binaries in place for anyone running them after this script.
cargo build "${MANIFEST[@]}" "${CLIENTS[@]}" --release

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
