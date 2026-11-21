#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
FLEETCTL="$HERE/fleetctl"
[[ -x "$FLEETCTL" ]] || { echo "✗ fleetctl not found next to this script." >&2; exit 1; }

link_into() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    ln -sf "$FLEETCTL" "$dir/fleetctl"
    echo "✓ fleetctl -> $dir/fleetctl"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) echo "  Note: $dir is not on your PATH in this shell. Add it: export PATH=\"$dir:\$PATH\"" ;;
    esac
}

if [[ -w /usr/local/bin ]] || mkdir -p /usr/local/bin 2>/dev/null; then
    link_into /usr/local/bin
else
    echo "/usr/local/bin needs sudo; using ~/.local/bin instead." >&2
    link_into "$HOME/.local/bin"
fi

echo
"$FLEETCTL" doctor || true
