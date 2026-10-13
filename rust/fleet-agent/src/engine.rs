//! The agent loop, forked from rx's engine pattern: system instructions built
//! once per session, a model client that emits tool calls, dispatch through
//! the typed tool surface, and per-turn usage accounting that feeds the meter.
//!
//! The model client speaks the OpenAI-compatible chat API that llama-server
//! exposes at 127.0.0.1 (the `RX_LOCAL_LLM_URL` convention), so the resident
//! agent runs on the same local inference the machine already serves — no
//! cloud call, no key, matching the console's locality doctrine.

use crate::meter::TurnUsage;
use crate::tools::{self, Dispatcher};
use serde_json::{json, Value};
use std::io::Write;
use std::time::{Duration, Instant};

pub const DEFAULT_LOCAL_LLM_URL: &str = "http://127.0.0.1:53144";
pub const DEFAULT_MODEL: &str = "qwen3.5-9b-local";
pub const MAX_TOOL_ITERATIONS: usize = 8;

/// System prompt for the resident console agent. Byte-stable for a given
/// toolset: no timestamps, no host state, so the provider's prompt cache (and
/// our own determinism guarantees) survive across turns.
pub fn system_instructions() -> String {
    let names = tools::tool_names().join(", ");
    format!(
        "You are the FleetConsole resident agent, living beside the fleetd controller on this Mac.\n\
         \n\
         ## What you are\n\
         A dedicated operations and routing agent for one machine's processes and memory. You help \
         with all things memory and process: what is running, what it costs, whether a number is \
         healthy, and what the honest next step is. You are an advisor first — mutation needs an \
         explicit confirm, and you must state what you are about to do and why before doing it.\n\
         \n\
         ## Specialized memory knowledge\n\
         - A Climbing resident-memory trend (sustained slope) outranks a high steady number: a leak \
         candidate is urgent, a big working set is not. One big sample is usually a legitimate \
         one-off (build, index, migration).\n\
         - macOS has no free-memory figure worth reading: cached pages leaving is not pressure. \
         Real pressure shows in compressor activity and swap use.\n\
         - A paused process still holds its ports and memory; pausing is the reversible first move \
         under pressure, stopping is not.\n\
         - The console clamps memory-used to the physical total because compressor counters can \
         drift above it; trust the trend over the absolute.\n\
         - Unmanaged processes are supervised and reported on but never signalled by the \
         controller — do not recommend fleet_kill for them.\n\
         \n\
         ## Process doctrine\n\
         - The controller owns process lifecycle: leases, budgets, health checks, reaping. Never \
         suggest spawning a process outside it.\n\
         - Stopped services do not come back on their own; every mutating call records a reason \
         in the append-only event log. Give the operator a reason worth reading.\n\
         - Unanswered operator mail outranks any technical finding. If a question is waiting, \
         surface it first.\n\
         \n\
         ## Authoritative advertised tools\n\
         Only these tools are callable: {names}.\n\
         If a capability is not in this list, say so — never invent tool names, never pass fields \
         the schema does not define. fleet_snapshot is the right first call for nearly every \
         question; fleet_top_memory and fleet_mem_advice carry the specialist memory reading.\n\
         Mutating tools (fleet_launch, fleet_stop, fleet_restart, fleet_pause, fleet_resume, \
         fleet_kill, fleet_reconcile) require confirm=true; set it only when the operator asked \
         for the action or you stated the action and its reason and no objection was raised in \
         this conversation.\n\
         \n\
         ## Voice\n\
         Plain, direct, operator-first. Lead with the finding, then the evidence, then the next \
         step. No filler, no celebration."
    )
}

pub struct EngineConfig {
    pub base_url: String,
    pub model: String,
    pub max_iterations: usize,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            base_url: std::env::var("FLEET_AGENT_LLM_URL")
                .unwrap_or_else(|_| DEFAULT_LOCAL_LLM_URL.to_string()),
            model: std::env::var("FLEET_AGENT_MODEL")
                .unwrap_or_else(|_| DEFAULT_MODEL.to_string()),
            max_iterations: MAX_TOOL_ITERATIONS,
        }
    }
}

/// One model round trip. Kept as a trait so tests can drive the loop without
/// a live llama-server, while the real run goes over HTTP.
///
/// Returns the *full* response object, not just the choice: usage accounting
/// lives at the top level in the OpenAI shape, and dropping it would meter a
/// real turn as a free one.
pub trait ModelClient {
    fn chat(&mut self, messages: &[Value]) -> Result<Value, String>;
    fn name(&self) -> String;
}

/// OpenAI-compatible client against the local llama-server.
pub struct HttpModelClient {
    config: EngineConfig,
    agent: crate::http::Http,
}

impl HttpModelClient {
    pub fn new(config: EngineConfig) -> Self {
        Self { config, agent: crate::http::Http::new(Duration::from_secs(180)) }
    }
}

impl ModelClient for HttpModelClient {
    fn chat(&mut self, messages: &[Value]) -> Result<Value, String> {
        let body = json!({
            "model": self.config.model,
            "messages": messages,
            "tools": tool_schemas(),
            "stream": false,
            "max_tokens": 2048,
        });
        let url = format!("{}/v1/chat/completions", self.config.base_url);
        self.agent.post_json(&url, &body)
    }

    fn name(&self) -> String {
        self.config.model.clone()
    }
}

/// The llama-server tool schema form (OpenAI function-calling shape), derived
/// from the same definitions the MCP surface serves so the two clients can
/// never disagree about what exists. The wire shapes differ — MCP lists
/// `inputSchema` at the top level, the chat API nests under `function` —
/// but the names, descriptions and parameter schemas are the single source
/// in `TOOLS`.
fn tool_schemas() -> Value {
    let list = tools::tools_list_payload();
    let parsed: Value = serde_json::from_str(&list).expect("static payload parses");
    let mcp_tools = parsed
        .get("tools")
        .and_then(|t| t.as_array())
        .cloned()
        .unwrap_or_default();
    let functions: Vec<Value> = mcp_tools
        .iter()
        .map(|tool| {
            json!({
                "type": "function",
                "function": {
                    "name": tool.get("name").cloned().unwrap_or(Value::Null),
                    "description": tool.get("description").cloned().unwrap_or(Value::Null),
                    "parameters": tool.get("inputSchema").cloned().unwrap_or_else(|| json!({"type": "object", "properties": {}})),
                }
            })
        })
        .collect();
    json!(functions)
}

/// A scripted client for tests and the offline `--self-check` path.
pub struct ScriptedClient {
    pub replies: Vec<Value>,
    pub calls: std::cell::RefCell<Vec<Value>>,
}

impl ScriptedClient {
    pub fn new(replies: Vec<Value>) -> Self {
        Self { replies, calls: std::cell::RefCell::new(Vec::new()) }
    }
}

impl ModelClient for ScriptedClient {
    fn chat(&mut self, _messages: &[Value]) -> Result<Value, String> {
        // Pop the next scripted reply; an exhausted script is an error so a
        // test can never silently loop on the final reply.
        if self.replies.is_empty() {
            return Err("scripted client exhausted".into());
        }
        let reply = self.replies.remove(0);
        self.calls.borrow_mut().push(reply.clone());
        Ok(reply)
    }

    fn name(&self) -> String {
        "scripted".into()
    }
}

/// Result of one agent turn.
pub struct TurnResult {
    pub reply: String,
    pub tool_calls_made: Vec<String>,
    pub usage: TurnUsage,
    pub iterations: usize,
}

impl TurnResult {
    pub fn is_zero(&self) -> bool {
        self.usage.is_zero() && self.tool_calls_made.is_empty()
    }
}

/// Run one operator turn: model -> (tool call -> result)* -> final answer.
/// Every iteration is bounded; usage is accumulated across the whole turn.
pub fn run_turn(
    client: &mut dyn ModelClient,
    dispatcher: &mut Dispatcher<'_>,
    history: &mut Vec<Value>,
    user_message: &str,
    config: &EngineConfig,
) -> Result<TurnResult, String> {
    let start = Instant::now();
    let mut usage = TurnUsage::default();
    let mut tool_calls_made: Vec<String> = Vec::new();
    let mut iterations = 0usize;

    history.push(json!({ "role": "user", "content": user_message }));

    loop {
        if iterations >= config.max_iterations {
            history.push(json!({
                "role": "assistant",
                "content": "Reached the tool-call iteration bound; stopping with what I have."
            }));
            break;
        }
        iterations += 1;
        let response = client.chat(history)?;
        if let Some(u) = response.get("usage").and_then(|u| u.as_object()) {
            let input = u.get("prompt_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
            let output = u.get("completion_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
            usage.input_tokens += input;
            usage.output_tokens += output;
        }

        let message = response
            .get("choices")
            .and_then(|c| c.get(0))
            .and_then(|c| c.get("message"))
            .cloned()
            .ok_or_else(|| "model reply had no choices[0].message".to_string())?;
        let tool_calls = message
            .get("tool_calls")
            .and_then(|t| t.as_array())
            .cloned()
            .unwrap_or_default();

        if tool_calls.is_empty() {
            let content = message
                .get("content")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            history.push(json!({ "role": "assistant", "content": content }));
            return Ok(TurnResult { reply: content, tool_calls_made, usage, iterations });
        }

        history.push(message);
        for call in &tool_calls {
            let name = call
                .get("function")
                .and_then(|f| f.get("name"))
                .and_then(|n| n.as_str())
                .unwrap_or("");
            let arguments = call
                .get("function")
                .and_then(|f| f.get("arguments"))
                .and_then(|a| a.as_str())
                .and_then(|a| serde_json::from_str::<Value>(a).ok())
                .unwrap_or_else(|| json!({}));
            tool_calls_made.push(name.to_string());
            let result = dispatcher.call(name, &arguments);
            let payload = match result {
                Ok(value) => json!({ "content": tools::canonical(&value) }),
                Err(error) => json!({ "content": format!("error: {error}"), "isError": true }),
            };
            history.push(json!({
                "role": "tool",
                "tool_call_id": call.get("id").cloned().unwrap_or(Value::Null),
                "content": payload["content"].clone(),
            }));
        }
        let _ = start.elapsed();
    }

    Ok(TurnResult {
        reply: "Reached the tool-call iteration bound; stopping with what I have.".to_string(),
        tool_calls_made,
        usage,
        iterations,
    })
}

/// Convenience for the CLI's one-shot path: fresh history, one turn.
pub fn ask_once(
    client: &mut dyn ModelClient,
    dispatcher: &mut Dispatcher<'_>,
    question: &str,
    config: &EngineConfig,
) -> Result<TurnResult, String> {
    let mut history = vec![json!({ "role": "system", "content": system_instructions() })];
    run_turn(client, dispatcher, &mut history, question, config)
}

#[allow(dead_code)]
fn unused(_w: &mut impl Write) {}

#[cfg(test)]
mod tests {
    use super::*;

    /// A scripted reply carrying a tool call, in the OpenAI shape.
    fn tool_call_reply(name: &str, args: &str) -> Value {
        json!({
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": null,
                    "tool_calls": [{
                        "id": "call-1",
                        "type": "function",
                        "function": { "name": name, "arguments": args }
                    }]
                }
            }],
            "usage": { "prompt_tokens": 100, "completion_tokens": 10 }
        })
    }

    fn final_reply(text: &str) -> Value {
        json!({
            "choices": [{ "message": { "role": "assistant", "content": text } }],
            "usage": { "prompt_tokens": 120, "completion_tokens": 30 }
        })
    }

    #[test]
    fn system_instructions_are_byte_stable_and_name_the_tools() {
        let a = system_instructions();
        let b = system_instructions();
        assert_eq!(a, b);
        assert!(a.contains("fleet_top_memory"));
        assert!(a.contains("confirm=true"));
        assert!(a.contains("Climbing resident-memory trend"));
    }

    #[test]
    fn loop_dispatches_then_answers_and_meters_both_round_trips() {
        // A turn that calls fleet_ps (unknown tool's read-only cousin — the
        // dispatch fails closed with the socket error, which the model then
        // answers from) and finishes.
        let mut scripted = ScriptedClient::new(vec![
            tool_call_reply("fleet_ps", "{}"),
            final_reply("the console is unreachable"),
        ]);
        let none: &'static mut Option<fleet_proto::Client> =
            Box::leak(Box::new(None::<fleet_proto::Client>));
        let mut dispatcher = tools::Dispatcher {
            client: none,
            socket_path: std::path::PathBuf::from("/missing/fleetd.sock"),
        };
        let config = EngineConfig { base_url: String::new(), model: "scripted".into(), max_iterations: 4 };
        let result = ask_once(&mut scripted, &mut dispatcher, "list services", &config).unwrap();
        assert_eq!(result.tool_calls_made, vec!["fleet_ps"]);
        assert!(result.reply.contains("unreachable") || !result.reply.is_empty());
        // Both round trips metered: 100+120 input, 10+30 output.
        assert_eq!(result.usage.input_tokens, 220);
        assert_eq!(result.usage.output_tokens, 40);
        assert_eq!(result.iterations, 2);
    }

    #[test]
    fn iteration_bound_stops_the_loop() {
        let endless: Vec<Value> = (0..10)
            .map(|_| tool_call_reply("fleet_ps", "{}"))
            .collect();
        let mut scripted = ScriptedClient::new(endless);
        let none: &'static mut Option<fleet_proto::Client> =
            Box::leak(Box::new(None::<fleet_proto::Client>));
        let mut dispatcher = tools::Dispatcher {
            client: none,
            socket_path: Default::default(),
        };
        let config = EngineConfig { base_url: String::new(), model: "scripted".into(), max_iterations: 3 };
        let result = ask_once(&mut scripted, &mut dispatcher, "go", &config).unwrap();
        assert_eq!(result.iterations, 3);
        assert!(result.reply.contains("iteration bound"));
    }
}