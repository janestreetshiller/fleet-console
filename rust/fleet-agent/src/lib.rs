//! fleet-agent: the FleetConsole resident operations agent.
//!
//! An rx-basis component specialized for console residency: typed tools over
//! the fleetd socket (never raw shell), a memory/process specialist system
//! prompt, a local-LLM engine loop, an MCP stdio server so hosts can drive
//! the same surface, and metered usage signed to a local ledger that Ouros
//! reads to bill.

pub mod engine;
pub mod guard;
pub mod http;
pub mod knowledge;
pub mod meter;
pub mod server;
pub mod tools;

use serde_json::Value;
use std::path::PathBuf;

/// Mirrors `FleetPaths.support`.
pub fn support_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("Library/Application Support/FleetConsole")
}

pub fn default_socket_path() -> PathBuf {
    support_dir().join("fleetd.sock")
}

/// Where meter records land. `agent-billing/` under the support directory, so
/// the Ouros bar finds it next to the registry and socket it already reads.
pub fn default_ledger_path() -> PathBuf {
    support_dir().join("agent-billing").join("meter-ledger.txt")
}

/// Open the controller connection once; `None` means fail-closed.
pub fn connect_controller(socket: &std::path::Path) -> Option<fleet_proto::Client> {
    fleet_proto::Client::connect(socket).ok()
}

pub fn json_pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}
