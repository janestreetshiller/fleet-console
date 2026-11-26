#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
GPUI="$(pwd -P)"
ROOT="$(cd ../.. && pwd -P)"
RUST="$ROOT/rust"
OUT="${1:-$ROOT/build/gpui}"
case "$OUT" in
    /*) ;;
    *) OUT="$GPUI/$OUT" ;;
esac
OUT="$(python3 "$ROOT/Scripts/release-staging.py" check "$OUT")"

REVISION="$(git -C "$ROOT" rev-parse --verify HEAD)"
SOURCE_STATUS="$(git -C "$ROOT" status --porcelain --untracked-files=normal)"
CORE_RECEIPT="$(cat "$ROOT/.design-core/receipt.json")"

SCRATCH_PATH="${FLEETCONSOLE_SCRATCH_PATH:-$ROOT/.build}"
case "$SCRATCH_PATH" in
    /*) ;;
    *) echo "FLEETCONSOLE_SCRATCH_PATH must be absolute" >&2; exit 2 ;;
esac
swift_build() {
    swift build --package-path "$ROOT" --scratch-path "$SCRATCH_PATH" \
        --jobs 1 -c release --disable-index-store --disable-automatic-resolution \
        -Xswiftc -disable-cmo "$@"
}

swift_build --product fleetd
swift_build --product fleetctl
SWIFT_BIN="$(swift_build --show-bin-path)"
cargo build --manifest-path "$RUST/Cargo.toml" --target-dir "$RUST/target" \
    --locked --release -p fleet-console -p fleet-agent --bin FleetConsole --bin fleet-agent

CURRENT_REVISION="$(git -C "$ROOT" rev-parse --verify HEAD)"
CURRENT_STATUS="$(git -C "$ROOT" status --porcelain --untracked-files=normal)"
if [ "$CURRENT_REVISION" != "$REVISION" ] || [ "$CURRENT_STATUS" != "$SOURCE_STATUS" ]; then
    echo "FleetConsole source changed during the build; refusing to label the bundle" >&2
    exit 1
fi

python3 - "$ROOT" "$GPUI" "$OUT" "$SWIFT_BIN" "$SCRATCH_PATH" \
    "$REVISION" "$SOURCE_STATUS" "$CORE_RECEIPT" "${FLEETCONSOLE_IDENTITY:--}" <<'STAGE'
import json
import os
from pathlib import Path
import plistlib
import re
import runpy
import shutil
import subprocess
import sys

root, gpui, out, swift_bin, scratch = map(Path, sys.argv[1:6])
revision, status, receipt, identity = sys.argv[6:]
rust_bin = root / "rust/target/release"
scripts = root / "Scripts"
resources = root / "Resources"
staging = runpy.run_path(str(scripts / "release-staging.py"))
core = json.loads(receipt)
if not re.fullmatch(r"[0-9a-f]{64}", core["sourceSHA256"]):
    raise SystemExit("Invalid design core identity")
with (gpui / "macos/Info.plist").open("rb") as template:
    info = plistlib.load(template)
info.update(
    FleetSourceRevision=revision,
    FleetSourceDirty=bool(status),
    OurosDesignCoreVersion=core["version"],
    OurosDesignCoreSHA256=core["sourceSHA256"],
)

contents = Path("Contents")
bundle_resources = contents / "Resources"
bin_dir = bundle_resources / "bin"
licenses = bundle_resources / "licenses"
jobs = contents / "Library/LaunchAgents"
app_executable = contents / "MacOS/FleetConsole"
helpers = {
    bin_dir / "fleetd": swift_bin / "fleetd",
    bin_dir / "fleetctl": swift_bin / "fleetctl",
    bin_dir / "fleet-agent": rust_bin / "fleet-agent",
}
signing_flags = ["--force", "--sign", identity]
if identity == "-":
    signing_flags += ["--timestamp=none"]
else:
    signing_flags += ["--options", "runtime", "--timestamp"]

def run(*args):
    subprocess.run(args, check=True)

try:
    with staging["_stage_output"](out, reserve=True) as (output, output_fd):
        name = staging["BUNDLE_NAME"]
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=output_fd)
        try:
            os.fchdir(fd)
            for directory in (app_executable.parent, bin_dir, licenses, jobs):
                directory.mkdir(parents=True)
            shutil.copy2(rust_bin / "FleetConsole", app_executable)
            for dest, source in helpers.items():
                shutil.copy2(source, dest)
            shutil.copy2(resources / "com.fleetconsole.fleetd.plist", jobs)
            shutil.copy2(resources / "AppIcon.icns", bundle_resources)
            shutil.copy2(root / "LICENSE", licenses / "FleetConsole-LICENSE.txt")
            shutil.copy2(
                scratch / "checkouts/SwiftTerm/LICENSE", licenses / "SwiftTerm-LICENSE.txt"
            )
            shutil.copytree(resources / "yazi", bundle_resources / "yazi")
            with (contents / "Info.plist").open("wb") as target:
                plistlib.dump(info, target, sort_keys=False)

            for binary in (app_executable, *helpers):
                run("xcrun", "strip", "-S", binary)
            run(sys.executable, scripts / "verify-agent-bundle.py", ".")
            for helper in helpers:
                run("codesign", *signing_flags, helper)
                run("codesign", "--verify", "--strict", helper)
            run("codesign", *signing_flags, ".")
            run("codesign", "--verify", "--deep", "--strict", ".")
        finally:
            os.close(fd)
except (OSError, ValueError, subprocess.CalledProcessError) as error:
    raise SystemExit(f"FleetConsole staging failed: {error}") from error

print(output / name)
if identity != "-":
    print("Developer ID signature only; this staging bundle is not notarized.", file=sys.stderr)
STAGE
