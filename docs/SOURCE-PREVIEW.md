# Controlled source preview

FleetConsole's current source carries the MIT license. For this preview, semi-open
means controlled reviewer access through the existing private repository plus a
reviewed source snapshot. The MIT license continues to grant its stated rights.
Repository visibility, a public announcement and binary distribution are separate
maintainer actions.

## Share the snapshot

Use the committed review revision to create a fresh `git archive` source package.
That package contains the source, tests, documentation, resources, dependency
lockfiles and license notices. Its publication set uses `.gitattributes` to omit
machine-local agent instruction adapters. The package starts with the reviewed
current tree, while the private repository retains its existing history and work.
A release privacy check reviews the authored identifiers; secret scans review both
that snapshot and reachable history. Retain the author copyright and intentional
repository/provider URLs.

Run the build and test commands in [the release guide](RELEASE.md) against the
exact revision. Keep runtime screenshots and raw benchmark receipts local because
they contain real host/process information; the assessment reports sanitized
measurements. Review public captures from the deterministic renderer individually.

## Reviewer workflow

Read [the README](../README.md), run the Swift and Rust checks, and stage an app
with a fresh output directory. Local monitoring and controller tools are free;
optional multi-device access uses Ouros. Local app builds use ad-hoc signatures.
A shared macOS download follows the Developer ID and Apple ticket checks in the
release guide, using the maintainer's existing credentials.

Agent clients launch managed services through `fleetctl`, with an owner, purpose
and lease. They read `list`, `show`, `logs`, `events` and `doctor` before acting.
Renew a needed lease or stop a launched service when its work ends. A claimed
process gets ownership records and visibility; signalling authority stays limited
to controller-launched services. The daemon checks process identity before acting.
