#!/usr/bin/env python3
"""Export a committed core-only snapshot without private Git history."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys

EXACT_FILES = {"LICENSE", "docs/CLI.md", "docs/THREAT-MODEL.md", "docs/RUNBOOKS.md",
               "docs/MULTI-DEVICE.md", "docs/LAUNCH-COPY.md", "rust/Cargo.toml",
               "rust/Cargo.lock", "rust/.gitignore"}
TEMPLATES = {
    "Package.swift": "Release/PublicPackage.swift",
    "README.md": "Release/PUBLIC-README.md",
    "CONTRIBUTING.md": "Release/PUBLIC-CONTRIBUTING.md",
    "SECURITY.md": "Release/PUBLIC-SECURITY.md",
    ".github/workflows/ci.yml": "Release/public-ci.yml",
    "docs/CORE-DEVELOPMENT.md": "Release/CORE-DEVELOPMENT.md",
}


def is_public_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or str(path) != name:
        return False
    if name in EXACT_FILES:
        return True
    if any(name.startswith(prefix) for prefix in (
        "Sources/FleetCore/", "Sources/fleetd/", "Sources/fleetctl/", "Tests/FleetCoreTests/"
    )):
        return path.suffix == ".swift" and not any(part.startswith(".") for part in path.parts)
    for crate in ("fleet-proto", "fleet-conformance"):
        if name == f"rust/{crate}/Cargo.toml":
            return True
        if name.startswith(f"rust/{crate}/src/") and path.suffix == ".rs":
            return not any(part.startswith(".") for part in path.parts)
    return False


def git(root, *arguments):
    return subprocess.run(["git", "-C", str(root), *arguments], check=True,
                          capture_output=True).stdout


def export_revision(root, output, revision="HEAD"):
    root, output = Path(root), Path(output)
    if not revision or revision.startswith("-"):
        raise ValueError("Expected a Git commit or revision, not an option")
    commit = git(root, "rev-parse", "--verify", revision + "^{commit}").decode().strip()
    tree = {}
    for entry in git(root, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        tree[name.decode()] = (mode, kind, object_id)
    chosen = {name: name for name in tree if is_public_path(name)}
    chosen.update(TEMPLATES)
    required = {"LICENSE", "Sources/FleetCore/Models.swift", "Sources/fleetd/main.swift",
                "Sources/fleetctl/main.swift", *TEMPLATES.values()}
    missing = sorted(required - tree.keys())
    if missing:
        raise ValueError("Release inputs missing: " + ", ".join(missing))
    content = {}
    for destination, source in sorted(chosen.items()):
        mode, kind, object_id = tree[source]
        if mode not in {"100644", "100755"} or kind != "blob":
            raise ValueError("Refusing nonregular release input: " + source)
        content[destination] = git(root, "cat-file", "blob", object_id)
    content[".gitignore"] = b".build/\n.swiftpm/\nrust/target/\n.DS_Store\n*.log\n*.sqlite*\n.env*\n"
    content["SOURCE-REVISION"] = (commit + "\n").encode()
    # No replacement, merges, history, remotes or working-tree reads.
    output.mkdir(exist_ok=False)
    hashes = {}
    for name, data in sorted(content.items()):
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    receipt = {"sourceCommit": commit, "fileCount": len(content),
               "files": sorted(content), "sha256": hashes,
               "boundary": "MIT core, daemon, CLI and Rust; native UI and private history excluded"}
    (output / "PUBLIC-SOURCE-MANIFEST.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    if not 2 <= len(sys.argv) <= 3:
        raise SystemExit("Usage: export-public-source.py <fresh-directory> [revision]")
    root = Path(__file__).resolve().parent.parent
    receipt = export_revision(root, Path(sys.argv[1]), sys.argv[2] if len(sys.argv) == 3 else "HEAD")
    print(json.dumps({"sourceCommit": receipt["sourceCommit"], "sourceFileCount": receipt["fileCount"],
                      "output": str(Path(sys.argv[1]).resolve())}, indent=2))


if __name__ == "__main__":
    main()
