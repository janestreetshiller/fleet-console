#!/usr/bin/env python3
"""Fail-closed output checks and atomic fresh-bundle reservation for build-app.sh."""
from contextlib import contextmanager
import os
from pathlib import Path
import stat
import subprocess
import sys

BUNDLE_NAME = "FleetConsole.app"


class StagingError(ValueError):
    pass


def _canonical_directory(path):
    """Resolve the existing prefix strictly; missing suffixes cannot hide symlinks."""
    path = Path(path)
    if not path.is_absolute():
        raise StagingError("staging destination must be absolute")
    current = path
    missing = []
    while True:
        try:
            current.lstat()
            break
        except FileNotFoundError:
            if current == current.parent:
                raise StagingError("cannot establish the staging destination")
            missing.append(current.name)
            current = current.parent
    current = current.resolve(strict=True)
    if not stat.S_ISDIR(current.stat().st_mode):
        raise StagingError("staging destination has a non-directory ancestor")
    # Only the missing suffix is normalized; existing symlinks were resolved first.
    return Path(os.path.normpath(str(current.joinpath(*reversed(missing)))))


def _protected_locations(directories):
    paths = []
    identities = set()
    for directory in directories:
        path = _canonical_directory(directory)
        paths.append(path)
        try:
            info = path.stat()
        except FileNotFoundError:
            # ~/Applications (or /Applications on non-macOS test hosts) may not exist.
            # Its canonical path is still forbidden, and all other errors fail closed.
            if sys.platform == "darwin" and Path(directory) == Path("/Applications"):
                raise StagingError("cannot establish Applications filesystem identity")
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise StagingError("cannot establish Applications filesystem identity")
        identities.add((info.st_dev, info.st_ino))
    return paths, identities


@contextmanager
def _output_directory(path, identities, create):
    """Check every ancestor by identity before creating anything beneath it.

    Directory-relative, no-follow opens also fail if a resolved ancestor turns
    into a symlink between resolution and use. macOS firmlinks retain their own
    spelling after realpath, but the Applications device/inode pair still matches.
    """
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(path.anchor, flags)
    try:
        for name in (*path.parts[1:], None):
            info = os.fstat(fd)
            if (info.st_dev, info.st_ino) in identities:
                raise StagingError("stage outside Applications; building must not replace an installed app")
            if name is None:
                break
            try:
                child = os.open(name, flags, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    yield None
                    return
                os.mkdir(name, dir_fd=fd)
                child = os.open(name, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


@contextmanager
def _stage_output(output_dir, *, reserve=False, protected_dirs=None):
    """Keep the checked output fd alive through reservation and its consumer.

    protected_dirs is a library seam for isolated filesystem fixtures, not a CLI
    or environment override; production always protects system/user Applications.
    """
    if protected_dirs is None:
        protected_dirs = (Path("/Applications"), Path.home() / "Applications")
    paths, identities = _protected_locations(protected_dirs)
    output = _canonical_directory(output_dir)
    if any(output == path or path in output.parents for path in paths):
        raise StagingError("stage outside Applications; building must not replace an installed app")
    with _output_directory(output, identities, reserve) as fd:
        if fd is not None:
            try:
                os.stat(BUNDLE_NAME, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise StagingError("output bundle already exists; choose a fresh FLEETCONSOLE_OUTPUT_DIR")
            if reserve:
                try:
                    os.mkdir(BUNDLE_NAME, dir_fd=fd)
                except FileExistsError as error:
                    raise StagingError("output bundle already exists; choose a fresh FLEETCONSOLE_OUTPUT_DIR") from error
        yield output, fd


def stage_output(output_dir, *, reserve=False, protected_dirs=None):
    """Check/reserve only; the returned path is descriptive, not write authority."""
    with _stage_output(output_dir, reserve=reserve, protected_dirs=protected_dirs) as (output, _):
        pass
    return output / BUNDLE_NAME if reserve else output


def assemble(output_dir, root, bin_dir, configuration):
    """Run ALL bundle operations relative to the reserved bundle's open identity."""
    if configuration not in ("debug", "release"):
        raise StagingError("configuration must be debug or release")
    root = Path(root).resolve(strict=True)
    bin_dir = Path(bin_dir).resolve(strict=True)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    with _stage_output(output_dir, reserve=True) as (_, output_fd):
        bundle_fd = os.open(BUNDLE_NAME, flags, dir_fd=output_fd)
        try:
            previous_cwd = os.open(".", flags)
            try:
                os.fchdir(bundle_fd)
                # cwd is an OS-held directory identity, not a path passed to the
                # child. Neither ancestor nor bundle renames can redirect '.'.
                result = subprocess.run([
                    "/bin/bash", str(root / "Scripts/assemble-app.sh"),
                    str(root), str(bin_dir), configuration,
                ], check=False).returncode
                if result == 0:
                    # Shell pwd can resolve a stale PWD through a replacement
                    # symlink. getcwd reports this still-pinned directory instead.
                    print(f"\n✓ built {os.getcwd()}\n")
                    print("No app was installed and no controller was stopped or restarted.")
                    print("See docs/RELEASE.md for release checks and deliberate installation.")
                return result
            finally:
                os.fchdir(previous_cwd)
                os.close(previous_cwd)
        finally:
            os.close(bundle_fd)


@contextmanager
def notary_bundle(output_dir, *, protected_dirs=None):
    """Open an existing, non-symlink artifact beneath checked ancestor identities."""
    if protected_dirs is None:
        protected_dirs = (Path("/Applications"), Path.home() / "Applications")
    paths, identities = _protected_locations(protected_dirs)
    output = _canonical_directory(output_dir)
    if any(output == path or path in output.parents for path in paths):
        raise StagingError("stage outside Applications; notarization must not mutate an installed app")
    with _output_directory(output, identities, False) as output_fd:
        if output_fd is None:
            raise StagingError("notarization output directory does not exist")
        expected = os.stat(BUNDLE_NAME, dir_fd=output_fd, follow_symlinks=False)
        if not stat.S_ISDIR(expected.st_mode):
            raise StagingError("notarization bundle must be a real directory, not a symlink")
        fd = os.open(BUNDLE_NAME, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=output_fd)
        try:
            opened = os.fstat(fd)
            if (opened.st_dev, opened.st_ino) != (expected.st_dev, expected.st_ino):
                raise StagingError("notarization bundle identity changed while opening")
            if (opened.st_dev, opened.st_ino) in identities:
                raise StagingError("stage outside Applications")
            yield fd
        finally:
            os.close(fd)


@contextmanager
def _notary_archive(root_fd):
    """Keep scratch creation, archive writes and cleanup on held identities."""
    import tempfile
    scratch = tempfile.mkdtemp(prefix=".fleet-notary-", dir=".")
    expected = os.stat(scratch, dir_fd=root_fd, follow_symlinks=False)
    private_fd = archive_fd = None
    name = "FleetConsole-notarize.zip"
    try:
        private_fd = os.open(scratch, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root_fd)
        opened = os.fstat(private_fd)
        if (opened.st_dev, opened.st_ino) != (expected.st_dev, expected.st_ino):
            raise StagingError("archive scratch identity changed while opening")
        archive_fd = os.open(name, os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_NOFOLLOW,
                             0o600, dir_fd=private_fd)
        yield private_fd, archive_fd, name
    finally:
        if archive_fd is not None:
            try:
                info = os.fstat(archive_fd)
                current = os.stat(name, dir_fd=private_fd, follow_symlinks=False)
                if (info.st_dev, info.st_ino) == (current.st_dev, current.st_ino):
                    os.unlink(name, dir_fd=private_fd)
            except FileNotFoundError:
                pass
            finally:
                os.close(archive_fd)
        if private_fd is not None:
            os.close(private_fd)
        try:
            current = os.stat(scratch, dir_fd=root_fd, follow_symlinks=False)
            if (current.st_dev, current.st_ino) == (expected.st_dev, expected.st_ino):
                os.rmdir(scratch, dir_fd=root_fd)
        except FileNotFoundError:
            pass


def notarize(output_dir, root):
    """Hold bundle, scratch and archive identities through the shell pipeline."""
    root = Path(root).resolve(strict=True)
    env = os.environ.copy()
    if env.get("FLEETCONSOLE_ASC_KEY"):
        env["FLEETCONSOLE_ASC_KEY"] = os.path.abspath(env["FLEETCONSOLE_ASC_KEY"])
    script = root / "Scripts/notarize.sh"
    worker = script.read_text().split("# PINNED NOTARY WORKER\n", 1)[1]
    with notary_bundle(output_dir) as bundle_fd:
        previous_cwd = os.open(".", os.O_RDONLY | os.O_DIRECTORY)
        try:
            # Private archive scratch is independent of the mutable output path.
            # Keep its root pinned for creation/cleanup too; a renamed stage
            # cannot redirect archive writes or remove a pre-existing archive.
            _, identities = _protected_locations((Path("/Applications"), Path.home() / "Applications"))
            with _output_directory(root, identities, False) as scratch_fd:
                if scratch_fd is None:
                    raise StagingError("archive scratch root is unavailable")
                os.fchdir(scratch_fd)
                with _notary_archive(scratch_fd) as (private_fd, archive_fd, name):
                    os.fchdir(bundle_fd)
                    return subprocess.run([
                        "/bin/bash", "-c", worker, str(script),
                        f"/dev/fd/{archive_fd}", str(private_fd), name,
                    ], env=env, pass_fds=(private_fd, archive_fd), check=False).returncode
        finally:
            os.fchdir(previous_cwd)
            os.close(previous_cwd)


def main():
    checking = len(sys.argv) == 3 and sys.argv[1] == "check"
    assembling = len(sys.argv) == 6 and sys.argv[1] == "assemble"
    notarizing = len(sys.argv) == 4 and sys.argv[1] == "notarize"
    if not checking and not assembling and not notarizing:
        print("Usage: release-staging.py check ABSOLUTE_OUTPUT_DIR\n"
              "       release-staging.py assemble ABSOLUTE_OUTPUT_DIR ROOT BIN debug|release\n"
              "       release-staging.py notarize ABSOLUTE_OUTPUT_DIR ROOT", file=sys.stderr)
        return 2
    try:
        if assembling:
            return assemble(*sys.argv[2:])
        if notarizing:
            return notarize(*sys.argv[2:])
        print(stage_output(sys.argv[2]))
    except (OSError, ValueError, RuntimeError) as error:
        print(f"✗ unsafe or unavailable staging destination: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
