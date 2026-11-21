#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/design"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT" "$WORK/Sources/Sheet/real"

ln -s "$ROOT/Sources/FleetCore" "$WORK/Sources/FleetCore"

for f in Design/OurosCoreTokens.swift \
         Design/CorePalette.swift \
         Design/Theme.swift \
         Design/Tokens.swift \
         Design/QuantizedCardGrid.swift \
         Design/Sketchfield.swift \
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
( cd "$WORK" && swift build -c release --disable-index-store )
BIN="$(cd "$WORK" && swift build -c release --disable-index-store --show-bin-path)"
echo "▸ rendering…"
"$BIN/Sheet" "$OUT"

echo
echo "→ $OUT"
if [[ "${1:-}" == "--open" ]]; then
  open "$OUT"/fleetkit-*.png
fi
