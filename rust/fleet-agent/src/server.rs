//! MCP stdio server for the fleet-agent surface.
//!
//! Forked from the rx MCP procedure: newline-delimited JSON-RPC 2.0 over
//! stdio, byte-stable `tools/list`, fail-closed `tools/call` with the error
//! naming the socket, and zero records written for rejected or unavailable
//! calls. The schema hash is pinned in `tools::SCHEMA_SHA256` and asserted by
//! the crate's own tests.

use crate::tools::{self, Dispatcher};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

pub const JSONRPC_VERSION: &str = "2.0";
pub const PROTOCOL_VERSION: &str = "2024-11-05";

pub struct Server<'a> {
    dispatcher: Dispatcher<'a>,
}

impl<'a> Server<'a> {
    pub fn new(dispatcher: Dispatcher<'a>) -> Self {
        Self { dispatcher }
    }

    /// Serve newline-delimited JSON-RPC on the given reader/writer until EOF.
    pub fn serve(&mut self, mut reader: impl BufRead, mut writer: impl Write) -> io::Result<()> {
        let mut line = String::new();
        loop {
            line.clear();
            let n = std::io::Read::take(&mut reader, (crate::guard::MAX_REQUEST_BYTES + 1) as u64).read_line(&mut line)?;
            if n > crate::guard::MAX_REQUEST_BYTES {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "MCP request exceeds byte limit"));
            }
            if n == 0 {
                return Ok(());
            }
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let request: Value = match serde_json::from_str(trimmed) {
                Ok(value) => value,
                Err(_) => {
                    let response = error_response(Value::Null, -32700, "parse error");
                    writeln_with(&mut writer, &response)?;
                    continue;
                }
            };
            let id = request.get("id").cloned().unwrap_or(Value::Null);
            let method = request.get("method").and_then(|m| m.as_str()).unwrap_or("");
            let params = request.get("params").cloned().unwrap_or(json!({}));
            let response = match method {
                "initialize" => result_response(
                    id,
                    json!({
                        "protocolVersion": PROTOCOL_VERSION,
                        "capabilities": { "tools": {} },
                        "serverInfo": { "name": "fleet-agent", "version": env!("CARGO_PKG_VERSION") },
                    }),
                ),
                "notifications/initialized" | "initialized" => continue, // notification: no reply
                "ping" => result_response(id, json!({})),
                "tools/list" => {
                    let tools: Value =
                        serde_json::from_str(&tools::tools_list_payload()).unwrap_or(json!([]));
                    result_response(id, json!({ "tools": tools["tools"].clone() }))
                }
                "tools/call" => {
                    let name = params
                        .get("name")
                        .and_then(|n| n.as_str())
                        .unwrap_or("");
                    let arguments = params.get("arguments").cloned().unwrap_or(json!({}));
                    match self.dispatcher.call(name, &arguments) {
                        Ok(result) => result_response(
                            id,
                            json!({
                                "content": [{ "type": "text", "text": tools::canonical(&result) }],
                            }),
                        ),
                        Err(error) => {
                            // Tool errors are *results* in MCP, not protocol
                            // errors: the host sees isError and the model
                            // reads the reason.
                            result_response(
                                id,
                                json!({
                                    "content": [{ "type": "text", "text": format!("error: {error}") }],
                                    "isError": true,
                                }),
                            )
                        }
                    }
                }
                _ => error_response(id, -32601, "method not found"),
            };
            writeln_with(&mut writer, &response)?;
        }
    }
}

fn writeln_with(writer: &mut impl Write, response: &Value) -> io::Result<()> {
    let bytes = serde_json::to_string(response).expect("response serializes");
    writer.write_all(bytes.as_bytes())?;
    writer.write_all(b"\n")?;
    writer.flush()
}

fn result_response(id: Value, result: Value) -> Value {
    json!({ "jsonrpc": JSONRPC_VERSION, "id": id, "result": result })
}

fn error_response(id: Value, code: i64, message: &str) -> Value {
    json!({ "jsonrpc": JSONRPC_VERSION, "id": id, "error": { "code": code, "message": message } })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn dispatch_with_no_daemon() -> Dispatcher<'static> {
        // A leaked empty box satisfies the 'static borrow without unsafe.
        let none: &'static mut Option<fleet_proto::Client> =
            Box::leak(Box::new(None::<fleet_proto::Client>));
        Dispatcher { client: none, socket_path: Default::default() }
    }

    #[test]
    fn initialize_and_tools_list_over_stdio() {
        let requests = concat!(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}\n",
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}\n",
        );
        let mut server = Server::new(dispatch_with_no_daemon());
        let mut out = Vec::new();
        server.serve(Cursor::new(requests.as_bytes()), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 2);
        let init: Value = serde_json::from_str(lines[0]).unwrap();
        assert_eq!(init["result"]["serverInfo"]["name"], "fleet-agent");
        let list: Value = serde_json::from_str(lines[1]).unwrap();
        let tools = list["result"]["tools"].as_array().unwrap();
        assert_eq!(tools.len(), tools::tool_names().len());
        // Byte-stable: the embedded list matches the pinned payload.
        let payload = tools::tools_list_payload();
        assert!(serde_json::from_str::<Value>(&payload).is_ok());
    }

    #[test]
    fn unknown_method_is_code_32601() {
        let requests = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"nope\",\"params\":{}}\n";
        let mut server = Server::new(dispatch_with_no_daemon());
        let mut out = Vec::new();
        server.serve(Cursor::new(requests.as_bytes()), &mut out).unwrap();
        let response: Value = serde_json::from_str(String::from_utf8(out).unwrap().trim()).unwrap();
        assert_eq!(response["error"]["code"], -32601);
    }

    #[test]
    fn notifications_get_no_reply() {
        let requests = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n";
        let mut server = Server::new(dispatch_with_no_daemon());
        let mut out = Vec::new();
        server.serve(Cursor::new(requests.as_bytes()), &mut out).unwrap();
        assert!(out.is_empty(), "notification must not produce a reply");
    }

    #[test]
    fn call_over_missing_daemon_returns_is_error_with_reason() {
        let requests =
            "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"fleet_ps\",\"arguments\":{}}}\n";
        let none: &'static mut Option<fleet_proto::Client> =
            Box::leak(Box::new(None::<fleet_proto::Client>));
        let mut server = Server::new(Dispatcher {
            client: none,
            socket_path: std::path::PathBuf::from("/missing/fleetd.sock"),
        });
        let mut out = Vec::new();
        server.serve(Cursor::new(requests.as_bytes()), &mut out).unwrap();
        let response: Value = serde_json::from_str(String::from_utf8(out).unwrap().trim()).unwrap();
        assert_eq!(response["result"]["isError"], true);
        assert!(response["result"]["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("not reachable"));
    }
}
