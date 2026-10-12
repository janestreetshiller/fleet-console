# Security reporting

Use [GitHub private vulnerability reporting](https://github.com/janestreetshiller/fleet-console-core/security/advisories/new). If the form is unavailable, open an issue requesting a private contact without including exploit details or personal data.

Include the affected release/commit, macOS version and a minimal reproduction with synthetic data. Do not post credentials, process environments, signing material or unredacted logs. No response-time guarantee or long-term-support branch is advertised.

FleetConsole supervises processes as the logged-in user. It is not a sandbox for untrusted commands. Its controller listens on a user-owned Unix socket and preserves the distinction between controller-launched and claimed processes. Read [the threat model](docs/THREAT-MODEL.md) before changing ownership or signal checks.
