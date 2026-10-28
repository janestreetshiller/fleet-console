# Core development

The public Swift package contains FleetCore, fleetd, fleetctl and their core tests. It does not build the native UI or require SwiftTerm.

Use macOS 14 or later, Swift 6 with the macOS SDK, and Rust 1.80 or later. Run the commands in the README. `swift build -c release --show-bin-path` locates the release executables.

`fleetd` normally runs as the logged-in user's LaunchAgent and stores its owner-only socket, configuration and SQLite registry in `~/Library/Application Support/FleetConsole`. The downloadable app contains its helper-registration flow. Building source tools does not register that helper.

For a foreground source-controller check, first confirm no existing FleetConsole controller is serving your user. Running a second controller against the same paths is not an isolated test. If no controller is running, execute the built `fleetd` in a foreground terminal and query it with the built `fleetctl ping` and `fleetctl doctor`; stop only the foreground process you started when finished. Use the core test suite for repeatable isolated checks.

The Rust `fleet-conformance` program makes read-only ping, snapshot, events and invalid-request round trips against the local controller:

```sh
cargo run --manifest-path rust/Cargo.toml -p fleet-conformance --locked
```

Run that only against a controller you are authorized to observe. It never launches or signals a service. Do not expose the Unix socket over a public TCP listener. Keep raw diagnostics private until reviewed.
