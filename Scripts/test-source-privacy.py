#!/usr/bin/env python3
"""Public-source identity regression; stdlib only, no builds or live probes.

Run: python3 Scripts/test-source-privacy.py
Scans the current Git deliverable manifest, including nonignored new files, not
history or build caches. AGENTS.md and license texts retain intended attribution.
This is a focused identity check, not a general secret scanner or runtime audit.
"""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
RULES = {
    "maintainer-home": re.compile(r"/Users/" + r"main\b"),
    "maintainer-host": re.compile(r"\bmetal" + r"-mini\b", re.I),
    "maintainer-tailnet": re.compile(r"\btail8a" + r"000f\b", re.I),
    "maintainer-overlay-address": re.compile(r"\b100\.98" + r"\.105\.78\b"),
}


def excluded(path):
    name = Path(path).name.upper()
    return name == "AGENTS.MD" or name in {"LICENSE", "LICENSE.MD", "LICENSE.TXT"}


def findings(path, text):
    """Return locations and rule names only, never identifying line contents."""
    if excluded(path):
        return []
    return [
        (str(path), number, rule)
        for number, line in enumerate(text.splitlines(), 1)
        for rule, pattern in RULES.items()
        if pattern.search(line)
    ]


def manifest():
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, check=True, capture_output=True,
    )
    return sorted(set(result.stdout.decode("utf-8").rstrip("\0").split("\0")) - {""})


class ScannerTests(unittest.TestCase):
    def test_each_identifier_is_rejected_without_echoing_it(self):
        samples = {
            "maintainer-home": "/Users/" + "main/Workspace/example",
            "maintainer-host": "metal" + "-mini",
            "maintainer-tailnet": "node.tail8a" + "000f.ts.net.",
            "maintainer-overlay-address": "100.98" + ".105.78",
        }
        for rule, sample in samples.items():
            with self.subTest(rule=rule):
                self.assertEqual(findings("Sources/example.swift", sample),
                                 [("Sources/example.swift", 1, rule)])

    def test_synthetic_examples_and_attribution_are_allowed(self):
        self.assertEqual(findings("Sources/example.swift", "/Users/demo node.example.ts.net."), [])
        for path in ("AGENTS.md", "docs/AGENTS.md", "LICENSE", "rust/LICENSE.txt"):
            with self.subTest(path=path):
                self.assertEqual(findings(path, "/Users/" + "main metal" + "-mini"), [])

    def test_noninstruction_docs_are_not_excluded(self):
        self.assertEqual(findings("docs/PRODUCT-SPEC.md", "metal" + "-mini"),
                         [("docs/PRODUCT-SPEC.md", 1, "maintainer-host")])


class SourcePrivacyTests(unittest.TestCase):
    def test_public_deliverables_have_no_known_maintainer_identifiers(self):
        paths = manifest()
        self.assertIn("Sources/FleetConsoleApp/SurfaceRenderer.swift", paths)
        violations = []
        scanned = 0
        for relative in paths:
            if excluded(relative):
                continue
            path = ROOT / relative
            if not path.is_file():
                continue  # A tracked deletion is not in the current deliverable.
            data = path.read_bytes()
            if b"\0" in data:
                continue  # Binary assets are outside this source-text check.
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            scanned += 1
            violations.extend(findings(relative, text))
        self.assertGreater(scanned, 0)
        summary = "\n".join(f"{path}:{line}: {rule}" for path, line, rule in violations)
        self.assertFalse(violations, "Known maintainer identifiers in public source:\n" + summary)
        print(f"source privacy: {scanned} text deliverables checked")

    def test_renderer_identity_does_not_read_the_rendering_machine(self):
        renderer = (ROOT / "Sources/FleetConsoleApp/SurfaceRenderer.swift").read_text()
        for expression in ("NSHomeDirectory(", "NSUserName(", "Host.current(", "FleetPaths.",
                           "model.settings.config.networkSegments"):
            with self.subTest(expression=expression):
                self.assertFalse(expression in renderer,
                                 f"Renderer fixture reads machine identity: {expression}")
        self.assertTrue("VLANRegistry.shared.adopt(Fixtures.segments)" in renderer,
                        "Renderer must adopt synthetic segment declarations")


if __name__ == "__main__":
    unittest.main(verbosity=2)
