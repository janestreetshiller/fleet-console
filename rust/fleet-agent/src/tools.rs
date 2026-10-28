//! The agent's tool surface: typed operations over the fleetd socket.
//!
//! Forked from the rx MCP procedure: byte-stable tool definitions as module
//! literals (no timestamps, counts, paths or host state in a schema), a pinned
//! schema hash, canonical JSON serialization, and fail-closed behavior when
//! the backing daemon is missing. The agent never gets raw shell execution —
//! every capability is a typed RPC against the controller, which is the whole
//! point of the console: agents call the CLI/daemon instead of spawning
//! processes themselves (`docs/RUNBOOKS.md`).

use serde_json::{json, Value};

pub const FLEET_AGENT_ID: &str = "fleet-agent";

/// Pinned SHA-256 of the canonical `tools/list` payload. A host (or test)
/// asserts against this constant; a drifting schema invalidates prompt caches,
/// which is the entire reason it is pinned.
pub const SCHEMA_SHA256: &str = "e03ae4f09b80f4424a5bd35d91cce34d9fe47c4b65df5cbeabe6754a101499a0";

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

/// One tool's schema, as a pre-serialized canonical JSON object literal.
/// Written by hand (not built from structs) so the bytes are stable by
/// construction and reviewable in one place.
struct ToolDef {
    name: &'static str,
    description: &'static str,
    /// Canonical JSON: sorted keys, no whitespace.
    input_schema: &'static str,
}

const TOOLS: &[ToolDef] = &[
    ToolDef {
        name: "fleet_snapshot",
        description: "Full fleet snapshot from the controller: daemon info, supervised services with CPU/memory history, unmanaged processes, devices, attention items, recent events and agent messages. The single best first call — everything else keys off serviceIDs it returns.",
        input_schema: r#"{"properties":{},"required":[],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_ps",
        description: "Compact service listing: id, name, owner agent, state, pid, CPU%, resident MB. Lighter than fleet_snapshot when you only need the roster.",
        input_schema: r#"{"properties":{},"required":[],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_top_memory",
        description: "Services and unmanaged processes ranked by resident memory, with the memory-trend classification (Climbing/Creeping/Oscillating/Steady) for each supervised service. The starting point for any memory question.",
        input_schema: r#"{"properties":{"limit":{"description":"Maximum rows to return (default 10).","type":"integer"}},"required":[],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_mem_advice",
        description: "Specialist memory interpretation for one service or the whole system: classifies the resident-memory trend, explains what the number means, and names the honest next step. Advice only — it never mutates anything.",
        input_schema: r#"{"properties":{"serviceID":{"description":"Optional service id from fleet_snapshot/fleet_ps. Omit for the system-wide pressure verdict.","type":"string"}},"required":[],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_logs",
        description: "Tail a supervised service's captured stdout/stderr from the controller's log store.",
        input_schema: r#"{"properties":{"serviceID":{"type":"string"},"stream":{"description":"\"out\" or \"err\"","type":"string"}},"required":["serviceID"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_events",
        description: "Recent controller events (launches, stops, reaps, breaches), newest first, optionally filtered to one service.",
        input_schema: r#"{"properties":{"limit":{"type":"integer"},"serviceID":{"type":"string"}},"required":[],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_launch",
        description: "Launch a supervised service through the controller. The controller owns the process from then on: lease, budgets, health checks, reaping. Requires confirm=true — an explicit opt-in for the only tool that starts a process.",
        input_schema: r#"{"properties":{"command":{"description":"Argv array, e.g. [\"/usr/bin/python3\",\"server.py\"]","items":{"type":"string"},"type":"array"},"confirm":{"description":"Must be true or the call refuses.","type":"boolean"},"cwd":{"type":"string"},"friendlyName":{"type":"string"},"leaseTTLSeconds":{"type":"number"},"ownerAgent":{"type":"string"},"purpose":{"description":"Why this service is allowed to exist. Recorded on the record.","type":"string"}},"required":["command","cwd","friendlyName","purpose","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_stop",
        description: "Graceful stop (SIGTERM then SIGKILL after grace). The service does not come back on its own. Requires confirm=true and a reason, which is recorded in the append-only event log.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"},"reason":{"type":"string"},"serviceID":{"type":"string"}},"required":["serviceID","reason","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_restart",
        description: "Stop then relaunch the same command under a fresh lease. Requires confirm=true and a reason.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"},"reason":{"type":"string"},"serviceID":{"type":"string"}},"required":["serviceID","reason","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_pause",
        description: "SIGSTOP the process group: the process keeps its ports and memory but stops burning CPU. The reversible first move under memory pressure. Requires confirm=true and a reason.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"},"reason":{"type":"string"},"serviceID":{"type":"string"}},"required":["serviceID","reason","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_resume",
        description: "SIGCONT a paused process group. Requires confirm=true and a reason.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"},"reason":{"type":"string"},"serviceID":{"type":"string"}},"required":["serviceID","reason","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_kill",
        description: "Immediate SIGKILL, no grace period. Last resort. Requires confirm=true and a reason.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"},"reason":{"type":"string"},"serviceID":{"type":"string"}},"required":["serviceID","reason","confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_renew",
        description: "Extend a service's lease so the reaper does not collect it while work is ongoing.",
        input_schema: r#"{"properties":{"serviceID":{"type":"string"},"ttlSeconds":{"type":"number"}},"required":["serviceID","ttlSeconds"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_reconcile",
        description: "Force a controller reconciliation sweep: compare desired state to reality and apply the diff. Requires confirm=true.",
        input_schema: r#"{"properties":{"confirm":{"type":"boolean"}},"required":["confirm"],"type":"object"}"#,
    },
    ToolDef {
        name: "fleet_message",
        description: "Post a message to the operator's console mailbox (e.g. a question that needs a human answer, or a report of action taken).",
        input_schema: r#"{"properties":{"body":{"type":"string"},"kind":{"description":"\"info\" (default), \"question\" or \"report\"","type":"string"},"needsReply":{"type":"boolean"},"subject":{"type":"string"}},"required":["body"],"type":"object"}"#,
    },
];

/// The canonical `tools/list` result: sorted keys, compact separators.
pub fn tools_list_payload() -> String {
    let tools: Vec<Value> = TOOLS
        .iter()
        .map(|t| {
            json!({
                "inputSchema": serde_json::from_str::<Value>(t.input_schema).expect("static schema is valid JSON"),
                "name": t.name,
                "description": t.description,
            })
        })
        .collect();
    let payload = json!({ "tools": tools });
    canonical(&payload)
}

/// Canonical JSON: sorted keys, compact separators — the cache-stable form.
pub fn canonical(value: &Value) -> String {
    // serde_json's Value preserves insertion order; canonicalize by
    // re-serializing through a sorted map walk.
    fn write_canonical(value: &Value, out: &mut String) {
        match value {
            Value::Object(map) => {
                let mut keys: Vec<&String> = map.keys().collect();
                keys.sort();
                out.push('{');
                for (i, key) in keys.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push_str(&serde_json::to_string(key).expect("key"));
                    out.push(':');
                    write_canonical(&map[*key], out);
                }
                out.push('}');
            }
            Value::Array(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_canonical(item, out);
                }
                out.push(']');
            }
            other => out.push_str(&serde_json::to_string(other).expect("scalar")),
        }
    }
    let mut out = String::new();
    write_canonical(value, &mut out);
    out
}

pub fn tool_names() -> Vec<&'static str> {
    TOOLS.iter().map(|t| t.name).collect()
}

pub fn is_known_tool(name: &str) -> bool {
    TOOLS.iter().any(|t| t.name == name)
}

pub const READ_ONLY_TOOLS: &[&str] = &[
    "fleet_snapshot",
    "fleet_ps",
    "fleet_top_memory",
    "fleet_mem_advice",
    "fleet_logs",
    "fleet_events",
];

pub fn is_mutating(name: &str) -> bool {
    !READ_ONLY_TOOLS.contains(&name)
}

// ---------------------------------------------------------------------------
// Dispatch — every tool call becomes exactly one controller RPC.
// ---------------------------------------------------------------------------

pub struct DispatchError(pub String);

impl std::fmt::Display for DispatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::fmt::Debug for DispatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "DispatchError({})", self.0)
    }
}

pub struct Dispatcher<'a> {
    pub client: &'a mut Option<fleet_proto::Client>,
    pub socket_path: std::path::PathBuf,
}

impl<'a> Dispatcher<'a> {
    /// Executable proposal boundary. Model-supplied `confirm=true` cannot opt
    /// into controller mutations, including lease renewal and mailbox writes.
    pub fn call_read_only(
        &mut self,
        name: &str,
        args: &Value,
        deadline: std::time::Instant,
    ) -> Result<Value, DispatchError> {
        if !READ_ONLY_TOOLS.contains(&name) {
            return Err(DispatchError(format!(
                "proposal is read-only: tool `{name}` is not permitted"
            )));
        }
        crate::http::remaining(deadline).map_err(DispatchError)?;
        let request = match name {
            "fleet_logs" => {
                let id = str_field(args, "serviceID")
                    .ok_or_else(|| DispatchError("fleet_logs: serviceID is required".into()))?;
                let mut r = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Logs);
                r.service_id = Some(id);
                r.stream = Some(
                    args.get("stream")
                        .and_then(|v| v.as_str())
                        .unwrap_or("out")
                        .into(),
                );
                r.max_bytes = Some(8192);
                r
            }
            "fleet_events" => {
                let mut r = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Events);
                r.service_id = str_field(args, "serviceID");
                r.limit = Some(
                    args.get("limit")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(20)
                        .clamp(1, 50),
                );
                r
            }
            _ => fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Snapshot),
        };
        let response = match self.daemon()?.send_bounded(
            &request,
            deadline.min(std::time::Instant::now() + crate::guard::ROUND_TIMEOUT),
            crate::guard::MAX_RESPONSE_BYTES,
        ) {
            Ok(response) => response,
            Err(error) => {
                // A partial or oversized frame cannot be safely reused by a
                // later tool request. Drop it instead of reading stale bytes.
                *self.client = None;
                return Err(DispatchError(format!(
                    "controller round trip failed: {error}"
                )));
            }
        };
        let mut out = serde_json::to_value(OpaqueResponse::from(response))
            .map_err(|e| DispatchError(format!("encode response: {e}")))?;
        match name {
            "fleet_top_memory" => Ok(top_memory(
                &out,
                args.get("limit")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(10)
                    .clamp(1, 50) as usize,
            )),
            "fleet_mem_advice" => mem_advice(&out, args.get("serviceID").and_then(|v| v.as_str())),
            "fleet_ps" => {
                if let Some(snapshot) = out.get_mut("snapshot").and_then(|s| s.as_object_mut()) {
                    snapshot.retain(|key, _| key == "daemon" || key == "services");
                    if let Some(services) =
                        snapshot.get_mut("services").and_then(|s| s.as_array_mut())
                    {
                        for service in services {
                            if let Some(service) = service.as_object_mut() {
                                service.retain(|key, _| {
                                    matches!(
                                        key.as_str(),
                                        "id" | "friendlyName"
                                            | "ownerAgent"
                                            | "state"
                                            | "pid"
                                            | "resources"
                                    )
                                });
                            }
                        }
                    }
                }
                Ok(out)
            }
            _ => Ok(out),
        }
    }

    /// Fail closed with a reason when the daemon is missing: an agent
    /// surface that fabricates success over a dead socket is the defect
    /// class this codebase keeps having to remove.
    fn daemon(&mut self) -> Result<&mut fleet_proto::Client, DispatchError> {
        match self.client {
            Some(client) => Ok(client),
            None => Err(DispatchError(format!(
                "fleetd socket {} is not reachable — start the controller (`launchctl kickstart -k system/com.fleetconsole.fleetd` or open the console) and retry. Nothing was changed.",
                self.socket_path.display()
            ))),
        }
    }

    fn require_confirm(args: &Value, field: &str) -> Result<(), DispatchError> {
        match args.get("confirm") {
            Some(Value::Bool(true)) => Ok(()),
            Some(Value::Bool(false)) => Err(DispatchError(format!(
                "{field} refused: confirm=false. Mutating operations require an explicit confirm=true so an ambiguous request can never act."
            ))),
            _ => Err(DispatchError(format!(
                "{field} refused: missing confirm=true. Mutating operations require an explicit opt-in."
            ))),
        }
    }

    fn send(&mut self, request: fleet_proto::RpcRequest) -> Result<Value, DispatchError> {
        let op_debug = format!("{:?}", request.op);
        let daemon = self.daemon()?;
        let response = daemon
            .send(&request)
            .map_err(|e| DispatchError(format!("controller round trip failed: {e}")))?;
        let mut out = serde_json::to_value(OpaqueResponse::from(response))
            .map_err(|e| DispatchError(format!("encode response: {e}")))?;
        // Present a stable, agent-friendly shape: ok/error first-class.
        if let Some(obj) = out.as_object_mut() {
            obj.insert("op".into(), json!(op_debug));
        }
        Ok(out)
    }

    /// Execute one tool call. Returns the JSON `result` object.
    pub fn call(&mut self, name: &str, args: &Value) -> Result<Value, DispatchError> {
        if !is_known_tool(name) {
            return Err(DispatchError(format!(
                "unknown tool `{name}` — call tools/list for the exact set; never invent tool names"
            )));
        }
        let empty = json!({});
        let args = if args.as_object().is_some() {
            args.clone()
        } else {
            empty
        };
        match name {
            "fleet_snapshot" => {
                self.send(fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Snapshot))
            }
            "fleet_ps" => {
                let mut out =
                    self.send(fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Snapshot))?;
                if let Some(snapshot) = out.get_mut("snapshot").and_then(|s| s.as_object_mut()) {
                    snapshot.retain(|key, _| key == "daemon" || key == "services");
                    for service in snapshot
                        .get_mut("services")
                        .and_then(|s| s.as_array_mut())
                        .into_iter()
                        .flatten()
                    {
                        if let Some(obj) = service.as_object_mut() {
                            obj.retain(|key, _| {
                                matches!(
                                    key.as_str(),
                                    "id" | "friendlyName"
                                        | "ownerAgent"
                                        | "state"
                                        | "pid"
                                        | "resources"
                                )
                            });
                        }
                    }
                }
                Ok(out)
            }
            "fleet_top_memory" => {
                let limit = args
                    .get("limit")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(10)
                    .clamp(1, 50) as usize;
                let snapshot =
                    self.send(fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Snapshot))?;
                Ok(top_memory(&snapshot, limit))
            }
            "fleet_mem_advice" => {
                let snapshot =
                    self.send(fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Snapshot))?;
                mem_advice(&snapshot, args.get("serviceID").and_then(|v| v.as_str()))
            }
            "fleet_logs" => {
                let service_id = str_field(&args, "serviceID")
                    .ok_or_else(|| DispatchError("fleet_logs: serviceID is required".into()))?;
                let mut request = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Logs);
                request.service_id = Some(service_id);
                request.stream = Some(
                    args.get("stream")
                        .and_then(|v| v.as_str())
                        .unwrap_or("out")
                        .to_string(),
                );
                request.max_bytes = Some(8192);
                self.send(request)
            }
            "fleet_events" => {
                let mut request = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Events);
                request.service_id = str_field(&args, "serviceID");
                request.limit = Some(args.get("limit").and_then(|v| v.as_i64()).unwrap_or(20));
                self.send(request)
            }
            "fleet_launch" => {
                Self::require_confirm(&args, "fleet_launch")?;
                let command = args
                    .get("command")
                    .and_then(|v| v.as_array())
                    .and_then(|a| {
                        a.iter()
                            .map(|i| i.as_str().map(String::from))
                            .collect::<Option<Vec<String>>>()
                    })
                    .filter(|c| !c.is_empty())
                    .ok_or_else(|| {
                        DispatchError("fleet_launch: command must be a non-empty argv array".into())
                    })?;
                let launch = json!({
                    "command": command,
                    "cwd": str_field(&args, "cwd").unwrap_or_default(),
                    "friendlyName": str_field(&args, "friendlyName").unwrap_or_else(|| "fleet-agent service".into()),
                    "ownerAgent": str_field(&args, "ownerAgent").unwrap_or_else(|| FLEET_AGENT_ID.into()),
                    "purpose": str_field(&args, "purpose").unwrap_or_else(|| "launched by fleet-agent".into()),
                    "leaseTTLSec": args.get("leaseTTLSeconds").and_then(|v| v.as_f64()).unwrap_or(3600.0),
                    "env": {},
                    "declaredPorts": [],
                    "budget": {},
                    "health": {"kind": "none"},
                });
                let mut request = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Launch);
                request.launch = Some(launch);
                self.send(request)
            }
            "fleet_stop" | "fleet_restart" | "fleet_pause" | "fleet_resume" | "fleet_kill" => {
                Self::require_confirm(&args, name)?;
                let service_id = str_field(&args, "serviceID")
                    .ok_or_else(|| DispatchError(format!("{name}: serviceID is required")))?;
                let reason = str_field(&args, "reason")
                    .filter(|r| !r.trim().is_empty())
                    .ok_or_else(|| DispatchError(format!("{name}: a reason is required — it is recorded in the append-only event log")))?;
                let op = match name {
                    "fleet_stop" => fleet_proto::RpcOp::Stop,
                    "fleet_restart" => fleet_proto::RpcOp::Restart,
                    "fleet_pause" => fleet_proto::RpcOp::Pause,
                    "fleet_resume" => fleet_proto::RpcOp::Resume,
                    _ => fleet_proto::RpcOp::Kill,
                };
                let mut request = fleet_proto::RpcRequest::new(op);
                request.service_id = Some(service_id);
                request.reason = Some(reason);
                self.send(request)
            }
            "fleet_renew" => {
                let service_id = str_field(&args, "serviceID")
                    .ok_or_else(|| DispatchError("fleet_renew: serviceID is required".into()))?;
                let ttl = args
                    .get("ttlSeconds")
                    .and_then(|v| v.as_f64())
                    .filter(|t| *t > 0.0)
                    .ok_or_else(|| {
                        DispatchError("fleet_renew: ttlSeconds must be positive".into())
                    })?;
                let mut request = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Renew);
                request.service_id = Some(service_id);
                request.ttl_sec = Some(ttl);
                self.send(request)
            }
            "fleet_reconcile" => {
                Self::require_confirm(&args, "fleet_reconcile")?;
                self.send(fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Reconcile))
            }
            "fleet_message" => {
                let body = str_field(&args, "body")
                    .filter(|b| !b.trim().is_empty())
                    .ok_or_else(|| DispatchError("fleet_message: body is required".into()))?;
                let mut request = fleet_proto::RpcRequest::new(fleet_proto::RpcOp::PostMessage);
                request.agent = Some(FLEET_AGENT_ID.into());
                request.body = Some(body);
                request.kind = Some(
                    args.get("kind")
                        .and_then(|v| v.as_str())
                        .unwrap_or("info")
                        .to_string(),
                );
                request.needs_reply = Some(
                    args.get("needsReply")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                );
                self.send(request)
            }
            _ => Err(DispatchError(format!(
                "tool `{name}` is defined but not dispatched"
            ))),
        }
    }
}

// The controller reply is half-opaque by design (`fleet-proto` docs); wrap it
// so serde keeps every field the daemon sent, none invented.
#[derive(serde::Serialize)]
struct OpaqueResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    service: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    events: Option<Vec<Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    logs: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    daemon: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    messages: Option<Vec<Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<Value>,
}

impl From<fleet_proto::RpcResponse> for OpaqueResponse {
    fn from(response: fleet_proto::RpcResponse) -> Self {
        Self {
            ok: response.ok,
            error: response.error,
            snapshot: response.snapshot,
            service: response.service,
            events: response.events,
            logs: response.logs,
            daemon: response
                .daemon
                .map(|d| serde_json::to_value(&d).unwrap_or(Value::Null)),
            messages: response.messages,
            message: response.message,
        }
    }
}

#[allow(dead_code)]
fn response_json_unused() {}

fn str_field(args: &Value, key: &str) -> Option<String> {
    args.get(key).and_then(|v| v.as_str()).map(String::from)
}

// ---------------------------------------------------------------------------
// Specialized analysis over a snapshot payload
// ---------------------------------------------------------------------------

fn f64_at(value: &Value, pointer: &[&str]) -> Option<f64> {
    let mut current = value;
    for key in pointer {
        current = current.get(*key)?;
    }
    current.as_f64()
}

fn top_memory(snapshot_response: &Value, limit: usize) -> Value {
    let mut rows: Vec<(f64, Value)> = Vec::new();
    if let Some(services) = snapshot_response
        .get("snapshot")
        .and_then(|s| s.get("services"))
        .and_then(|s| s.as_array())
    {
        for service in services {
            let rss = f64_at(service, &["resources", "memMB"]).unwrap_or(0.0);
            let history: Vec<f64> = service
                .get("memHistory")
                .and_then(|h| h.as_array())
                .map(|a| a.iter().filter_map(|v| v.as_f64()).collect())
                .unwrap_or_default();
            let trend = crate::knowledge::classify_memory_trend(&history);
            let mut row = json!({
                "kind": "service",
                "id": service.get("id"),
                "name": service.get("friendlyName"),
                "ownerAgent": service.get("ownerAgent"),
                "state": service.get("state"),
                "pid": service.get("pid"),
                "rssMB": rss,
                "trend": format!("{:?}", trend.classification),
                "trendNote": trend.note,
            });
            if let Some(slope) = trend.slope_mb_per_sample {
                row["slopeMBPerSample"] = json!(slope);
            }
            rows.push((rss, row));
        }
    }
    if let Some(unmanaged) = snapshot_response
        .get("snapshot")
        .and_then(|s| s.get("unmanaged"))
        .and_then(|s| s.as_array())
    {
        for process in unmanaged {
            let rss = f64_at(process, &["resources", "memMB"]).unwrap_or(0.0);
            let row = json!({
                "kind": "unmanaged",
                "id": process.get("id"),
                "name": process.get("name"),
                "pid": process.get("pid"),
                "rssMB": rss,
                "note": "unmanaged: supervised and reported on, but the controller never signals processes it did not start — use `fleetctl claim` semantics via the operator, not fleet_kill",
            });
            rows.push((rss, row));
        }
    }
    rows.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    rows.truncate(limit);
    json!({
        "top": rows.into_iter().map(|(_, row)| row).collect::<Vec<Value>>(),
        "hint": "A Climbing trend outranks a high steady number: a leak candidate is urgent, a big working set is not.",
    })
}

fn mem_advice(snapshot_response: &Value, service_id: Option<&str>) -> Result<Value, DispatchError> {
    let snapshot = snapshot_response
        .get("snapshot")
        .ok_or_else(|| DispatchError("controller returned no snapshot".into()))?;
    if let Some(service_id) = service_id {
        let service = snapshot
            .get("services")
            .and_then(|s| s.as_array())
            .and_then(|a| {
                a.iter()
                    .find(|s| s.get("id").and_then(|i| i.as_str()) == Some(service_id))
            })
            .ok_or_else(|| {
                DispatchError(format!(
                    "no supervised service with id `{service_id}` — list ids with fleet_ps"
                ))
            })?;
        let rss = f64_at(service, &["resources", "memMB"]);
        let name = service
            .get("friendlyName")
            .and_then(|v| v.as_str())
            .unwrap_or(service_id);
        let history: Vec<f64> = service
            .get("memHistory")
            .and_then(|h| h.as_array())
            .map(|a| a.iter().filter_map(|v| v.as_f64()).collect())
            .unwrap_or_default();
        let trend = crate::knowledge::classify_memory_trend(&history);
        let advice = crate::knowledge::classify_process_memory(rss, name);
        let budget_warn = f64_at(service, &["budget", "memWarnMB"]);
        let breaches = service.get("budgetBreaches").cloned().unwrap_or(json!([]));
        return Ok(json!({
            "service": service_id,
            "name": name,
            "rssMB": rss,
            "classification": format!("{:?}", advice.classification),
            "trend": format!("{:?}", trend.classification),
            "trendNote": trend.note,
            "advice": advice.note,
            "budgetMemWarnMB": budget_warn,
            "budgetBreaches": breaches,
        }));
    }
    // System-wide: read the telemetry block the snapshot carries when present.
    let external = snapshot.get("external").cloned().unwrap_or(json!([]));
    let sessions = snapshot.get("sessions").cloned().unwrap_or(json!([]));
    Ok(json!({
        "scope": "system",
        "note": "macOS pressure is read from compressor and swap activity, not a free-memory figure; a cached page leaving memory is not pressure. This snapshot does not carry host vm counters — run `fleet_top_memory` and weigh the trends.",
        "external": external,
        "sessions": sessions,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tools_list_is_byte_stable_across_calls() {
        let a = tools_list_payload();
        let b = tools_list_payload();
        assert_eq!(a, b);
    }

    #[test]
    fn payload_matches_pinned_hash() {
        use sha2::Digest;
        let digest = sha2::Sha256::digest(tools_list_payload().as_bytes());
        let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(
            hex, SCHEMA_SHA256,
            "tool schema drifted — repin SCHEMA_SHA256 after review"
        );
    }

    #[test]
    fn every_definition_is_valid_canonical_json() {
        for tool in TOOLS {
            let parsed: Value = serde_json::from_str(tool.input_schema).expect(tool.name);
            assert_eq!(
                canonical(&parsed),
                tool.input_schema,
                "{} schema not canonical",
                tool.name
            );
        }
    }

    #[test]
    fn mutating_tools_are_gated() {
        assert!(!is_mutating("fleet_ps"));
        assert!(is_mutating("fleet_stop"));
        assert!(is_mutating("fleet_launch"));
        assert!(is_mutating("fleet_reconcile"));
        // renew and message mutate controller state but not processes;
        // they stay un-gated by design and are documented as such.
        assert!(is_mutating("fleet_renew"));
    }

    #[test]
    fn unknown_tool_fails_closed() {
        let mut none: Option<fleet_proto::Client> = None;
        let mut dispatcher = Dispatcher {
            client: &mut none,
            socket_path: Default::default(),
        };
        let err = dispatcher.call("fleet_shell", &json!({})).unwrap_err();
        assert!(err.0.contains("never invent tool names"));
    }

    #[test]
    fn missing_daemon_fails_closed_with_reason() {
        let mut none: Option<fleet_proto::Client> = None;
        let mut dispatcher = Dispatcher {
            client: &mut none,
            socket_path: std::path::PathBuf::from("/nope/fleetd.sock"),
        };
        let err = dispatcher.call("fleet_ps", &json!({})).unwrap_err();
        assert!(err.0.contains("is not reachable"), "got: {}", err.0);
        assert!(err.0.contains("Nothing was changed"));
    }

    #[test]
    fn confirm_gate_refuses_false_and_missing() {
        let mut none: Option<fleet_proto::Client> = None;
        let mut dispatcher = Dispatcher {
            client: &mut none,
            socket_path: Default::default(),
        };
        for args in [json!({}), json!({"confirm": false})] {
            let err = dispatcher.call("fleet_stop", &args).unwrap_err();
            assert!(err.0.contains("refused"), "got: {}", err.0);
        }
        // Missing daemon means we never reach the confirm-passed path's send,
        // so a true confirm must produce the *socket* error, not a panic.
        let err = dispatcher
            .call(
                "fleet_stop",
                &json!({"confirm": true, "serviceID": "x", "reason": "y"}),
            )
            .unwrap_err();
        assert!(err.0.contains("not reachable"));
    }

    #[test]
    fn top_memory_ranks_and_classifies() {
        let response = json!({
            "snapshot": {
                "services": [
                    {"id": "big", "friendlyName": "big", "resources": {"memMB": 2048.0},
                     "memHistory": [2000.0, 2010.0, 2020.0, 2030.0, 2040.0, 2050.0, 2060.0, 2070.0]},
                    {"id": "small", "friendlyName": "small", "resources": {"memMB": 90.0},
                     "memHistory": [80.0, 92.0, 81.0, 90.0, 85.0, 88.0, 82.0, 86.0]},
                ],
                "unmanaged": [
                    {"id": "u1", "name": "orphan", "pid": 999, "resources": {"memMB": 500.0}},
                ],
            }
        });
        let out = top_memory(&response, 10);
        let top = out.get("top").unwrap().as_array().unwrap();
        assert_eq!(top.len(), 3);
        assert_eq!(top[0]["id"], json!("big"));
        assert_eq!(top[0]["trend"], json!("Climbing"));
        assert_eq!(top[2]["id"], json!("small"));
        assert_eq!(top[2]["rssMB"], json!(90.0));
        // limit truncates
        let out2 = top_memory(&response, 1);
        assert_eq!(out2.get("top").unwrap().as_array().unwrap().len(), 1);
    }

    #[test]
    fn mem_advice_targets_a_service() {
        let response = json!({
            "snapshot": {
                "services": [
                    {"id": "svc", "friendlyName": "svc", "resources": {"memMB": 3000.0},
                     "memHistory": [3000.0, 3000.0, 3000.0, 3000.0, 3000.0, 3000.0, 3000.0, 3000.0], "budget": {"memWarnMB": 512.0},
                     "budgetBreaches": ["memWarn"]},
                ],
            }
        });
        let out = mem_advice(&response, Some("svc")).unwrap();
        assert_eq!(out["classification"], json!("Heavy"));
        assert_eq!(out["budgetBreaches"], json!(["memWarn"]));
        assert!(out["advice"].as_str().unwrap().contains("Before stopping"));
        let err = mem_advice(&response, Some("nope")).unwrap_err();
        assert!(err.0.contains("no supervised service"));
    }
}
