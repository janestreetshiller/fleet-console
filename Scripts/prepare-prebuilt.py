from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(arguments):
    return subprocess.check_output([str(v) for v in arguments], text=True, timeout=120)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--core-sha256', required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if (not re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}', args.source_revision)
            or not re.fullmatch(r'[a-f0-9]{64}', args.core_sha256)
            or not re.fullmatch(r'[A-Z0-9]{10}', args.team)
            or args.output.exists()
            or not args.output.resolve().is_relative_to(root / 'artifacts')):
        raise ValueError('Fresh owning artifact output and explicit source/core/team are required')
    metadata = plistlib.loads((args.bundle / 'Contents/Info.plist').read_bytes())
    identity = json.loads(run([args.bundle / 'Contents/MacOS/FleetConsole', '--design-core-identity']))
    if (metadata.get('CFBundleIdentifier') != 'com.fleetconsole.app'
            or metadata.get('FleetSourceRevision') != args.source_revision
            or metadata.get('FleetSourceDirty') is not False
            or metadata.get('OurosDesignCoreSHA256') != args.core_sha256
            or identity.get('sourceSHA256') != args.core_sha256):
        raise ValueError('Actual signed Fleet source/core identity differs')
    requirement = f'identifier "com.fleetconsole.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "{args.team}"'
    run(['codesign', '--verify', '--deep', '--strict', '-R=' + requirement, args.bundle])
    run(['xcrun', 'stapler', 'validate', args.bundle])
    run(['spctl', '--assess', '--type', 'execute', '--verbose=2', args.bundle])
    args.output.mkdir(parents=True)
    scripts = args.output / 'Scripts'
    scripts.mkdir()
    for name in ['update-installed.sh', 'verify-core-update.py']:
        shutil.copyfile(root / 'Scripts' / name, scripts / name)
    bundle = args.output / 'FleetConsole.app'
    run(['ditto', args.bundle, bundle])
    result = {'format': 'fleet-console-prebuilt-v1', 'sourceRevision': args.source_revision, 'coreSHA256': args.core_sha256, 'team': args.team, 'version': metadata['CFBundleShortVersionString'], 'build': metadata['CFBundleVersion'], 'executableSHA256': sha(bundle / 'Contents/MacOS/FleetConsole'), 'toolSHA256': {name: sha(scripts / name) for name in ['update-installed.sh', 'verify-core-update.py']}}
    (args.output / 'handoff.json').write_text(json.dumps(result, indent=2) + '\n')
    result['handoffSHA256'] = sha(args.output / 'handoff.json')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
