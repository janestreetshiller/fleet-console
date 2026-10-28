# Contribute to FleetConsole

Contribute fixes, tests, documentation, and measured performance improvements through pull requests. FleetConsole runs on macOS 14 or later and uses Swift 6; its Rust workspace models the controller protocol.

## Build and test your change

Install an Xcode toolchain with Swift 6 and the macOS SDK. Use Rust 1.80 or later for changes under `rust/`. Keep `Package.resolved` and `rust/Cargo.lock` committed so dependency changes remain reviewable.

Run the Swift checks from the repository root:

```bash
swift build --disable-index-store
swift test --disable-index-store
```

For release-sensitive changes, also exercise the existing compiler workaround:

```bash
swift build -c release --disable-index-store -Xswiftc -disable-cmo
```

Check the Rust workspace without connecting to a daemon:

```bash
cargo check --manifest-path rust/Cargo.toml --workspace --all-targets --locked
```

Run shell syntax checks when you change a script:

```bash
for script in Scripts/*.sh; do bash -n "$script"; done
```

The [CI workflow](.github/workflows/ci.yml) builds, tests, and checks scripts. It does not sign, notarize, install, publish, or start a controller. `fleet-conformance` needs a running daemon; do not run it against another person's fleet without permission.

## Keep runtime costs bounded

Preserve the separation between `FleetCore`, `fleetd`, `fleetctl`, and the app. SwiftTerm belongs only to the app target. Discuss new dependencies before introducing them.

For performance changes, report the workload, toolchain, hardware, elapsed time, and before/after measurements. Check idle CPU, polling frequency, allocation growth, and UI responsiveness where relevant. Prefer bounded sampling and existing caches over additional background workers.

## Protect local data and running work

Use synthetic fixtures in tests and screenshots. Remove account names, home paths, hostnames, tailnet identifiers, real IP addresses, process arguments, and credentials before sharing diagnostics. Never commit signing keys, notarization credentials, runtime databases, or logs.

Building an app bundle is separate from installing it. Use a fresh `FLEETCONSOLE_OUTPUT_DIR` for packaging, and never replace binaries in a running bundle. The build script does not stop or restart the daemon. See [release instructions](docs/RELEASE.md) for staged builds.

For interface changes, include captures of the affected states and describe keyboard or layout checks. `Scripts/surface-sheet.sh` renders shipping views, but some probes still read your machine's state; review captures before uploading them.

## Submit a focused pull request

Include these details:

- The problem and the behavior you changed
- Relevant tests and their actual results
- Performance measurements for runtime changes
- Screenshots for interface changes, with private data removed
- Any compatibility changes or remaining limitations

Add regression coverage for behavior changes. Keep unrelated refactors out of the patch. Report vulnerabilities privately using [the security policy](SECURITY.md), not a public issue.

## Preserve license notices

Your contributions are offered under the repository's [MIT license](LICENSE). Keep existing copyright and third-party notices intact. SwiftTerm retains its own MIT notices; the packaging script includes its upstream license with the app. Do not assume the repository license replaces dependency licenses.
