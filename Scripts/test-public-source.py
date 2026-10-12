#!/usr/bin/env python3
"""Regress the core-only export; no native builds or external writes."""
import importlib.util
import os
from pathlib import Path
import tempfile
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


def load_exporter():
    spec = importlib.util.spec_from_file_location("public_export", ROOT / "Scripts/export-public-source.py")
    if spec is None or spec.loader is None:
        raise ImportError("Cannot load public exporter")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicSourceTests(unittest.TestCase):
    def test_allowlist_excludes_ui_credentials_and_private_media(self):
        module = load_exporter()
        for name in ["Sources/FleetCore/Models.swift", "Sources/fleetd/main.swift",
                     "Sources/fleetctl/main.swift", "Tests/FleetCoreTests/ConfigTests.swift",
                     "rust/fleet-proto/src/lib.rs", "rust/fleet-conformance/src/main.rs",
                     "rust/Cargo.lock", "LICENSE"]:
            self.assertTrue(module.is_public_path(name), name)
        for name in ["Sources/FleetConsoleApp/main.swift", "Tests/FleetConsoleAppTests/A.swift",
                     ".git/config", "AGENTS.md", "docs/AGENTS.md", ".env",
                     "rust/target/debug/fleet-conformance", "ad-private/soundtrack.wav",
                     "build/FleetConsole.app/Contents/MacOS/FleetConsole",
                     "Sources/FleetCore/key.p8", "Sources/FleetCore/.env",
                     "Sources/FleetCore/debug.log", "Sources/FleetCore/runtime.sqlite"]:
            self.assertFalse(module.is_public_path(name), name)

    def test_export_uses_only_committed_allowlisted_content_and_public_templates(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as temporary:
            repo = Path(temporary) / "private"
            repo.mkdir()
            files = {
                "Sources/FleetCore/Models.swift": "// test core\n",
                "Sources/fleetd/main.swift": "// test daemon\n",
                "Sources/fleetctl/main.swift": "// test CLI\n",
                "Sources/FleetConsoleApp/main.swift": "PRIVATE UI\n",
                ".env": "PRIVATE CREDENTIAL FIXTURE\n",
                "LICENSE": "MIT test license\n",
                "README.md": "PRIVATE README\n",
                "Release/PublicPackage.swift": "// public test package\n",
                "Release/PUBLIC-README.md": "public test README\n",
                "Release/PUBLIC-CONTRIBUTING.md": "test contributions\n",
                "Release/PUBLIC-SECURITY.md": "test security\n",
                "Release/public-ci.yml": "name: test\n",
                "Release/CORE-DEVELOPMENT.md": "test core development\n",
            }
            for name, content in files.items():
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "user.name=Fixture",
                            "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"], check=True)
            (repo / "Sources/FleetCore/Models.swift").write_text("UNCOMMITTED CHANGE\n")
            (repo / "Sources/FleetCore/Untracked.swift").write_text("UNTRACKED\n")
            output = Path(temporary) / "public"
            module = load_exporter()
            self.assertTrue(hasattr(module, "export_revision"), "Committed snapshot exporter missing")
            receipt = module.export_revision(repo, output, "HEAD")
            self.assertEqual((output / "Sources/FleetCore/Models.swift").read_text(), "// test core\n")
            self.assertEqual((output / "README.md").read_text(), "public test README\n")
            self.assertEqual((output / "Package.swift").read_text(), "// public test package\n")
            self.assertFalse((output / "Sources/FleetConsoleApp").exists())
            self.assertFalse((output / ".env").exists())
            self.assertFalse((output / ".git").exists())
            self.assertFalse((output / "Sources/FleetCore/Untracked.swift").exists())
            self.assertEqual(receipt["fileCount"], len(receipt["files"]))
            self.assertEqual((output / "SOURCE-REVISION").read_text().strip(), receipt["sourceCommit"])
            sentinel = output / "sentinel"
            sentinel.write_text("keep\n")
            with self.assertRaises(FileExistsError):
                module.export_revision(repo, output, "HEAD")
            self.assertEqual(sentinel.read_text(), "keep\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
