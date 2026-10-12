#!/usr/bin/env python3
"""Isolated notarization identity regressions; no native signing or Apple calls."""
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

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent


def tool():
    root = Path(os.environ["FLEET_TEST_ROOT"])
    if not (root / "TEST-DATA-ONLY").is_file():
        raise SystemExit("Not an isolated fixture")
    name, *args = sys.argv[2:]
    boundary = ("inspect" if name == "codesign" else "archive" if name == "ditto"
                else ":".join(args[:2]) if name == "xcrun" else "assess")
    saved = root / "saved"
    scratch_swap = os.environ.get("NOTARY_TEST_SCRATCH_SWAP")
    moved = root / "scratch-moved"
    if scratch_swap and boundary == "inspect" and not moved.exists():
        repository = root / "repository-parent/repository"
        scratch = next(repository.glob(".fleet-notary-*"))
        source = scratch if scratch_swap == "scratch" else repository.parent if scratch_swap == "ancestor" else repository
        source.rename(moved)
        source.mkdir()
        replacement = source if scratch_swap == "scratch" else source / ("repository" if scratch_swap == "ancestor" else "") / scratch.name
        replacement.mkdir(parents=True, exist_ok=True)
        sentinel = replacement / "FleetConsole-notarize.zip"
        sentinel.write_text("replacement archive sentinel")
        (root / "replacement-archive-path").write_text(str(sentinel))
    if boundary == os.environ.get("NOTARY_TEST_SWAP") and not saved.exists():
        source = root / "stage" if os.environ.get("NOTARY_TEST_ANCESTOR") else root / "stage/FleetConsole.app"
        source.rename(saved)
        source.symlink_to(root / "home/Applications" if os.environ.get("NOTARY_TEST_ANCESTOR")
                          else root / "home/Applications/FleetConsole.app", target_is_directory=True)
    target = None
    if name in ("codesign", "spctl"):
        target = Path(args[-1])
    elif name == "ditto":
        target = Path(args[-2])
    elif name == "xcrun" and args[0] == "stapler":
        target = Path(args[2])
    entry = {"tool": name, "args": args, "cwd": os.getcwd(), "boundary": boundary}
    if target is not None:
        if not target.resolve().is_relative_to(root):
            raise SystemExit("Target outside fixture")
        info = target.stat()
        entry["identity"] = [info.st_dev, info.st_ino]
    if name == "xcrun" and args[:2] == ["notarytool", "submit"]:
        archive = Path(args[2])
        if not archive.resolve().is_relative_to(root):
            raise SystemExit("Archive outside fixture")
        entry["archive_content"] = archive.read_text()
    with (root / "calls.jsonl").open("a") as stream:
        stream.write(json.dumps(entry) + "\n")
    if name == "codesign":
        print("Developer ID Application\nflags=0x10000(runtime)", file=sys.stderr)
    elif name == "ditto" and target is not None:
        Path(args[-1]).write_text("TEST DATA archive: " + (target / "marker").read_text())
    elif name == "xcrun" and args[:2] == ["stapler", "staple"] and target is not None:
        (target / "ticket").write_text("TEST DATA ticket")
    if boundary == os.environ.get("NOTARY_TEST_FAILURE"):
        raise SystemExit(42)


class NotaryStagingTests(unittest.TestCase):
    def setUp(self):
        scratch = os.environ.get("TMPDIR")
        if not scratch or not Path(scratch).is_dir():
            self.fail("TMPDIR must name an existing scratch directory")
        self.temp = tempfile.TemporaryDirectory(prefix="fleet-notary-test-data-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "TEST-DATA-ONLY").touch()
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for name in ("notarize.sh", "release-staging.py", "test-notary-staging.py"):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        self.home = self.root / "home"
        self.protected = self.home / "Applications"
        self.protected.mkdir(parents=True)
        self.stage = self.root / "stage"
        self.stage.mkdir()
        self.app = self.bundle(self.stage, "staged")
        self.installed = self.bundle(self.protected, "installed")
        env_file = self.root / "mock-boundaries.sh"
        env_file.write_text("\n".join(
            f'{name}() {{ "{sys.executable}" -B "{scripts / "test-notary-staging.py"}" --tool {label} "$@"; }}'
            for name, label in (("codesign", "codesign"), ("xcrun", "xcrun"),
                                ("spctl", "spctl"), ("/usr/bin/ditto", "ditto"))
        ) + "\n")
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("FLEETCONSOLE_")}
        self.env.update(HOME=str(self.home), BASH_ENV=str(env_file), FLEET_TEST_ROOT=str(self.root),
                        FLEETCONSOLE_OUTPUT_DIR=str(self.stage), PYTHONDONTWRITEBYTECODE="1")

    def bundle(self, parent, value):
        app = parent / "FleetConsole.app"
        app.mkdir()
        (app / "marker").write_text(value)
        return app

    def run_notary(self, **env):
        return subprocess.run(["/bin/bash", str(self.root / "Scripts/notarize.sh")], cwd=self.root,
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=10)

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_applications_alias_refused_before_tools_or_archive_changes(self):
        alias = self.root / "innocent"
        alias.symlink_to(self.protected, target_is_directory=True)
        archive = self.protected / "FleetConsole-notarize.zip"
        archive.write_text("existing archive")
        result = self.run_notary(FLEETCONSOLE_OUTPUT_DIR=str(alias))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("stage outside Applications", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(archive.read_text(), "existing archive")
        self.assertFalse((self.installed / "ticket").exists())

    def test_symlink_bundle_refused_before_tools(self):
        shutil.rmtree(self.app)
        self.app.symlink_to(self.installed, target_is_directory=True)
        result = self.run_notary()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.installed / "ticket").exists())

    def test_bundle_swaps_do_not_redirect_archive_staple_or_verification(self):
        identity = self.app.stat()
        result = self.run_notary(NOTARY_TEST_SWAP="inspect")
        self.assertTrue((self.root / "saved").is_dir(), "The race must execute")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.installed / "ticket").exists())
        self.assertTrue((self.root / "saved/ticket").is_file())
        for call in self.calls():
            if "identity" in call:
                self.assertEqual(call["identity"], [identity.st_dev, identity.st_ino], call)

    def test_ancestor_swap_does_not_redirect_archive_or_stapling(self):
        identity = self.app.stat()
        result = self.run_notary(NOTARY_TEST_SWAP="notarytool:submit", NOTARY_TEST_ANCESTOR="1")
        self.assertTrue((self.root / "saved").is_dir(), "The race must execute")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.installed / "ticket").exists())
        self.assertFalse((self.protected / "FleetConsole-notarize.zip").exists())
        for call in self.calls():
            if "identity" in call:
                self.assertEqual(call["identity"], [identity.st_dev, identity.st_ino], call)
    def load_staging(self):
        spec = importlib.util.spec_from_file_location("notary_staging", SCRIPTS / "release-staging.py")
        if spec is None or spec.loader is None:
            self.fail("Cannot load production staging guard")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_firmlink_style_alias_refused_by_ancestor_identity(self):
        staging = self.load_staging()
        alias_info = self.stage.stat()
        protected_info = self.protected.stat()
        real_fstat = os.fstat

        def firmlink(fd):
            info = real_fstat(fd)
            return protected_info if (info.st_dev, info.st_ino) == (alias_info.st_dev, alias_info.st_ino) else info

        with mock.patch.object(staging.os, "fstat", side_effect=firmlink):
            with self.assertRaisesRegex(staging.StagingError, "stage outside Applications"):
                with staging.notary_bundle(self.stage, protected_dirs=[self.protected]):
                    self.fail("Protected alias accepted")
        self.assertEqual(self.calls(), [])
        self.assertEqual((self.app / "marker").read_text(), "staged")

    def test_plain_directory_replacement_during_open_refused(self):
        staging = self.load_staging()
        real_open = os.open

        def replace(name, flags, *args, **kwargs):
            if name == "FleetConsole.app" and "dir_fd" in kwargs:
                self.app.rename(self.root / "original-app")
                self.bundle(self.stage, "replacement")
            return real_open(name, flags, *args, **kwargs)

        with mock.patch.object(staging.os, "open", side_effect=replace):
            with self.assertRaisesRegex(staging.StagingError, "identity changed while opening"):
                with staging.notary_bundle(self.stage, protected_dirs=[self.protected]):
                    self.fail("Replacement bundle accepted")
        self.assertEqual(self.calls(), [])

    def check_scratch_replacement(self, mode):
        repository = self.root / "repository-parent/repository"
        scripts = repository / "Scripts"
        scripts.mkdir(parents=True)
        for name in ("notarize.sh", "release-staging.py"):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        result = subprocess.run(["/bin/bash", str(scripts / "notarize.sh")], cwd=self.root,
                                env=dict(self.env, NOTARY_TEST_SCRATCH_SWAP=mode),
                                capture_output=True, text=True, timeout=10)
        self.assertTrue((self.root / "scratch-moved").is_dir(), "The scratch race must execute")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        sentinel = Path((self.root / "replacement-archive-path").read_text())
        self.assertEqual(sentinel.read_text(), "replacement archive sentinel")
        submitted = [call for call in self.calls() if call["boundary"] == "notarytool:submit"]
        self.assertEqual(len(submitted), 1)
        self.assertEqual(submitted[0]["archive_content"], "TEST DATA archive: staged")
        self.assertTrue((self.app / "ticket").is_file())

    def test_scratch_repository_replacement_preserves_archive_identity(self):
        self.check_scratch_replacement("repository")

    def test_scratch_ancestor_replacement_preserves_archive_identity(self):
        self.check_scratch_replacement("ancestor")

    def test_private_scratch_replacement_preserves_archive_identity_and_sentinel(self):
        self.check_scratch_replacement("scratch")

    def test_worker_argument_cannot_bypass_protected_location_guard(self):
        result = subprocess.run([
            "/bin/bash", str(self.root / "Scripts/notarize.sh"), "--pinned-notary",
            str(self.protected / "unsafe.zip"),
        ], cwd=self.installed, env=dict(self.env, FLEETCONSOLE_OUTPUT_DIR=str(self.protected)),
            capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.installed / "ticket").exists())


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--tool":
        tool()
    else:
        unittest.main(verbosity=2)
