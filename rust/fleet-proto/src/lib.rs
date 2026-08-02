//! The FleetConsole controller protocol, in Rust.
//!
//! This is the seam the port runs through. `FleetConsole.app` has always been a
//! client — it speaks newline-delimited JSON over a `0600` Unix socket and never
//! signals a process itself — so a Rust daemon can replace the Swift one without
//! the GUI knowing, and a Rust TUI can be a second client of the same socket.
//! That only holds if both sides agree on the bytes, which is what
//! `fleet-conformance` exists to prove against the running daemon.
//!
//! Two details are load-bearing and easy to get wrong:
//!
//! * **Dates are epoch seconds**, because Swift's `Codec` pins
//!   `dateEncodingStrategy = .secondsSince1970`. They are `f64` here, not a
//!   date type, so nothing can quietly reinterpret them.
//! * **Absent is not null.** Swift decodes a missing key into `nil`, but a
//!   present `null` is also valid; we skip serializing `None` so requests look
//!   exactly like the ones the Swift client sends.

use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

/// Operations the controller accepts. The wire values are Swift enum raw values,
/// which are the case names verbatim — so `refreshDevices`, not `refresh_devices`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RpcOp {
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "snapshot")]
    Snapshot,
    #[serde(rename = "subscribe")]
    Subscribe,
    #[serde(rename = "launch")]
    Launch,
    #[serde(rename = "renew")]
    Renew,
    #[serde(rename = "stop")]
    Stop,
    #[serde(rename = "restart")]
    Restart,
    #[serde(rename = "events")]
    Events,
    #[serde(rename = "logs")]
    Logs,
    #[serde(rename = "claim")]
    Claim,
    #[serde(rename = "reconcile")]
    Reconcile,
    #[serde(rename = "refreshDevices")]
    RefreshDevices,
    #[serde(rename = "reloadConfig")]
    ReloadConfig,
    #[serde(rename = "ignoreCommand")]
    IgnoreCommand,
    #[serde(rename = "prune")]
    Prune,
    #[serde(rename = "pause")]
    Pause,
    #[serde(rename = "resume")]
    Resume,
    #[serde(rename = "kill")]
    Kill,
    #[serde(rename = "postMessage")]
    PostMessage,
    #[serde(rename = "messages")]
    Messages,
    #[serde(rename = "reply")]
    Reply,
    #[serde(rename = "markSeen")]
    MarkSeen,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RpcRequest {
    pub op: RpcOp,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub launch: Option<serde_json::Value>,
    #[serde(rename = "serviceID", skip_serializing_if = "Option::is_none")]
    pub service_id: Option<String>,
    #[serde(rename = "ttlSec", skip_serializing_if = "Option::is_none")]
    pub ttl_sec: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stream: Option<String>,
    #[serde(rename = "maxBytes", skip_serializing_if = "Option::is_none")]
    pub max_bytes: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(rename = "unmanagedID", skip_serializing_if = "Option::is_none")]
    pub unmanaged_id: Option<String>,
    #[serde(rename = "friendlyName", skip_serializing_if = "Option::is_none")]
    pub friendly_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(rename = "needsReply", skip_serializing_if = "Option::is_none")]
    pub needs_reply: Option<bool>,
    #[serde(rename = "messageID", skip_serializing_if = "Option::is_none")]
    pub message_id: Option<i64>,
    #[serde(rename = "unansweredOnly", skip_serializing_if = "Option::is_none")]
    pub unanswered_only: Option<bool>,
}

impl Default for RpcOp {
    fn default() -> Self {
        RpcOp::Ping
    }
}

impl RpcRequest {
    pub fn new(op: RpcOp) -> Self {
        Self { op, ..Default::default() }
    }
}

/// The controller's identity and liveness. Modelled fully because it is the
/// smallest complete thing both implementations must agree on.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonInfo {
    pub version: String,
    pub pid: i32,
    /// Epoch seconds.
    #[serde(rename = "startedAt")]
    pub started_at: f64,
    #[serde(rename = "lastTickAt", default, skip_serializing_if = "Option::is_none")]
    pub last_tick_at: Option<f64>,
    #[serde(rename = "lastReconcileAt", default, skip_serializing_if = "Option::is_none")]
    pub last_reconcile_at: Option<f64>,
    #[serde(rename = "tickIntervalSec")]
    pub tick_interval_sec: f64,
    #[serde(rename = "socketPath", default)]
    pub socket_path: String,
}

/// The reply envelope.
///
/// `snapshot`, `service` and `events` stay `serde_json::Value` deliberately.
/// Porting the registry model is the large half of this work, and a half-modelled
/// `ServiceRecord` that silently drops fields would be worse than an honest
/// opaque one. They get real types as each subsystem is ported.
#[derive(Debug, Clone, Deserialize)]
pub struct RpcResponse {
    pub ok: bool,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub snapshot: Option<serde_json::Value>,
    #[serde(default)]
    pub service: Option<serde_json::Value>,
    #[serde(default)]
    pub events: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub logs: Option<serde_json::Value>,
    #[serde(default)]
    pub daemon: Option<DaemonInfo>,
    #[serde(default)]
    pub messages: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub message: Option<serde_json::Value>,
}

#[derive(Debug)]
pub enum ClientError {
    Io(std::io::Error),
    Decode(serde_json::Error),
    Closed,
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::Io(e) => write!(f, "io error: {e}"),
            ClientError::Decode(e) => write!(f, "decode error: {e}"),
            ClientError::Closed => write!(f, "controller closed the connection"),
        }
    }
}

impl std::error::Error for ClientError {}

/// Where the controller listens. Mirrors `FleetPaths.socket`.
pub fn default_socket_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home)
        .join("Library/Application Support/FleetConsole")
        .join("fleetd.sock")
}

/// A blocking client for one request/response exchange.
///
/// Blocking on purpose: every operation here is a single round trip against a
/// local socket, and an async runtime would be machinery without a job. The
/// `subscribe` op is the exception and is not modelled yet.
pub struct Client {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
}

impl Client {
    pub fn connect(path: &std::path::Path) -> Result<Self, ClientError> {
        let stream = UnixStream::connect(path).map_err(ClientError::Io)?;
        stream
            .set_read_timeout(Some(Duration::from_secs(15)))
            .map_err(ClientError::Io)?;
        let writer = stream.try_clone().map_err(ClientError::Io)?;
        Ok(Self { reader: BufReader::new(stream), writer })
    }

    pub fn send(&mut self, request: &RpcRequest) -> Result<RpcResponse, ClientError> {
        let mut line = serde_json::to_vec(request).map_err(ClientError::Decode)?;
        line.push(b'\n');
        self.writer.write_all(&line).map_err(ClientError::Io)?;
        self.writer.flush().map_err(ClientError::Io)?;

        let mut buffer = String::new();
        let read = self.reader.read_line(&mut buffer).map_err(ClientError::Io)?;
        if read == 0 {
            return Err(ClientError::Closed);
        }
        serde_json::from_str(&buffer).map_err(ClientError::Decode)
    }

    /// The exact bytes we would put on the wire, for tests that assert shape
    /// rather than behaviour.
    pub fn encode(request: &RpcRequest) -> String {
        serde_json::to_string(request).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn omits_absent_fields() {
        // The Swift client sends only `op` for a ping. Emitting explicit nulls
        // would still decode, but it would make the two implementations
        // distinguishable on the wire, which defeats the point.
        let encoded = Client::encode(&RpcRequest::new(RpcOp::Ping));
        assert_eq!(encoded, r#"{"op":"ping"}"#);
    }

    #[test]
    fn uses_swift_case_names() {
        let encoded = Client::encode(&RpcRequest::new(RpcOp::RefreshDevices));
        assert!(encoded.contains(r#""op":"refreshDevices""#), "got {encoded}");
    }

    #[test]
    fn service_id_keeps_swift_spelling() {
        let mut request = RpcRequest::new(RpcOp::Stop);
        request.service_id = Some("abc".into());
        assert!(Client::encode(&request).contains(r#""serviceID":"abc""#));
    }
}
