# Public source boundary

FleetConsole uses a freemium distribution model: local monitoring and service management are free, with optional Ouros multi-device access at $10 USD/month from Ouros AI, LLC.

The public repository is https://github.com/janestreetshiller/fleet-console. Its MIT source includes:

- `Sources/FleetConsoleApp`: the native menu-bar and dashboard app (SwiftUI + SwiftTerm).
- `Sources/FleetCore`: shared models, storage, socket protocol and safety rules.
- `Sources/fleetd`: the local controller.
- `Sources/fleetctl`: the CLI.
- `Tests/`: regression coverage for the core and the app surfaces.
- `rust/fleet-proto` and `rust/fleet-conformance`: protocol models and live read-only checks.

Signing material, runtime state, marketing media and privately supplied recordings are not published. The package fetches SwiftTerm for the app target and nothing else.

The free macOS app download is published alongside the source only after Developer ID signing, Apple acceptance, stapled-ticket validation and extracted-archive checks. The bundled MIT and SwiftTerm notices remain intact. Source availability and payment terms are separate: MIT rights for the published code do not depend on a subscription.

Use `Scripts/export-public-source.py <fresh-directory> [revision]` from a release checkout. Run `Scripts/test-public-source.py`, inspect the exported manifest, scan the actual export for secrets, and run its own Swift/Rust checks before pushing. Keep runtime receipts private. Public marketing captures must use the current native views, reviewed demo data and explicit fixture provenance.

The prepared macOS download carries a Developer ID signature, Apple's accepted notarization and a validated stapled ticket; the extracted archive also passes Gatekeeper and deep strict signature checks. Local development builds can use ad-hoc signatures; follow the release guide with the maintainer's existing credentials for subsequent candidates.

Agent clients launch through `fleetctl`, with an owner, purpose and lease. Read before acting, renew what is needed, and stop launched work when it ends. Claims add visibility without signalling authority. Paused services retain their resources and postpone expiry cleanup until resumed.
