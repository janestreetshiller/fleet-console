import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def snapshot(bundle):
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    keys = ['CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleExecutable', 'OurosSourceRevision', 'OurosSourceHasLocalChanges', 'OurosSourceRepository', 'OurosSourceDigest', 'OurosDevelopmentOnly', 'FleetSourceRevision', 'FleetSourceDirty']
    executable = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
    return {'path': str(bundle), 'info': {key: info[key] for key in keys if key in info}, 'executableSHA256': hashlib.sha256(executable.read_bytes()).hexdigest()}


def check(installed, candidate, proof, core, revision):
    expected = json.loads(proof.read_text())['fleet']
    if snapshot(installed) != expected:
        raise ValueError('Installed Fleet predecessor changed; no replacement is authorized')
    info = plistlib.loads((candidate / 'Contents/Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'com.fleetconsole.app'
            or info.get('FleetSourceRevision') != revision
            or info.get('FleetSourceDirty') is not False
            or info.get('OurosDesignCoreSHA256') != core):
        raise ValueError('Fleet candidate source or pinned core metadata differs')
    identity = json.loads(subprocess.check_output([candidate / 'Contents/MacOS/FleetConsole', '--design-core-identity'], text=True, timeout=30))
    if identity.get('sourceSHA256') != core or identity.get('version') != info.get('OurosDesignCoreVersion'):
        raise ValueError('Compiled Fleet candidate core differs before replacement')
    version = lambda value: tuple(int(part) for part in value.split('.'))
    if version(info['CFBundleShortVersionString']) <= version(expected['info']['CFBundleShortVersionString']):
        raise ValueError('Fleet candidate must advance the installed product release')


if __name__ == '__main__':
    try:
        if len(sys.argv) == 3 and sys.argv[1] == '--snapshot':
            print(json.dumps({'fleet': snapshot(Path(sys.argv[2]))}, indent=2))
        else:
            check(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4], sys.argv[5])
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
