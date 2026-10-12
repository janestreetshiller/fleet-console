# Public source boundary

FleetConsole uses a freemium distribution model: local monitoring and service management are free, with optional Ouros multi-device access at $10 USD/month from Ouros AI, LLC.

The public repository is https://github.com/janestreetshiller/fleet-console-core. Its MIT source snapshot includes:

- `Sources/FleetCore`: shared models, storage, socket protocol and safety rules.
- `Sources/fleetd`: the local controller.
- `Sources/fleetctl`: the CLI.
- `Tests/FleetCoreTests`: regression coverage for the shared core.
- `rust/fleet-proto` and `rust/fleet-conformance`: protocol models and live read-only checks.
- A standalone Swift package manifest, Rust lockfile, focused documentation and CI.

The native desktop UI source, SwiftTerm integration, private development history, local instruction adapters, signing material, runtime state and privately supplied soundtrack are not published. A new Git repository contains only the allowlisted committed snapshot; it does not import the private repository's history or remotes. The public package builds the daemon and CLI without fetching SwiftTerm or referring to the private app target.

The free macOS app download is published alongside the core source only after Developer ID signing, Apple acceptance, stapled-ticket validation and extracted-archive checks. The bundled MIT and SwiftTerm notices remain intact. Source availability and payment terms are separate: MIT rights for the published code do not depend on a subscription.

Use `Scripts/export-public-source.py <fresh-directory> [revision]` from the private release tree. Run `Scripts/test-public-source.py`, inspect the exported manifest, scan the actual export for secrets, and run its own Swift/Rust checks before pushing. Keep runtime receipts private. Public marketing captures must use the current native views, reviewed demo data and explicit fixture provenance.

Agent clients launch through `fleetctl`, with an owner, purpose and lease. Read before acting, renew what is needed, and stop launched work when it ends. Claims add visibility without signalling authority. Paused services retain their resources and postpone expiry cleanup until resumed.
