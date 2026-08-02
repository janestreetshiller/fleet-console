#!/bin/bash
# Renders a contact sheet of every FleetKit primitive to build/design/.
#
#   Scripts/fleetkit-sheet.sh          # render, print paths
#   Scripts/fleetkit-sheet.sh --open   # render and open them
#
# Four images: light and dark, each also desaturated. The greyscale pair is the
# point. `accessibilityDifferentiateWithoutColor` is a read-only environment
# value that cannot be injected into a render, but the question it exists to
# answer — does this still read without hue — is answered better by stripping
# the hue from the finished pixels and looking. Anything that turns into an
# undifferentiated grey blob was encoding state in colour alone.
#
# The design sources are **symlinked** into a throwaway package, never copied,
# so the sheet always shows what actually ships. `Scripts/fleetkit-sheet/Sheet.swift`
# is the only file that belongs to this tool; add a primitive there when you add
# one to FleetKit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/design"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT" "$WORK/Sources/Sheet/real"

# FleetCore as its own target: the app's FleetConsoleApp target is an executable,
# so its types cannot be imported from outside the package.
ln -s "$ROOT/Sources/FleetCore" "$WORK/Sources/FleetCore"

for f in Design/Theme.swift \
         Design/Tokens.swift \
         Design/StatusTone.swift \
         Design/ConsoleModule.swift \
         Design/ViewModifiers.swift \
         Design/FleetRow.swift \
         Design/Formatters.swift \
         Views/Components.swift \
         Probes/SystemMetrics.swift; do
  ln -s "$ROOT/Sources/FleetConsoleApp/$f" "$WORK/Sources/Sheet/real/$(basename "$f")"
done
cp "$ROOT/Scripts/fleetkit-sheet/Sheet.swift" "$WORK/Sources/Sheet/main.swift"

cat > "$WORK/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Sheet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FleetCore",
                swiftSettings: [.swiftLanguageMode(.v5)],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Sheet", dependencies: ["FleetCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
MANIFEST

echo "▸ building sheet…"
( cd "$WORK" && swift build -c release 2>&1 | grep -vE '^\[|warning: missing creator' || true )
echo "▸ rendering…"
( cd "$WORK" && swift run -c release Sheet "$OUT" 2>&1 | grep -E '^wrote' )

echo
echo "→ $OUT"
if [[ "${1:-}" == "--open" ]]; then
  open "$OUT"/fleetkit-*.png
fi
