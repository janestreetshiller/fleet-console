#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${1:-$ROOT/../../build/gpui}"
APP="$OUT/FleetConsole.app"

cargo build --release -p fleet-console --manifest-path "$ROOT/../Cargo.toml"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/../target/release/FleetConsole" "$APP/Contents/MacOS/FleetConsole"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
plutil -p "$APP/Contents/Info.plist" | grep -E 'CFBundleIdentifier|LSUIElement|CFBundleExecutable'
