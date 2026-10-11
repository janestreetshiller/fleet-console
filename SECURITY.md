# Report a security vulnerability

Report security issues privately before opening a public issue or pull request. FleetConsole can supervise local processes and inspect system state, so reports may contain sensitive commands, paths, or network details.

## Use a private report

Use [GitHub's private vulnerability reporting](https://github.com/janestreetshiller/fleet-console/security/advisories/new) if the repository has enabled it. If the private form is unavailable, open an issue asking for a private reporting channel without including vulnerability details, exploit code, or private data. No separate security email or guaranteed response time is advertised.

Include these details in the private report:

- The affected version or commit and macOS version
- The expected behavior and the observed security impact
- Reproduction steps using synthetic data where possible
- The affected component: app, `fleetd`, `fleetctl`, or Rust protocol
- Whether a workaround exists

Do not attach real credentials, process environment dumps, signing keys, or unredacted runtime logs. Coordinate disclosure with the maintainer before publishing an exploit.

## Understand the security boundary

FleetConsole is a local process-management tool, not a sandbox for untrusted commands. A process launched through `fleetctl` runs with the launching user's permissions. The daemon uses a user-owned Unix socket; it does not require a privileged helper or a public network listener.

Local process arguments, service records, network observations, agent usage files, terminal sessions, and screenshots can expose personal information. Treat exported diagnostics as private until you review them. Optional external tools and services have their own security boundaries.

## Check support status

The project has no long-term-support branches or promised security response window. Report problems against the current source or latest published release, and include the exact revision. A source license, successful build, or ad-hoc signature does not establish that a downloadable app passed Apple's notarization checks.
