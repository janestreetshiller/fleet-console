#!/usr/bin/env python3
"""TEST DATA ONLY: mocked signing/build tools; the archive spy runs native ditto."""
import json
import os
from pathlib import Path
import sys
import subprocess

root = Path(os.environ["FLEET_TEST_ROOT"]).resolve()
if not (root / "TEST-DATA-ONLY").is_file():
    raise SystemExit("Refusing mock invocation outside an isolated test fixture")
name = Path(sys.argv[0]).name
args = sys.argv[1:]
boundary = ("strip" if name == "xcrun" and args[:2] == ["strip", "-S"]
            else ("deep" if "--deep" in args else "verify" if "--verify" in args else "sign")
            if name == "codesign" and "-dv" not in args else None)
swap_at = os.environ.get("FLEET_TEST_BUNDLE_SWAP")
if boundary is not None and boundary == swap_at:
    saved = root / f"saved-{boundary}" / "FleetConsole.app"
    if not saved.exists():
        source = Path(os.environ["FLEETCONSOLE_OUTPUT_DIR"]) / "FleetConsole.app"
        protected = root / "home/Applications/FleetConsole.app"
        if not source.resolve().is_relative_to(root) or not protected.is_dir():
            raise SystemExit("Bundle swap must stay inside the TEST DATA fixture")
        saved.parent.mkdir()
        source.rename(saved)
        source.symlink_to(protected, target_is_directory=True)
entry = {"tool": name, "args": args, "cwd": str(Path.cwd())}
if name == "ditto" or (name == "xcrun" and args[:2] == ["notarytool", "submit"]):
    info = (os.fstat(int(args[-1].rsplit("/", 1)[1])) if name == "ditto"
            else Path(args[2]).stat())
    entry["archive_identity"] = [info.st_dev, info.st_ino]
with (root / "mock-calls.jsonl").open("a") as log:
    log.write(json.dumps(entry) + "\n")

if name == "swift":
    if not args or args[0] != "build":
        raise SystemExit("Unexpected TEST DATA swift invocation")
    if "--show-bin-path" in args:
        collision = os.environ.get("FLEET_TEST_COLLISION")
        if collision:
            target = Path(collision)
            if not target.resolve().is_relative_to(root):
                raise SystemExit("Collision must stay inside the TEST DATA fixture")
            target.mkdir(parents=True)
            (target / "keep.txt").write_text("TEST DATA: concurrent staging owner\n")
        print(root / "bin")
elif name == "ditto":
    if not Path(args[-2]).resolve().is_relative_to(root):
        raise SystemExit("Cannot archive outside the TEST DATA fixture")
    destination = args[-1]
    if not destination.startswith("/dev/fd/"):
        raise SystemExit("Archive destination must be the inherited descriptor")
    descriptor = int(destination.rsplit("/", 1)[1])
    raise SystemExit(subprocess.run(["/usr/bin/ditto", *args], pass_fds=(descriptor,), check=False).returncode)
elif name == "xcrun":
    if ":".join(args[:2]) == os.environ.get("FLEET_TEST_NOTARY_FAILURE"):
        print("TEST DATA: simulated notarization failure", file=sys.stderr)
        raise SystemExit(42)
    if args[:2] == ["notarytool", "history"]:
        raise SystemExit(0)
    if args[:2] == ["notarytool", "submit"] or args[:2] in (["stapler", "staple"], ["stapler", "validate"]):
        target = Path(args[2]).resolve()
        if not target.is_relative_to(root):
            raise SystemExit("Cannot notarize outside the TEST DATA fixture")
        raise SystemExit(0)
    if args[:2] != ["strip", "-S"]:
        raise SystemExit("Only TEST DATA strip is allowed")
    target = Path(args[-1]).resolve()
    if not target.is_relative_to(root):
        raise SystemExit("Cannot strip outside the TEST DATA fixture")
    with target.open("ab") as binary:
        binary.write(b"\n# TEST DATA: stripped copy\n")
elif name == "codesign":
    target = Path(args[-1]).resolve()
    if not target.is_relative_to(root):
        raise SystemExit("Cannot sign outside the TEST DATA fixture")
    bundle = next((path for path in (target, *target.parents) if path.name == "FleetConsole.app"), None)
    if bundle is None:
        raise SystemExit("TEST DATA signature target must belong to the staged bundle")
    for notice in ("FleetConsole-LICENSE.txt", "SwiftTerm-LICENSE.txt"):
        if not (bundle / "Contents/Resources/licenses" / notice).is_file():
            raise SystemExit("TEST DATA: licenses must be assembled before signing")
    if "-dv" in args:
        signature = os.environ.get("FLEET_TEST_SIGNATURE", "developer-runtime")
        print("Signature=adhoc" if signature == "adhoc"
              else "TEST DATA ONLY: Developer ID Application", file=sys.stderr)
        print("flags=0x10000(runtime)" if signature == "developer-runtime"
              else "flags=0x0(none)", file=sys.stderr)
        if os.environ.get("FLEET_TEST_VERBOSE_SIGNATURE"):
            for _ in range(256):
                print("TEST DATA: extra signature diagnostic " * 100, file=sys.stderr, flush=True)
        if os.environ.get("FLEET_TEST_SIGNATURE_EXIT"):
            raise SystemExit(42)
        raise SystemExit(0)
    operation = "deep" if "--deep" in args else "verify" if "--verify" in args else "sign"
    failure = os.environ.get("FLEET_TEST_CODESIGN_FAILURE")
    if failure in (f"{operation}:{target.name}", operation):
        print("TEST DATA: simulated codesign failure", file=sys.stderr)
        raise SystemExit(42)
elif name == "spctl":
    if not Path(args[-1]).resolve().is_relative_to(root):
        raise SystemExit("Cannot assess outside the TEST DATA fixture")
    if os.environ.get("FLEET_TEST_NOTARY_FAILURE") == "spctl":
        raise SystemExit(42)
elif name == "lsof":
    mode = os.environ.get("FLEET_TEST_LSOF", "failed")
    if mode == "busy":
        print(os.environ.get("FLEET_TEST_RUNNING_PID", "4242"))
    elif mode == "failed":
        print("TEST DATA: simulated lsof error", file=sys.stderr)
        raise SystemExit(2)
    elif mode != "unused":
        raise SystemExit("Unexpected TEST DATA lsof mode")
else:
    raise SystemExit(f"Forbidden native tool boundary reached: {name}")
