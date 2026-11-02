import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import hashlib


class UpdateIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fleet-core-update-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.installed = self.root / 'installed.app'
        self.candidate = self.root / 'candidate.app'
        self.core = '1' * 64
        self.revision = '2' * 40
        self.old = {'CFBundleIdentifier': 'com.fleetconsole.app', 'CFBundleShortVersionString': '1.3.0', 'CFBundleVersion': '11', 'CFBundleExecutable': 'FleetConsole', 'FleetSourceRevision': '3' * 40, 'FleetSourceDirty': False}
        self.new = dict(self.old, CFBundleShortVersionString='1.3.1', CFBundleVersion='1.3.1', FleetSourceRevision=self.revision, OurosDesignCoreVersion='1.1.2', OurosDesignCoreSHA256=self.core)
        for bundle, info in [(self.installed, self.old), (self.candidate, self.new)]:
            (bundle / 'Contents/MacOS').mkdir(parents=True)
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            (bundle / 'Contents/MacOS/FleetConsole').write_text('fixture installed executable')
        self.write_candidate(self.core)
        self.proof = self.root / 'predecessor.json'
        self.proof.write_text(json.dumps({'fleet': {'path': str(self.installed), 'info': self.old, 'executableSHA256': hashlib.sha256((self.installed / 'Contents/MacOS/FleetConsole').read_bytes()).hexdigest()}}))

    def write_candidate(self, core):
        executable = self.candidate / 'Contents/MacOS/FleetConsole'
        identity = json.dumps({'version': '1.1.2', 'sourceSHA256': core})
        executable.write_text('#!' + sys.executable + '\nimport pathlib\npathlib.Path(' + repr(str(self.root / 'candidate-ran')) + ').touch()\nprint(' + repr(identity) + ')\n')
        executable.chmod(0o755)

    def invoke(self):
        return subprocess.run([sys.executable, str(Path(__file__).with_name('verify-core-update.py')), str(self.installed), str(self.candidate), str(self.proof), self.core, self.revision], capture_output=True, text=True, timeout=10)

    def assert_refused(self):
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_matching_actual_predecessor_and_compiled_core_pass(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_replaced_installed_executable_is_refused_before_candidate_execution(self):
        (self.installed / 'Contents/MacOS/FleetConsole').write_text('new owner executable')
        self.assert_refused()
        self.assertFalse((self.root / 'candidate-ran').exists())

    def test_changed_installed_metadata_is_refused(self):
        (self.installed / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(self.old, CFBundleVersion='12')))
        self.assert_refused()

    def test_matching_plist_cannot_hide_old_compiled_core(self):
        self.write_candidate('4' * 64)
        self.assert_refused()

    def test_dirty_or_different_source_is_refused(self):
        for replacement in [dict(self.new, FleetSourceDirty=True), dict(self.new, FleetSourceRevision='5' * 40)]:
            with self.subTest(replacement=replacement):
                (self.candidate / 'Contents/Info.plist').write_bytes(plistlib.dumps(replacement))
                self.assert_refused()

    def test_old_product_version_is_refused(self):
        (self.candidate / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(self.new, CFBundleShortVersionString='1.3.0')))
        self.assert_refused()


if __name__ == '__main__':
    unittest.main()
