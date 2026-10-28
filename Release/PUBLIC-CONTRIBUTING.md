# Contributing

This repository contains the MIT-licensed FleetConsole source, including the native app, daemon, CLI and Rust protocol. Submit focused fixes, tests and documentation through pull requests.

Use macOS 14 or later with Swift 6 and the macOS SDK. Run:

```sh
swift build -c release --disable-index-store -Xswiftc -disable-cmo
swift test --disable-index-store
cargo test --manifest-path rust/Cargo.toml --workspace --locked
```

Add regression coverage for behavior changes. Preserve ownership checks, process-identity checks, lease semantics and socket permissions. Do not start, stop or reinstall another person's controller for a test; source-core tests use isolated fixtures. Keep `rust/Cargo.lock` committed. Include the exact commands and results in your pull request.

Never commit credentials, service databases, hostnames, unredacted logs or private process arguments. Use synthetic identities in fixtures. Report vulnerabilities through [SECURITY.md](SECURITY.md). Contributions are offered under [MIT](LICENSE); retain copyright and dependency notices.
