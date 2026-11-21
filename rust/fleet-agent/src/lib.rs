
pub mod engine;
pub mod guard;
pub mod http;
pub mod knowledge;
pub mod meter;
pub mod server;
pub mod tools;

use serde_json::Value;
use std::path::PathBuf;

pub fn support_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("Library/Application Support/FleetConsole")
}

pub fn default_socket_path() -> PathBuf {
    support_dir().join("fleetd.sock")
}

pub fn default_ledger_path() -> PathBuf {
    support_dir().join("agent-billing").join("meter-ledger.txt")
}

pub fn connect_controller(socket: &std::path::Path) -> Option<fleet_proto::Client> {
    fleet_proto::Client::connect(socket).ok()
}

pub fn json_pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}
