# Prepare a FleetConsole release

Use this checklist to publish reviewed MIT source or stage a macOS app without changing an installed controller. Source publication, binary distribution, and installation are separate actions; a build does not complete the other steps.

## Review source before making it public

Audit the complete publish set, including Git history if you intend to publish it. A private repository is a staging area, not evidence that its contents are safe to disclose.

Check these inputs:

- Tracked files, intended new files, and the final diff
- Reachable Git history, including files deleted from the current tree
- Home paths, hostnames, tailnet addresses, signing-team identifiers, and account details in docs or fixtures
- API tokens, passwords, private keys, notarization credentials, runtime databases, and logs
- Screenshot and archive contents, including incidental machine data
- Authored MIT coverage and the separate licenses of dependencies

Run the working-tree checks and, when Gitleaks is available, a redacted history scan:

```bash
git status --short
git diff --check
gitleaks git . --log-opts='--all' --redact --ignore-gitleaks-allow
```

Scan the intended working-tree files separately; a history scan does not include uncommitted additions. Keep scan reports outside the publish tree, redact findings, and review each match. A scanner match in an invalid-key test is not proof of a credential leak, and a clean scan is not a complete privacy review.

Review these existing risk paths before publishing:

- `docs/PRODUCT-SPEC.md`: machine-of-record and network identifiers
- `Sources/FleetCore/Tailscale.swift`: a hostname/tailnet example in a comment
- `Sources/FleetConsoleApp/SurfaceRenderer.swift`: home paths and network fixtures, plus probes that can capture live state
- `Sources/FleetConsoleApp/Views/TaskComposer.swift`: machine-specific home defaults
- `Scripts/notarize.sh`: a signing-team example and assumptions about credential profiles
- `Sources/FleetCore/License.swift` and `Tests/FleetCoreTests/LicenseTests.swift`: historical license-key scaffolding and synthetic keys
- `AGENTS.md` and `docs/AGENTS.md`: local policy links; don't assume they work on a contributor's machine

Removing data from the current tree does not remove it from history. If history contains private data, use a maintainer-approved cleanup or publish a fresh reviewed source snapshot. Rotate actual exposed credentials before publication. Do not force-push or discard unrelated work as part of an audit.

## Verify the release revision

Use macOS 14 or later, a Swift 6 toolchain with the macOS SDK, a current stable Rust toolchain (this release uses Rust 1.99.1), and Python 3.9 or later for staging and script checks. Run these checks on the exact source revision you plan to publish:

```bash
for script in Scripts/*.sh; do bash -n "$script"; done
python3 Scripts/test-release-policy.py
PYTHONOPTIMIZE=1 python3 Scripts/test-release-policy.py
python3 Scripts/test-notary-staging.py
PYTHONOPTIMIZE=1 python3 Scripts/test-notary-staging.py
python3 Scripts/test-source-privacy.py
PYTHONOPTIMIZE=1 python3 Scripts/test-source-privacy.py
swift build -c release --disable-index-store -Xswiftc -disable-cmo
swift test --disable-index-store
cargo check --manifest-path rust/Cargo.toml --workspace --all-targets --locked
```

The [CI workflow](../.github/workflows/ci.yml) runs these checks on macOS. Require a successful run before publication; it does not package, sign, notarize, install, publish, or start a daemon. Run live Rust conformance only against a controller you are authorized to observe.

The script regressions use labelled test data and mock build/signing tools in `TMPDIR`; they do not produce a native app or valid signatures. They exercise the production staging and benchmark gates, including Applications aliases, existing/running targets, signing failures, and invalid receipts/budgets with Python optimization enabled. Set `TMPDIR` to an existing scratch directory before running them.

For a focused live Quick View check, build the renderer with the existing
release flags and invoke its observational verifier:

```bash
swift build -c release --disable-index-store -Xswiftc -disable-cmo \
  -Xswiftc -DFLEET_SURFACE_RENDERER
bin="$(swift build -c release --disable-index-store -Xswiftc -disable-cmo \
  -Xswiftc -DFLEET_SURFACE_RENDERER --show-bin-path)"
quick="$(mktemp -d "${TMPDIR:-$HOME/Library/Caches}/fleet-quick-view.XXXXXX")"
"$bin/FleetConsoleApp" --verify-live "$quick" 60 --verify-quick-view
```

This checks the shipping popover in an offscreen native window with live data,
records app and reaped-collector CPU separately, and captures both appearances.
Rebuild ordinary production products before packaging.

Keep the `-disable-cmo` workaround until a tested toolchain no longer needs it. Keep the dependency lockfiles. For runtime changes, record before/after workload measurements rather than inferring speed from a release build.

For a binary release, check `CFBundleShortVersionString` and `CFBundleVersion` in `Scripts/assemble-app.sh` before building. Record the source commit, toolchain, architecture, test results, and signing/notarization status in the release notes. Do not label an architecture-specific build as universal.

## Stage a local ad-hoc build

Choose a fresh staging destination that is not an installed app location. Relative `FLEETCONSOLE_OUTPUT_DIR` values resolve from the repository root; the default is `build/`. The script refuses any existing `FleetConsole.app` entry, including files and symlinks, whether or not it is running.

Before creating directories, it checks Applications aliases by ancestor filesystem identity. It then atomically reserves a new bundle without replacement and keeps assembly anchored to that open directory, including stripping, signing, and verification. `Scripts/assemble-app.sh` is an internal worker, not a standalone build entry point; use `Scripts/build-app.sh`. A failed build/signature may leave a partial bundle; choose another fresh stage for the next attempt. The script never stops, unloads, registers, or restarts a controller.

Build with explicit ad-hoc signing to avoid a signing-identity lookup:

```bash
stage="$(mktemp -d "${TMPDIR:-$HOME/Library/Caches}/fleet-release.XXXXXX")"
FLEETCONSOLE_OUTPUT_DIR="$stage" FLEETCONSOLE_IDENTITY=- \
  Scripts/build-app.sh release
app="$stage/FleetConsole.app"
```

The script signs nested code before the app, omits timestamps for ad-hoc signatures, and fails if signing or verification fails. Ad-hoc signing does not provide a publisher identity, notarization, or a Gatekeeper acceptance guarantee. Offer source builds rather than presenting this artifact as a notarized download.

The bundle includes SwiftPM resources and both `Contents/Resources/licenses/FleetConsole-LICENSE.txt` and `SwiftTerm-LICENSE.txt`. Verify those notices before redistributing it. SwiftTerm's upstream license includes its original authors' copyright notices; the repository's [MIT license](../LICENSE) does not replace them.

## Prepare an authorized Developer ID download

Use an existing Developer ID Application identity only when binary distribution is authorized. Set `FLEETCONSOLE_IDENTITY` to its exact installed name or fingerprint and build into a fresh stage:

```bash
stage="$(mktemp -d "${TMPDIR:-$HOME/Library/Caches}/fleet-release.XXXXXX")"
: "${developer_id_identity:?Set an existing Developer ID identity}"
FLEETCONSOLE_OUTPUT_DIR="$stage" \
  FLEETCONSOLE_IDENTITY="$developer_id_identity" \
  Scripts/build-app.sh release
app="$stage/FleetConsole.app"
```

Developer ID builds use hardened runtime and secure timestamps. Do not change executables or bundle contents after signing. Check nested signatures as well as the outer app:

```bash
codesign --verify --strict --verbose=2 "$app/Contents/Resources/bin/fleetd"
codesign --verify --strict --verbose=2 "$app/Contents/Resources/bin/fleetctl"
codesign --verify --deep --strict --verbose=2 "$app"
```

`Scripts/notarize.sh` uses the same `FLEETCONSOLE_OUTPUT_DIR` as the build script and forwards the selected API-key or keychain-profile authentication to submission. It rejects Applications aliases and symlink bundles, opens the staged bundle by filesystem identity, and keeps staple and validation operations relative to that pinned directory. Archive writes target an inherited open file descriptor; submission uses the ZIP name relative to the opened private scratch directory. Creation and cleanup retain those identities across repository, ancestor and scratch-directory replacement. Cleanup preserves replacement entries and removes the owned archive. For an existing authorized `notary_profile`, the staged wrapper is:

```bash
FLEETCONSOLE_OUTPUT_DIR="$stage" FLEETCONSOLE_NOTARY_PROFILE="$notary_profile" \
  Scripts/notarize.sh
```

It submits, staples and validates that artifact; do not create credentials automatically.

When invoking release tools over SSH, check the execution context before drawing
conclusions about keychain availability. `launchctl managername` distinguishes a
Background session from the logged-in Aqua session. The same installed identity
can fail in the former while actual signing succeeds in the latter. Run an
approved, task-specific release script through a background LaunchServices launch
in the existing GUI session, retain its log, and verify the resulting artifact.
Preserve keychain ACLs and protection; credentials remain in their existing store.
Test a configured notary profile against its default store before adding
`--keychain`: explicitly selecting a file-based login keychain can hide credentials
that work through the default data-protection store.

The equivalent explicit submission is:

```bash
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "$app" "$stage/FleetConsole-notarize.zip"
xcrun notarytool submit "$stage/FleetConsole-notarize.zip" \
  --keychain-profile "$notary_profile" --wait
```

Require the submission status `Accepted`, then staple and validate that same app:

```bash
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
```

Archive after stapling so the download preserves the ticket. If any check fails, report the failure and do not call the download notarized. Credentials and notarization are intentionally absent from CI.

## Archive and checksum the reviewed artifact

Use `ditto` rather than a plain ZIP command to preserve bundle metadata. Read the actual bundle version and label the architecture used to build it:

```bash
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app/Contents/Info.plist")"
archive="FleetConsole-$version-macos-$(uname -m).zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
(cd "$stage" && shasum -a 256 "$archive" > "$archive.sha256" \
  && shasum -a 256 -c "$archive.sha256")
```

Upload the archive and its `.sha256` file together only after approval. Test the extracted archive on the intended macOS version and architecture. Checksums detect changed bytes; they do not establish trust in the publisher or replace signing.

For a source archive, use a clean, committed, reviewed release tree. `git archive` includes committed files only, not uncommitted edits or ignored runtime state:

```bash
git archive --format=tar.gz --prefix=FleetConsole/ \
  --output="$stage/FleetConsole-source.tar.gz" HEAD
(cd "$stage" && shasum -a 256 FleetConsole-source.tar.gz \
  > FleetConsole-source.tar.gz.sha256 \
  && shasum -a 256 -c FleetConsole-source.tar.gz.sha256)
```

Confirm the source archive contains `LICENSE`, the contribution/security policies, source, tests, resources, and dependency lockfiles. GitHub-generated source archives omit dependencies; SwiftPM fetches SwiftTerm at the pinned revision, with its own license.

## Keep installation and donations separate

Do not copy over `/Applications/FleetConsole.app` while its controller is running. Install or re-register a controller only during a separately authorized maintenance window. Starting a staged client may connect to the installed daemon; packaging does not start the client.

Donation account configuration is deferred. Add an optional README donation link or `.github/FUNDING.yml` only after the maintainer chooses and verifies an enabled account. Do not invent a donation URL or imply payments are active. Donations must not change the MIT rights or unlock required runtime features.
