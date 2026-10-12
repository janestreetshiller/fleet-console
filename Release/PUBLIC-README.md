# FleetConsole

A free macOS menu-bar app for monitoring your Mac and keeping background agent work accountable.

[Download FleetConsole](https://github.com/janestreetshiller/fleet-console-core/releases/latest)

Requires macOS 14 or later. The downloadable build is for Apple Silicon (arm64).

## The app

Quick View has four instruments: CPU and memory dials, a disk-capacity map, and upload/download bars. Services, Agents, Processes and Network share the same compact menu frame. Name and color-tag services, register agent IDs, handle pending requests, or open the dashboard for charts and logs. The dashboard's sidebar tucks away when you want more room.

Local monitoring and service management are free. Optional multi-device access costs $10 USD/month through Ouros, using your existing SSH setup for remote metrics and read-only service inventory. It does not include AI credits or automatic repairs. Signing and Apple ticket details for each downloadable build appear in its release notes.

## What's open source

This repository publishes FleetCore, fleetd, fleetctl, their core tests and the Rust protocol/conformance workspace under [MIT](LICENSE). The native desktop UI source, hosted billing infrastructure, private development history and unreleased media are not included. The public Swift package builds independently without SwiftTerm or the private app target. MIT rights for this source do not depend on a subscription.

## Build the core and tools

Use macOS 14 or later and a Swift 6 toolchain with the macOS SDK. The core, daemon and CLI have no external Swift package dependencies; FleetCore links the system SQLite library.

```sh
swift build -c release --disable-index-store -Xswiftc -disable-cmo
swift test --disable-index-store
cargo test --manifest-path rust/Cargo.toml --workspace --locked
```

The Rust workspace requires Rust 1.80 or later and fetches the dependencies pinned in `rust/Cargo.lock`. Find the tools with `swift build -c release --show-bin-path`. Building does not install or restart a controller.

## Install the downloadable app

Download the ZIP and its checksum from Releases. Verify the checksum, extract the archive and move FleetConsole.app to Applications. Open the app and approve its FleetConsole background item when macOS requests it; the controller runs as your user, without root or a public listener. Do not replace a running app/controller; quit it before updating. The app's **Edit Configuration** action opens its local settings. The CLI is bundled at:

```text
/Applications/FleetConsole.app/Contents/Resources/bin/fleetctl
```

`fleetctl doctor` checks controller connectivity and local state. Advanced source-tool installation and foreground daemon testing are described in [core development](docs/CORE-DEVELOPMENT.md).

## Give agent work an owner and a lease

```sh
fleetctl launch --name "Local API" --owner codex \
  --purpose "API for the current task" --cwd "$PWD" \
  --lease 30m -- python3 -m http.server 8787
fleetctl list
fleetctl renew "Local API" --lease 30m
fleetctl stop "Local API"
```

The controller records owner, purpose, lease and logs. It cleans up unpaused services it launched when unrenewed leases expire. Paused services keep their process groups and resources until resumed. Claimed processes get ownership records and visibility, not signalling authority. The controller verifies process identity before signalling.

See [CLI reference](docs/CLI.md), [threat model](docs/THREAT-MODEL.md), [contribution guide](CONTRIBUTING.md), and [security reporting](SECURITY.md). Registry/configuration live in `~/Library/Application Support/FleetConsole`; logs live in `~/Library/Logs/FleetConsole`. Review diagnostics before sharing them.
