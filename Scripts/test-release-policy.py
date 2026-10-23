#!/usr/bin/env python3
"""Non-destructive release-policy regressions; all artifacts are TEST DATA in TMPDIR.

Execute the current production scripts byte-for-byte in a disposable fixture.
Swift, strip, codesign, keychain, launchctl and lsof boundaries are isolated mocks;
these tests are policy evidence, not evidence of a native build or valid signature.
Run: python3 Scripts/test-release-policy.py
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent
# Loading the production helper must not leave __pycache__ in the checkout.
sys.dont_write_bytecode = True


def snapshot(path):
    if path.is_symlink():
        return {".": ("symlink", os.readlink(path))}
    if path.is_file():
        return {".": ("file", path.read_bytes())}
    return {
        str(item.relative_to(path)): (
            ("symlink", os.readlink(item)) if item.is_symlink()
            else ("file", item.read_bytes()) if item.is_file()
            else ("directory", None)
        )
        for item in path.rglob("*")
    }


class ScriptFixture(unittest.TestCase):
    def setUp(self):
        scratch = os.environ.get("TMPDIR")
        if not scratch or not Path(scratch).is_dir():
            self.fail("Set TMPDIR to an existing scratch directory; no system-temp fallback")
        self.temp = tempfile.TemporaryDirectory(prefix="fleet-release-test-data-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "TEST-DATA-ONLY").write_text("TEST DATA ONLY: no native tools\n")
        self.tools = self.root / "mock-tools"
        self.tools.mkdir()
        mock = self.tools / "mock-tool.py"
        shutil.copyfile(SCRIPTS / "release-policy-mock-tool.py", mock)
        mock.chmod(0o755)
        for name in ("swift", "cargo", "git", "xcrun", "codesign", "security", "launchctl", "lsof", "spctl", "ditto"):
            (self.tools / name).symlink_to(mock)
        (self.tools / "python3").symlink_to(sys.executable)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for name in ("build-app.sh", "assemble-app.sh", "verify-agent-bundle.py", "benchmark.sh", "release-staging.py", "notarize.sh"):
            if (SCRIPTS / name).is_file():
                # No rewritten guards: the fixture always runs current production bytes.
                shutil.copyfile(SCRIPTS / name, scripts / name)
        self.home = self.root / "home"
        self.home.mkdir()
        (self.root / "rust").mkdir()
        resources = self.root / "Resources"
        resources.mkdir()
        (resources / "AppIcon.icns").write_text("TEST DATA: icon\n")
        (resources / "com.fleetconsole.fleetd.plist").write_text("TEST DATA: plist\n")
        (resources / "yazi").mkdir()
        (resources / "yazi" / "theme.toml").write_text("# TEST DATA: theme\n")
        (self.root / "LICENSE").write_text("TEST DATA: authored MIT license\n")
        license_dir = self.root / ".build/checkouts/SwiftTerm"
        license_dir.mkdir(parents=True)
        (license_dir / "LICENSE").write_text("TEST DATA: upstream SwiftTerm license\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("FleetConsoleApp", "fleetd", "fleetctl"):
            (self.bin / name).write_text(f"TEST DATA: {name} executable\n")
        (self.bin / "SwiftTerm.bundle").mkdir()
        (self.bin / "SwiftTerm.bundle" / "shaders.metallib").write_text("TEST DATA: shaders\n")
        framework = self.bin / "Test.framework"
        framework.mkdir()
        (framework / "Test").write_text("TEST DATA: framework\n")
        (self.bin / "test.dylib").write_text("TEST DATA: dylib\n")
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.app = self.stage / "FleetConsole.app"
        bash_env = self.root / "mock-boundaries.sh"
        # Intercept absolute tool names too, including the old /usr/sbin/lsof call.
        bash_env.write_text("\n".join(
            f'{prefix}/{name}() {{ "$FLEET_TEST_ROOT/mock-tools/{name}" "$@"; }}'
            for prefix in ("/usr/bin", "/usr/sbin", "/bin")
            for name in ("swift", "git", "xcrun", "codesign", "security", "launchctl", "lsof", "spctl", "ditto")
        ) + "\n")
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "PATH": str(self.tools) + os.pathsep + os.environ.get("PATH", ""),
            "BASH_ENV": str(bash_env),
            "FLEET_TEST_ROOT": str(self.root),
            "FLEETCONSOLE_OUTPUT_DIR": str(self.stage),
            "FLEETCONSOLE_IDENTITY": "-",
            "FLEET_TEST_LSOF": "failed",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        self.env.pop("FLEET_BENCHMARK_CPU_BUDGET", None)


    def run_script(self, name, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.root / "Scripts" / name), *args],
            env=dict(self.env, **env), cwd=self.root, capture_output=True, text=True, timeout=15,
        )

    def calls(self):
        log = self.root / "mock-calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def expect_failure(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertNotIn("✓ built", result.stdout)

    def existing_bundle(self):
        executable = self.app / "Contents/Resources/bin/fleetd"
        executable.parent.mkdir(parents=True)
        executable.write_text(
            "#!/usr/bin/env python3\n"
            "# TEST DATA ONLY: running fixture, never the real controller.\n"
            "import sys\nprint('TEST DATA: running', flush=True)\nsys.stdin.read()\n"
        )
        executable.chmod(0o755)
        (self.app / "keep.txt").write_text("TEST DATA: never replace me\n")
        return executable


class PackagingTests(ScriptFixture):
    def test_offline_build_uses_one_job_and_the_selected_dependency_license(self):
        scratch = self.root / "offline-scratch"
        license_dir = scratch / "checkouts" / "SwiftTerm"
        license_dir.mkdir(parents=True)
        (license_dir / "LICENSE").write_text("TEST DATA: selected offline license\n")
        result = self.run_script("build-app.sh", "release", FLEETCONSOLE_OFFLINE="1",
                                 FLEETCONSOLE_SCRATCH_PATH=str(scratch))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        swift_calls = [call for call in calls if call["tool"] == "swift"]
        self.assertTrue(swift_calls)
        for call in swift_calls:
            args = call["args"]
            self.assertEqual(args[args.index("--jobs") + 1], "1")
            self.assertIn("--disable-automatic-resolution", args)
            self.assertIn("--skip-update", args)
            self.assertEqual(args[args.index("--scratch-path") + 1], str(scratch))
        cargo_calls = [call for call in calls if call["tool"] == "cargo"]
        self.assertTrue(cargo_calls)
        for call in cargo_calls:
            self.assertEqual(call["args"][call["args"].index("--jobs") + 1], "1")
        notice = self.app / "Contents/Resources/licenses/SwiftTerm-LICENSE.txt"
        self.assertEqual(notice.read_text(), "TEST DATA: selected offline license\n")
        import plistlib
        with (self.app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleVersion"], "6")
        self.assertEqual(info["FleetSourceRevision"], "unrecorded")
        self.assertTrue(info["FleetSourceDirty"])

    def test_relative_scratch_is_refused_before_building(self):
        result = self.run_script("build-app.sh", "release", FLEETCONSOLE_SCRATCH_PATH="relative")
        self.expect_failure(result, "must be absolute")
        self.assertFalse(any(call["tool"] in ("swift", "cargo") for call in self.calls()))

    def test_model_weights_are_rejected_before_signing(self):
        (self.bin / "SwiftTerm.bundle/unexpected.gguf").write_bytes(b"model fixture")
        result = self.run_script("build-app.sh", "release")
        self.expect_failure(result, "inference runtime or model weights cannot ship")
        self.assertNotIn("codesign", [call["tool"] for call in self.calls()])

    def test_bundled_agent_builds_with_bounded_parallelism(self):
        result = self.run_script("build-app.sh", "release")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        builds = [call for call in self.calls() if call["tool"] in ("swift", "cargo")]
        self.assertEqual({call["tool"] for call in builds}, {"swift", "cargo"})
        for call in builds:
            self.assertIn("--jobs", call["args"], call)
            self.assertLessEqual(int(call["args"][call["args"].index("--jobs") + 1]), 2)
        self.assertTrue((self.app / "Contents/Resources/bin/fleet-agent").is_file())
        self.assertEqual(
            {p.name for p in (self.app / "Contents/Library/LaunchAgents").iterdir()},
            {"com.fleetconsole.fleetd.plist"},
        )

    def test_existing_bundle_refused_even_when_lsof_fails(self):
        self.existing_bundle()
        before = snapshot(self.app)
        result = self.run_script("build-app.sh", "release", FLEET_TEST_LSOF="failed")
        self.expect_failure(result, "output bundle already exists")
        self.assertEqual(snapshot(self.app), before)
        self.assertEqual(self.calls(), [], "Refusal must precede build/lsof/signing")

    def test_existing_unused_bundle_is_not_replaced(self):
        self.existing_bundle()
        before = snapshot(self.app)
        result = self.run_script("build-app.sh", "release", FLEET_TEST_LSOF="unused")
        self.expect_failure(result, "output bundle already exists")
        self.assertEqual(snapshot(self.app), before)
        self.assertEqual(self.calls(), [])

    def test_existing_running_bundle_is_not_replaced(self):
        executable = self.existing_bundle()
        child = subprocess.Popen(
            [str(executable)], env=self.env, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            if child.stdout is None:
                self.fail("Running TEST DATA fixture did not get a stdout pipe")
            self.assertEqual(child.stdout.readline().strip(), "TEST DATA: running")
            before = snapshot(self.app)
            result = self.run_script(
                "build-app.sh", "release", FLEET_TEST_LSOF="busy",
                FLEET_TEST_RUNNING_PID=str(child.pid),
            )
            self.expect_failure(result, "output bundle already exists")
            self.assertEqual(snapshot(self.app), before)
            self.assertIsNone(child.poll())
            self.assertEqual(self.calls(), [])
        finally:
            child.communicate(timeout=5)

    def test_applications_symlink_alias_is_refused_before_creating_output(self):
        protected = self.root / "protected-applications"
        protected.mkdir()
        (protected / "keep.txt").write_text("TEST DATA: installed apps\n")
        (self.home / "Applications").symlink_to(protected, target_is_directory=True)
        alias = self.root / "innocent-alias"
        alias.symlink_to(protected, target_is_directory=True)
        before = snapshot(protected)
        result = self.run_script(
            "build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(alias / "new-stage"),
        )
        self.expect_failure(result, "stage outside Applications")
        self.assertEqual(snapshot(protected), before)
        self.assertEqual(self.calls(), [])

    def test_existing_output_file_and_symlinks_are_refused(self):
        for kind in ("file", "directory-symlink", "dangling-symlink"):
            with self.subTest(kind=kind):
                if kind == "file":
                    self.app.write_text("TEST DATA: existing file\n")
                else:
                    target = self.root / kind
                    if kind == "directory-symlink":
                        target.mkdir()
                        (target / "keep.txt").write_text("TEST DATA: symlink target\n")
                    self.app.symlink_to(target, target_is_directory=True)
                before = snapshot(self.app)
                result = self.run_script("build-app.sh", "release")
                self.expect_failure(result, "output bundle already exists")
                self.assertEqual(snapshot(self.app), before)
                self.assertEqual(self.calls(), [])
                self.app.unlink()

    def test_concurrently_created_bundle_is_not_replaced(self):
        result = self.run_script(
            "build-app.sh", "release", FLEET_TEST_COLLISION=str(self.app),
        )
        self.expect_failure(result, "output bundle already exists")
        self.assertEqual(snapshot(self.app), {"keep.txt": ("file", b"TEST DATA: concurrent staging owner\n")})
        self.assertEqual([call["tool"] for call in self.calls()], ["swift", "swift"])

    def test_post_open_ancestor_swap_keeps_all_destinations_in_reserved_bundle(self):
        protected = self.home / "Applications"
        protected.mkdir()
        self.existing_bundle()
        self.app.rename(protected / self.app.name)
        before = snapshot(protected)
        original = self.root / "original-stage"
        hook = self.root / "reservation-hook"
        hook.mkdir()
        # TEST DATA injection at the actual reservation syscall, after stage fd
        # open. Production scripts are copied unchanged; no production race hook.
        (hook / "sitecustomize.py").write_text(
            "import os\nfrom pathlib import Path\n"
            "root = Path(os.environ['FLEET_TEST_ROOT'])\n"
            "real_mkdir = os.mkdir\n"
            "def swap(name, *args, **kwargs):\n"
            "    if name == 'FleetConsole.app' and 'dir_fd' in kwargs and not (root / 'original-stage').exists():\n"
            "        (root / 'stage').rename(root / 'original-stage')\n"
            "        (root / 'stage').symlink_to(root / 'home/Applications', target_is_directory=True)\n"
            "    return real_mkdir(name, *args, **kwargs)\n"
            "os.mkdir = swap\n"
        )
        result = self.run_script("build-app.sh", "release", PYTHONPATH=str(hook))
        self.assertTrue(original.is_dir(), "Post-open reservation swap must actually execute")
        self.assertTrue(os.path.samefile(self.stage, protected))
        self.assertEqual(snapshot(protected), before, "Existing protected files must remain byte-for-byte untouched")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        reserved = original / self.app.name
        self.assertTrue((reserved / "Contents/MacOS/FleetConsole").is_file())
        self.assertIn(f"✓ built {reserved}", result.stdout)
        destination_calls = [call for call in self.calls() if call["tool"] in ("xcrun", "codesign")]
        self.assertTrue(destination_calls, "Assembly must still strip, sign and verify")
        for call in destination_calls:
            self.assertEqual(Path(call["cwd"]), reserved)
            self.assertFalse(Path(call["args"][-1]).is_absolute(), "Destination must be relative to the pinned cwd")

    def test_unresolvable_output_is_refused_without_building(self):
        dangling = self.root / "dangling-output"
        dangling.symlink_to(self.root / "absent")
        loop = self.root / "loop-output"
        loop.symlink_to(loop)
        file = self.root / "output-file"
        file.write_text("TEST DATA: not a directory\n")
        for output in (dangling / "new", loop / "new", file / "new"):
            with self.subTest(output=output):
                before = snapshot(self.root)
                result = self.run_script("build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(output))
                self.expect_failure(result, "unsafe or unavailable staging destination")
                self.assertEqual(snapshot(self.root), before)
                self.assertEqual(self.calls(), [])

    def test_bundle_rename_keeps_destinations_pinned_through_strip_sign_and_verification(self):
        protected = self.home / "Applications"
        protected.mkdir()
        self.existing_bundle()
        self.app.rename(protected / self.app.name)
        before = snapshot(protected)
        for boundary in ("strip", "sign", "verify", "deep"):
            with self.subTest(boundary=boundary):
                stage = self.root / f"swap-{boundary}"
                count = len(self.calls())
                result = self.run_script("build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(stage),
                                         FLEET_TEST_BUNDLE_SWAP=boundary)
                reserved = self.root / f"saved-{boundary}" / self.app.name
                self.assertTrue(reserved.is_dir(), "Mid-operation bundle swap must actually execute")
                self.assertTrue(os.path.samefile(stage / self.app.name, protected / self.app.name))
                self.assertEqual(snapshot(protected), before, "Protected existing bundle must remain untouched")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"✓ built {reserved}", result.stdout)
                self.assertTrue((reserved / "Contents/Info.plist").is_file())
                self.assertTrue((reserved / "Contents/Resources/SwiftTerm.bundle/shaders.metallib").is_file())
                calls = [call for call in self.calls()[count:] if call["tool"] in ("xcrun", "codesign")]
                self.assertTrue(any(Path(call["cwd"]) == reserved for call in calls))
                for call in calls:
                    self.assertFalse(Path(call["args"][-1]).is_absolute())

    def test_fresh_release_preserves_resources_licenses_and_signing_order(self):
        inner = self.bin / "Test.framework" / "inner.dylib"
        inner.write_text("TEST DATA: nested framework dylib\n")
        originals = snapshot(self.bin)
        result = self.run_script("build-app.sh", "release")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"✓ built {self.app}", result.stdout)
        self.assertEqual(snapshot(self.bin), originals, "Strip must only mutate copied executables")
        notices = self.app / "Contents/Resources/licenses"
        self.assertEqual((notices / "FleetConsole-LICENSE.txt").read_bytes(), (self.root / "LICENSE").read_bytes())
        self.assertEqual((notices / "SwiftTerm-LICENSE.txt").read_bytes(),
                         (self.root / ".build/checkouts/SwiftTerm/LICENSE").read_bytes())
        self.assertTrue((self.app / "Contents/Resources/SwiftTerm.bundle/shaders.metallib").is_file())
        self.assertTrue((self.app / "Contents/Frameworks/Test.framework/inner.dylib").is_file())
        calls = self.calls()
        self.assertTrue(all(call["tool"] in ("swift", "cargo", "xcrun", "codesign") for call in calls))
        stripping = [index for index, call in enumerate(calls) if call["tool"] == "xcrun"]
        signing = [index for index, call in enumerate(calls) if call["tool"] == "codesign"]
        self.assertEqual(len(stripping), 4)
        self.assertLess(max(stripping), min(signing))
        code_calls = [call["args"] for call in calls if call["tool"] == "codesign"]
        signed = [args for args in code_calls if "--sign" in args]
        names = [(Path(call["cwd"]) / call["args"][-1]).resolve().name
                 for call in calls if call["tool"] == "codesign" and "--sign" in call["args"]]
        self.assertEqual(set(names), {"inner.dylib", "Test.framework", "test.dylib", "fleetd", "fleetctl", "fleet-agent", "FleetConsole.app"})
        self.assertLess(names.index("inner.dylib"), names.index("Test.framework"))
        self.assertEqual(names[-4:], ["fleetd", "fleetctl", "fleet-agent", "FleetConsole.app"])
        for args in signed:
            self.assertEqual(args[args.index("--sign") + 1], "-")
            self.assertIn("--timestamp=none", args)
            self.assertNotIn("--deep", args)
            self.assertNotIn("--options", args)
            position = code_calls.index(args)
            self.assertEqual(code_calls[position + 1], ["--verify", "--strict", "--verbose=2", args[-1]])
        self.assertEqual(code_calls[-1], ["--verify", "--deep", "--strict", "--verbose=2", "."])
        for call in calls:
            if call["tool"] in ("xcrun", "codesign"):
                self.assertEqual(Path(call["cwd"]), self.app)
                self.assertFalse(Path(call["args"][-1]).is_absolute())

    def test_explicit_developer_id_keeps_runtime_and_timestamp_flags(self):
        identity = "TEST DATA ONLY: Developer ID identity (not a real certificate)"
        result = self.run_script("build-app.sh", "release", FLEETCONSOLE_IDENTITY=identity)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertNotIn("security", [call["tool"] for call in calls])
        for call in calls:
            args = call["args"]
            if call["tool"] == "codesign" and "--sign" in args:
                self.assertEqual(args[args.index("--sign") + 1], identity)
                self.assertEqual(args[args.index("--options") + 1], "runtime")
                self.assertIn("--timestamp", args)
                self.assertNotIn("--timestamp=none", args)
                self.assertNotIn("--deep", args)

    def test_every_signing_or_verification_failure_stops_packaging(self):
        failures = ("sign:Test.framework", "verify:Test.framework", "sign:test.dylib", "verify:test.dylib",
                    "sign:fleetd", "verify:fleetd",
                    "sign:fleetctl", "verify:fleetctl", "sign:fleet-agent", "verify:fleet-agent",
                    "sign:FleetConsole.app", "verify:FleetConsole.app", "deep")
        for index, failure in enumerate(failures):
            with self.subTest(failure=failure):
                stage = self.root / f"signing-failure-{index}"
                result = self.run_script("build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(stage),
                                         FLEET_TEST_CODESIGN_FAILURE=failure)
                self.expect_failure(result, "TEST DATA: simulated codesign failure")
                self.assertEqual(result.returncode, 42)
                before = snapshot(stage / "FleetConsole.app")
                count = len(self.calls())
                retry = self.run_script("build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(stage))
                self.expect_failure(retry, "output bundle already exists")
                self.assertEqual(snapshot(stage / "FleetConsole.app"), before)
                self.assertEqual(len(self.calls()), count, "A partial failed bundle must not be reused")

    def test_missing_license_fails_before_signing(self):
        (self.root / ".build/checkouts/SwiftTerm/LICENSE").unlink()
        result = self.run_script("build-app.sh", "release")
        self.expect_failure(result, "SwiftTerm license missing")
        self.assertNotIn("codesign", [call["tool"] for call in self.calls()])

    def test_default_and_relative_fresh_stages_keep_debug_behavior(self):
        for output, destination in (("", self.root / "build"), ("fresh staging/relative", self.root / "fresh staging/relative")):
            with self.subTest(output=output):
                count = len(self.calls())
                result = self.run_script("build-app.sh", "debug", FLEETCONSOLE_OUTPUT_DIR=output)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((destination / "FleetConsole.app/Contents/MacOS/FleetConsole").is_file())
                self.assertNotIn("xcrun", [call["tool"] for call in self.calls()[count:]])


class NotarizationTests(ScriptFixture):
    """Routing and refusals only: no native signing, keychain, or Apple submission."""

    def setUp(self):
        super().setUp()
        for key in ("FLEETCONSOLE_ASC_KEY", "FLEETCONSOLE_ASC_KEY_ID",
                    "FLEETCONSOLE_ASC_ISSUER", "FLEETCONSOLE_NOTARY_PROFILE"):
            self.env.pop(key, None)

    def build_fixture(self, output):
        result = self.run_script("build-app.sh", "release", FLEETCONSOLE_OUTPUT_DIR=str(output))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def refuse_notarization(self, message, **env):
        output = self.root / "build"
        self.build_fixture(output)
        (output / "FleetConsole-notarize.zip").write_text("TEST DATA: existing archive must not be touched\n")
        before = snapshot(output)
        count = len(self.calls())
        result = self.run_script("notarize.sh", FLEETCONSOLE_OUTPUT_DIR=str(output), **env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertNotIn("✓ notarized", result.stdout)
        self.assertNotIn("▸ archiving", result.stdout)
        self.assertEqual(snapshot(output), before)
        calls = self.calls()[count:]
        self.assertFalse(any(call["tool"] == "xcrun" and call["args"][:2] != ["notarytool", "history"]
                             for call in calls), "Refusal must precede submission or stapling")
        self.assertNotIn("spctl", [call["tool"] for call in calls])
        return calls

    def test_ad_hoc_signature_is_refused_before_auth_or_archiving(self):
        calls = self.refuse_notarization("not signed with a Developer ID identity", FLEET_TEST_SIGNATURE="adhoc")
        self.assertEqual([call["tool"] for call in calls], ["codesign"])

    def test_missing_hardened_runtime_is_refused_before_auth_or_archiving(self):
        calls = self.refuse_notarization("not signed with the hardened runtime", FLEET_TEST_SIGNATURE="developer-no-runtime")
        self.assertEqual([call["tool"] for call in calls], ["codesign", "codesign"])

    def test_unavailable_credentials_are_refused_without_artifact_changes(self):
        calls = self.refuse_notarization("No credential available", FLEET_TEST_NOTARY_FAILURE="notarytool:history")
        self.assertEqual([call["tool"] for call in calls], ["codesign", "codesign", "xcrun"])
        self.assertEqual(calls[-1]["args"], ["notarytool", "history", "--keychain-profile", "FleetConsole"])

    def test_api_key_arguments_are_used_for_submission(self):
        output = self.root / "build"
        self.build_fixture(output)
        key = self.root / "AuthKey_TESTDATA.p8"
        key.write_text("TEST DATA ONLY: not a private key\n")
        result = self.run_script(
            "notarize.sh", FLEETCONSOLE_OUTPUT_DIR=str(output),
            FLEETCONSOLE_ASC_KEY=str(key), FLEETCONSOLE_ASC_KEY_ID="TESTDATA",
            FLEETCONSOLE_ASC_ISSUER="00000000-0000-0000-0000-000000000000",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        submit = next(call["args"] for call in self.calls()
                      if call["tool"] == "xcrun" and call["args"][:2] == ["notarytool", "submit"])
        self.assertIn("--key", submit)
        self.assertEqual(submit[submit.index("--key") + 1], str(key))
        self.assertEqual(submit[submit.index("--key-id") + 1], "TESTDATA")
        self.assertEqual(submit[submit.index("--issuer") + 1],
                         "00000000-0000-0000-0000-000000000000")
        self.assertNotIn("--keychain-profile", submit)

    def test_custom_stage_and_profile_select_the_exact_artifact(self):
        for spelling in (str(self.root / "custom stage"), "relative stage"):
            with self.subTest(output=spelling):
                output = Path(spelling)
                if not output.is_absolute():
                    output = self.root / output
                self.build_fixture(output)
                before = len(self.calls())
                result = self.run_script("notarize.sh", FLEETCONSOLE_OUTPUT_DIR=spelling,
                                         FLEETCONSOLE_NOTARY_PROFILE="TEST_DATA_PROFILE")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = self.calls()[before:]
                submission = next(call for call in calls
                                  if call["tool"] == "xcrun" and call["args"][:2] == ["notarytool", "submit"])
                submit = submission["args"]
                self.assertFalse(Path(submit[2]).is_absolute())
                archive = Path(submission["cwd"]) / submit[2]
                self.assertEqual(archive.name, "FleetConsole-notarize.zip")
                self.assertEqual(archive.parent.parent, self.root)
                self.assertTrue(archive.parent.name.startswith(".fleet-notary-"))
                self.assertFalse(archive.parent.exists(), "Private archive scratch must be cleaned")
                self.assertEqual(submit[submit.index("--keychain-profile") + 1], "TEST_DATA_PROFILE")
                app = (output / "FleetConsole.app").resolve()
                for call in calls:
                    target = None
                    if call["tool"] in ("codesign", "spctl"):
                        target = Path(call["args"][-1])
                    if call["tool"] == "xcrun" and call["args"][0] == "stapler":
                        target = Path(call["args"][2])
                    if target is not None:
                        self.assertEqual((Path(call["cwd"]) / target).resolve(), app)
                        self.assertEqual(Path(call["cwd"]).resolve(), app,
                                         "Each artifact operation must remain pinned to the exact app")
                    if call["tool"] == "ditto":
                        self.assertEqual((Path(call["cwd"]) / call["args"][-2]).resolve(), app)
                        self.assertTrue(call["args"][-1].startswith("/dev/fd/"))
                        self.assertEqual(call["archive_identity"], submission["archive_identity"])
                self.assertEqual(sum(call["tool"] == "ditto" for call in calls), 1)
                self.assertFalse((self.root / "build").exists())

    def test_signature_diagnostics_are_consumed_before_acceptance(self):
        output = self.root / "verbose stage"
        self.build_fixture(output)
        result = self.run_script("notarize.sh", FLEETCONSOLE_OUTPUT_DIR=str(output),
                                 FLEET_TEST_VERBOSE_SIGNATURE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_signature_command_failure_is_refused_even_with_matching_text(self):
        output = self.root / "failed inspection"
        self.build_fixture(output)
        before = len(self.calls())
        result = self.run_script("notarize.sh", FLEETCONSOLE_OUTPUT_DIR=str(output),
                                 FLEET_TEST_SIGNATURE_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call["tool"] == "xcrun" for call in self.calls()[before:]))

    def test_submission_and_stapling_failures_cannot_report_success(self):
        output = self.root / "build"
        self.build_fixture(output)
        for failure in ("notarytool:submit", "stapler:staple", "stapler:validate", "spctl"):
            with self.subTest(failure=failure):
                before = len(self.calls())
                result = self.run_script("notarize.sh", FLEETCONSOLE_OUTPUT_DIR=str(output),
                                         FLEET_TEST_NOTARY_FAILURE=failure)
                self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
                self.assertNotIn("✓ notarized", result.stdout)
                calls = self.calls()[before:]
                if failure == "notarytool:submit":
                    self.assertFalse(any(call["tool"] == "xcrun" and call["args"][0] == "stapler"
                                         for call in calls))
                if failure in ("notarytool:submit", "stapler:staple", "stapler:validate"):
                    self.assertNotIn("spctl", [call["tool"] for call in calls])


class StagingIdentityTests(ScriptFixture):
    def setUp(self):
        super().setUp()
        spec = importlib.util.spec_from_file_location("fleet_release_staging", SCRIPTS / "release-staging.py")
        if spec is None or spec.loader is None:
            self.fail("Cannot load the actual production staging guard")
        self.staging = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.staging)
        self.protected = self.root / "fixture-applications"
        self.protected.mkdir()
        (self.protected / "keep.txt").write_text("TEST DATA: protected location\n")

    def test_firmlink_style_ancestor_identity_blocks_missing_descendants(self):
        alias = self.root / "fixture-firmlink-alias"
        alias.mkdir()
        protected_info = self.protected.stat()
        alias_info = alias.stat()
        real_fstat = os.fstat

        def firmlink_test_data(fd):
            info = real_fstat(fd)
            # TEST DATA ONLY: different path spelling, same device/inode as Applications.
            return protected_info if (info.st_dev, info.st_ino) == (alias_info.st_dev, alias_info.st_ino) else info

        before = snapshot(alias)
        for reserve in (False, True):
            with self.subTest(reserve=reserve), mock.patch.object(self.staging.os, "fstat", side_effect=firmlink_test_data):
                with self.assertRaisesRegex(self.staging.StagingError, "stage outside Applications"):
                    self.staging.stage_output(alias / "new/descendant", reserve=reserve, protected_dirs=[self.protected])
        self.assertEqual(snapshot(alias), before)

    def test_host_applications_firmlink_check_is_read_only(self):
        system = Path("/Applications")
        data_alias = Path("/System/Volumes/Data/Applications")
        if not system.is_dir() or not data_alias.is_dir() or not os.path.samefile(system, data_alias):
            self.skipTest("Host has no macOS Applications firmlink; portable inode fixture covers it")
        # check-only production entry point: no real Applications writes, even if it regresses.
        with self.assertRaisesRegex(self.staging.StagingError, "stage outside Applications"):
            self.staging.stage_output(data_alias / "FleetConsole-release-policy-test-data/never-created")

    def test_unknown_protected_identity_fails_closed(self):
        real_stat = Path.stat

        def inaccessible(path, *args, **kwargs):
            if path == self.protected:
                raise PermissionError("TEST DATA: cannot read protected identity")
            return real_stat(path, *args, **kwargs)

        with mock.patch.object(Path, "stat", inaccessible), self.assertRaises(PermissionError):
            self.staging.stage_output(self.root / "new-stage", reserve=True, protected_dirs=[self.protected])
        self.assertFalse((self.root / "new-stage").exists())

    def test_unknown_ancestor_identity_fails_closed(self):
        with mock.patch.object(self.staging.os, "fstat", side_effect=PermissionError("TEST DATA: inaccessible ancestor")):
            with self.assertRaises(PermissionError):
                self.staging.stage_output(self.root / "new-stage", reserve=True, protected_dirs=[self.protected])
        self.assertFalse((self.root / "new-stage").exists())

    def test_symlink_swap_after_resolution_fails_closed(self):
        real_open = os.open
        original = self.root / "original-stage"

        def swap(name, flags, *args, **kwargs):
            if name == self.stage.name and "dir_fd" in kwargs and not original.exists():
                self.stage.rename(original)
                self.stage.symlink_to(self.protected, target_is_directory=True)
            return real_open(name, flags, *args, **kwargs)

        before = snapshot(self.protected)
        with mock.patch.object(self.staging.os, "open", side_effect=swap), self.assertRaises(OSError):
            self.staging.stage_output(self.stage, reserve=True, protected_dirs=[self.protected])
        self.assertEqual(snapshot(self.protected), before)

    def test_atomic_reservation_does_not_replace_a_last_moment_bundle(self):
        real_mkdir = os.mkdir

        def collide(name, *args, **kwargs):
            if name == "FleetConsole.app":
                real_mkdir(name, *args, **kwargs)
                (self.app / "keep.txt").write_text("TEST DATA: atomic race winner\n")
            return real_mkdir(name, *args, **kwargs)

        with mock.patch.object(self.staging.os, "mkdir", side_effect=collide):
            with self.assertRaisesRegex(self.staging.StagingError, "output bundle already exists"):
                self.staging.stage_output(self.stage, reserve=True, protected_dirs=[self.protected])
        self.assertEqual(snapshot(self.app), {"keep.txt": ("file", b"TEST DATA: atomic race winner\n")})


class BenchmarkTests(ScriptFixture):
    def setUp(self):
        super().setUp()
        executable = self.bin / "FleetConsoleApp"
        executable.write_text(
            "#!/usr/bin/env python3\n"
            "# TEST DATA ONLY: emit supplied receipts, never launch the native app.\n"
            "import os, sys\nfrom pathlib import Path\n"
            "root = Path(os.environ['FLEET_TEST_ROOT']).resolve()\n"
            "output = Path(sys.argv[2]).resolve()\n"
            "if sys.argv[1] != '--verify-live' or not output.is_relative_to(root):\n"
            "    raise SystemExit('Unsafe TEST DATA receipt output')\n"
            "if os.environ.get('FLEET_TEST_NO_RECEIPT') == '1':\n"
            "    raise SystemExit(0)\n"
            "(output / 'receipt.json').write_text(os.environ['FLEET_TEST_RECEIPT'])\n"
        )
        executable.chmod(0o755)
        self.receipt = {
            "testData": True, "valid": True, "configuration": "release",
            "processCPUPercent": 3.5, "benchmarkSeconds": 60.0,
        }

    def benchmark(self, *, receipt=None, optimize="0", budget=""):
        return self.run_script(
            "benchmark.sh", "60", str(self.root / "benchmark-test-data"),
            FLEET_TEST_RECEIPT=json.dumps(self.receipt if receipt is None else receipt),
            PYTHONOPTIMIZE=optimize, FLEET_BENCHMARK_CPU_BUDGET=budget,
        )

    def test_prior_valid_receipt_cannot_accept_a_noop_repeat_under_optimization(self):
        output = self.root / "benchmark-test-data"
        first = self.benchmark(optimize="1")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        evidence = Path(next(line.removeprefix("Evidence: ") for line in first.stdout.splitlines()
                             if line.startswith("Evidence: ")))
        before = snapshot(evidence)
        repeat = self.run_script(
            "benchmark.sh", "60", str(output), FLEET_TEST_NO_RECEIPT="1", PYTHONOPTIMIZE="1",
        )
        self.expect_failure(repeat, "Invalid verification receipt")
        self.assertNotIn("Evidence:", repeat.stdout)
        self.assertEqual(snapshot(evidence), before, "Prior successful evidence must not be deleted or reused")
        self.assertEqual(evidence.parent, output)
        runs = list(output.glob("run.*"))
        self.assertEqual(len(runs), 2, "Each invocation must get its own evidence directory")
        failed = next(path for path in runs if path != evidence)
        self.assertFalse((failed / "receipt.json").exists())

    def test_failed_receipt_is_rejected_under_optimization(self):
        result = self.benchmark(receipt=dict(self.receipt, valid=False), optimize="1")
        self.expect_failure(result, "Native live verification failed")
        self.assertNotIn("Evidence:", result.stdout)

    def test_debug_receipt_is_rejected_under_optimization(self):
        result = self.benchmark(receipt=dict(self.receipt, configuration="debug"), optimize="1")
        self.expect_failure(result, "Expected optimized code")
        self.assertNotIn("Evidence:", result.stdout)

    def test_exceeded_budget_is_rejected_under_optimization(self):
        result = self.benchmark(optimize="1", budget="2")
        self.expect_failure(result, "CPU budget exceeded")
        self.assertNotIn("Evidence:", result.stdout)

    def test_valid_must_be_literal_true(self):
        for optimize in ("0", "1"):
            for value in (1, "true", "false", False, None, [True]):
                with self.subTest(optimize=optimize, value=value):
                    result = self.benchmark(receipt=dict(self.receipt, valid=value), optimize=optimize)
                    self.expect_failure(result, "Native live verification failed")
                    self.assertNotIn("Evidence:", result.stdout)

    def test_configuration_must_be_literal_release(self):
        for optimize in ("0", "1"):
            for value in ("debug", "Release", True, None):
                with self.subTest(optimize=optimize, value=value):
                    result = self.benchmark(receipt=dict(self.receipt, configuration=value), optimize=optimize)
                    self.expect_failure(result, "Expected optimized code")

    def test_measurements_must_be_finite_numbers_not_booleans(self):
        invalid = [float("nan"), float("inf"), -float("inf"), True, False, "3.5", None, -1, 10**400]
        for optimize in ("0", "1"):
            for key, message in (("processCPUPercent", "Invalid CPU measurement"),
                                 ("benchmarkSeconds", "Invalid benchmark duration")):
                for value in invalid + ([0] if key == "benchmarkSeconds" else []):
                    with self.subTest(optimize=optimize, key=key, value=value):
                        result = self.benchmark(receipt=dict(self.receipt, **{key: value}), optimize=optimize)
                        self.expect_failure(result, message)
                        self.assertNotIn("Evidence:", result.stdout)

    def test_budgets_must_be_finite_and_positive(self):
        for optimize in ("0", "1"):
            for budget in ("nan", "inf", "-inf", "0", "-1", "not-a-number", "1e400"):
                with self.subTest(optimize=optimize, budget=budget):
                    result = self.benchmark(optimize=optimize, budget=budget)
                    self.expect_failure(result, "CPU budget must be finite and positive")
                    self.assertNotIn("Evidence:", result.stdout)

    def test_missing_fields_and_nonobject_receipts_are_rejected(self):
        invalid = [[], "TEST DATA: not a receipt"]
        for key in ("valid", "configuration", "processCPUPercent", "benchmarkSeconds"):
            receipt = self.receipt.copy()
            del receipt[key]
            invalid.append(receipt)
        for optimize in ("0", "1"):
            for receipt in invalid:
                with self.subTest(optimize=optimize, receipt=receipt):
                    result = self.benchmark(receipt=receipt, optimize=optimize)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn("Evidence:", result.stdout)

    def test_valid_receipts_pass_with_and_without_optimization(self):
        for optimize in ("0", "1"):
            for cpu, seconds, budget in ((0, 60, ""), (3.5, 60.0, "3.5"), (3.5, 60.0, "4")):
                with self.subTest(optimize=optimize, cpu=cpu, budget=budget):
                    result = self.benchmark(
                        receipt=dict(self.receipt, processCPUPercent=cpu, benchmarkSeconds=seconds),
                        optimize=optimize, budget=budget,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("Evidence:", result.stdout)

    def test_missing_and_malformed_receipts_are_rejected(self):
        for optimize in ("0", "1"):
            for index, raw in enumerate(("null", "{", "")):
                with self.subTest(optimize=optimize, raw=raw):
                    result = self.run_script(
                        "benchmark.sh", "60", str(self.root / f"invalid-receipt-{index}-{optimize}"),
                        FLEET_TEST_RECEIPT=raw, PYTHONOPTIMIZE=optimize,
                    )
                    self.expect_failure(result, "Invalid verification receipt")
                    self.assertNotIn("Evidence:", result.stdout)
            result = self.run_script(
                "benchmark.sh", "60", str(self.root / f"missing-receipt-{optimize}"),
                FLEET_TEST_NO_RECEIPT="1", PYTHONOPTIMIZE=optimize,
            )
            self.expect_failure(result, "Invalid verification receipt")
            self.assertNotIn("Evidence:", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
