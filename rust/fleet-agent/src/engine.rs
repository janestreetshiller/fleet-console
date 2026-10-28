//! The agent loop, forked from rx's engine pattern: system instructions built
//! once per session, a model client that emits tool calls, dispatch through
//! the typed tool surface, and per-turn usage accounting that feeds the meter.
//!
//! The model client speaks the OpenAI-compatible chat API that llama-server
//! exposes at 127.0.0.1 (the `RX_LOCAL_LLM_URL` convention), so the resident
//! agent runs on the same local inference the machine already serves — no
//! cloud call, no key, matching the console's locality doctrine.

use crate::guard;
use crate::meter::TurnUsage;
use crate::tools::{self, Dispatcher};
use serde_json::{json, Value};
use std::time::Instant;

pub const DEFAULT_MODEL: &str = "local";
pub const MAX_TOOL_ITERATIONS: usize = 8;

/// System prompt for the resident console agent. Byte-stable for a given
/// toolset: no timestamps, no host state, so the provider's prompt cache (and
/// our own determinism guarantees) survive across turns.
pub fn system_instructions() -> String {
    let names = tools::READ_ONLY_TOOLS.join(", ");
    format!(
        "You are FleetConsole's proposal agent for this Mac. Read evidence and propose a next step.\n\
         You have read-only tools: {names}. State-changing tools are unavailable.\n\
         Never launch or load a model, start a service, renew a lease, send mail, or mutate processes.\n\
         First inspect fleet_top_memory or fleet_ps; use fleet_mem_advice for memory trends.\n\
         A Climbing resident-memory trend is a leak candidate; a large steady working set alone is not.\n\
         Pausing a process keeps its RAM; it does not relieve memory pressure.\n\
         Lead with the finding and evidence, then propose an action for the operator to review."
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
            base_url: std::env::var("FLEET_AGENT_LLM_URL").unwrap_or_default(),
            model: std::env::var("FLEET_AGENT_MODEL").unwrap_or_else(|_| DEFAULT_MODEL.to_string()),
            max_iterations: MAX_TOOL_ITERATIONS,
        }
    }
}

impl EngineConfig {
    pub fn validate(&self) -> Result<(), String> {
        if self.base_url.trim().is_empty() {
            return Err("inference is not configured: set FLEET_AGENT_LLM_URL to an already running loopback model endpoint".into());
        }
        if self.base_url.len() > 2048 || self.base_url.contains(['\r', '\n', '?', '#']) {
            return Err("invalid model endpoint URL".into());
        }
        crate::http::Http::loopback_origin(&self.base_url)?;
        if self.model.is_empty() || self.model.len() > 128 {
            return Err("model name must be between 1 and 128 bytes".into());
        }
        Ok(())
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
    fn chat_until(&mut self, messages: &[Value], _deadline: Instant) -> Result<Value, String> {
        self.chat(messages)
    }
}

/// OpenAI-compatible client against the local llama-server.
pub struct HttpModelClient {
    config: EngineConfig,
    agent: crate::http::Http,
    memory_sample: fn() -> Result<guard::MemorySnapshot, String>,
}

impl HttpModelClient {
    pub fn new(config: EngineConfig) -> Self {
        Self {
            config,
            agent: crate::http::Http::new(guard::ROUND_TIMEOUT),
            memory_sample: guard::sample_memory,
        }
    }
}

impl ModelClient for HttpModelClient {
    fn chat(&mut self, messages: &[Value]) -> Result<Value, String> {
        self.chat_until(messages, Instant::now() + guard::ROUND_TIMEOUT)
    }
    fn chat_until(&mut self, messages: &[Value], deadline: Instant) -> Result<Value, String> {
        self.config.validate()?;
        guard::require_headroom((self.memory_sample)())?;
        let body = json!({
            "model": self.config.model,
            "messages": messages,
            "tools": tool_schemas(),
            "stream": false,
            "max_tokens": guard::MAX_OUTPUT_TOKENS,
            "parallel_tool_calls": false,
            "cache_prompt": false,
        });
        let url = format!(
            "{}/v1/chat/completions",
            self.config.base_url.trim_end_matches('/')
        );
        self.agent.post_json_until(&url, &body, deadline)
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
pub fn tool_schemas() -> Value {
    let list = tools::tools_list_payload();
    let parsed: Value = serde_json::from_str(&list).expect("static payload parses");
    let mcp_tools = parsed
        .get("tools")
        .and_then(|t| t.as_array())
        .cloned()
        .unwrap_or_default();
    let functions: Vec<Value> = mcp_tools
        .iter()
        .filter(|tool| tool.get("name").and_then(|n| n.as_str()).map(|name| tools::READ_ONLY_TOOLS.contains(&name)).unwrap_or(false))
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

/// A scripted client for tests; never used by the executable inference path.
pub struct ScriptedClient {
    pub replies: Vec<Value>,
    pub calls: std::cell::RefCell<Vec<Value>>,
}

impl ScriptedClient {
    pub fn new(replies: Vec<Value>) -> Self {
        Self {
            replies,
            calls: std::cell::RefCell::new(Vec::new()),
        }
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
    run_turn_until(
        client,
        dispatcher,
        history,
        user_message,
        config,
        Instant::now() + guard::TURN_TIMEOUT,
    )
}

/// The real loop takes an absolute deadline so transports and tool RPCs share
/// one budget; tests can exercise deadline edges without waiting 45 seconds.
pub fn run_turn_until(
    client: &mut dyn ModelClient,
    dispatcher: &mut Dispatcher<'_>,
    history: &mut Vec<Value>,
    user_message: &str,
    config: &EngineConfig,
    deadline: Instant,
) -> Result<TurnResult, String> {
    guard::check_question(user_message)?;
    let mut usage = TurnUsage::default();
    let mut tool_calls_made: Vec<String> = Vec::new();
    let mut iterations = 0usize;

    history.push(json!({ "role": "user", "content": user_message }));

    loop {
        crate::http::remaining(deadline)?;
        check_prompt(history)?;
        if iterations >= config.max_iterations.min(MAX_TOOL_ITERATIONS) {
            history.push(json!({
                "role": "assistant",
                "content": "Reached the tool-call iteration bound; stopping with what I have."
            }));
            check_prompt(history)?;
            break;
        }
        iterations += 1;
        let response = client.chat_until(history, deadline)?;
        crate::http::remaining(deadline)?;
        if let Some(u) = response.get("usage").and_then(|u| u.as_object()) {
            let input = u.get("prompt_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
            let output = u
                .get("completion_tokens")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
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
            check_prompt(history)?;
            return Ok(TurnResult {
                reply: content,
                tool_calls_made,
                usage,
                iterations,
            });
        }

        if tool_calls.len() > guard::MAX_TOOL_CALLS.saturating_sub(tool_calls_made.len()) {
            return Err(format!(
                "proposal exceeds {} total tool calls",
                guard::MAX_TOOL_CALLS
            ));
        }
        history.push(message);
        check_prompt(history)?;
        for call in &tool_calls {
            crate::http::remaining(deadline)?;
            let name = call
                .get("function")
                .and_then(|f| f.get("name"))
                .and_then(|n| n.as_str())
                .unwrap_or("");
            let argument_text = call
                .get("function")
                .and_then(|f| f.get("arguments"))
                .and_then(|a| a.as_str())
                .unwrap_or("{}");
            if argument_text.len() > guard::MAX_TOOL_ARGUMENT_BYTES {
                return Err(format!(
                    "tool arguments exceed {} bytes",
                    guard::MAX_TOOL_ARGUMENT_BYTES
                ));
            }
            let arguments = serde_json::from_str::<Value>(argument_text)
                .ok()
                .unwrap_or_else(|| json!({}));
            tool_calls_made.push(name.to_string());
            let result = dispatcher.call_read_only(name, &arguments, deadline);
            let payload = match result {
                Ok(value) => {
                    let mut bytes = crate::http::LimitedBytes::new(guard::MAX_TOOL_RESULT_BYTES);
                    match serde_json::to_writer(&mut bytes, &value) {
                        Ok(()) => {
                            json!({"content": String::from_utf8(bytes.bytes).expect("JSON is UTF-8")})
                        }
                        Err(_) => {
                            json!({"content": format!("error: tool result exceeds {} bytes; request compact fleet_ps or fleet_top_memory evidence", guard::MAX_TOOL_RESULT_BYTES), "isError": true})
                        }
                    }
                }
                Err(error) => json!({ "content": format!("error: {error}"), "isError": true }),
            };
            history.push(json!({
                "role": "tool",
                "tool_call_id": call.get("id").cloned().unwrap_or(Value::Null),
                "content": payload["content"].clone(),
            }));
            check_prompt(history)?;
        }
        crate::http::remaining(deadline)?;
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

fn check_prompt(history: &[Value]) -> Result<(), String> {
    let mut bytes = crate::http::LimitedBytes::new(guard::MAX_HISTORY_BYTES);
    serde_json::to_writer(&mut bytes, history).map_err(|_| {
        format!(
            "proposal history exceeds {} bytes",
            guard::MAX_HISTORY_BYTES
        )
    })?;
    // Bound the complete textual prompt separately from JSON overhead. A byte
    // bound is predictable without a tokenizer and stays below a modest context.
    let content_bytes: usize = history
        .iter()
        .map(|m| {
            m.get("content")
                .and_then(|v| v.as_str())
                .map(str::len)
                .unwrap_or(0)
        })
        .sum();
    if content_bytes > guard::MAX_PROMPT_BYTES {
        return Err(format!(
            "proposal prompt exceeds {} bytes",
            guard::MAX_PROMPT_BYTES
        ));
    }
    Ok(())
}

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
        assert!(a.contains("State-changing tools are unavailable"));
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
        let config = EngineConfig {
            base_url: String::new(),
            model: "scripted".into(),
            max_iterations: 4,
        };
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
        let endless: Vec<Value> = (0..10).map(|_| tool_call_reply("fleet_ps", "{}")).collect();
        let mut scripted = ScriptedClient::new(endless);
        let none: &'static mut Option<fleet_proto::Client> =
            Box::leak(Box::new(None::<fleet_proto::Client>));
        let mut dispatcher = tools::Dispatcher {
            client: none,
            socket_path: Default::default(),
        };
        let config = EngineConfig {
            base_url: String::new(),
            model: "scripted".into(),
            max_iterations: 3,
        };
        let result = ask_once(&mut scripted, &mut dispatcher, "go", &config).unwrap();
        assert_eq!(result.iterations, 3);
        assert!(result.reply.contains("iteration bound"));
    }
    fn healthy_sample() -> Result<guard::MemorySnapshot, String> {
        let gib = 1024 * 1024 * 1024;
        Ok(guard::MemorySnapshot {
            pressure: guard::Pressure::Normal,
            physical_bytes: 16 * gib,
            wired_bytes: gib,
            compressed_bytes: gib / 2,
            swap_used_bytes: 0,
        })
    }
    fn incident_sample() -> Result<guard::MemorySnapshot, String> {
        let gib = 1024 * 1024 * 1024;
        Ok(guard::MemorySnapshot {
            pressure: guard::Pressure::Normal,
            physical_bytes: 16 * gib,
            wired_bytes: 733_000 * 16_384,
            compressed_bytes: 5 * gib / 2,
            swap_used_bytes: 14 * gib,
        })
    }
    #[test]
    fn real_model_client_refuses_original_incident_before_connection() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let mut model = HttpModelClient::new(EngineConfig {
            base_url: format!("http://{}", listener.local_addr().unwrap()),
            model: "fixture".into(),
            max_iterations: 8,
        });
        model.memory_sample = incident_sample;
        let error = model
            .chat(&[json!({"role":"user","content":"inspect"})])
            .unwrap_err();
        assert!(error.contains("swap"), "{error}");
        assert_eq!(
            listener.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
    }

    #[test]
    fn real_http_model_turn_keeps_read_only_schemas_and_generation_bound() {
        use std::io::{BufRead, BufReader, Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let worker = std::thread::spawn(move || {
            for reply in [
                tool_call_reply(
                    "fleet_launch",
                    r#"{"confirm":true,"command":["llama-server"]}"#,
                ),
                final_reply("Review this proposal"),
            ] {
                let (stream, _) = listener.accept().unwrap();
                stream
                    .set_read_timeout(Some(std::time::Duration::from_secs(1)))
                    .unwrap();
                let mut reader = BufReader::new(stream);
                let mut length = 0;
                loop {
                    let mut line = String::new();
                    reader.read_line(&mut line).unwrap();
                    if line.trim().is_empty() {
                        break;
                    }
                    if let Some(value) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                        length = value.trim().parse::<usize>().unwrap();
                    }
                }
                let mut bytes = vec![0; length];
                reader.read_exact(&mut bytes).unwrap();
                let request: Value = serde_json::from_slice(&bytes).unwrap();
                assert_eq!(request["max_tokens"], guard::MAX_OUTPUT_TOKENS);
                assert_eq!(request["cache_prompt"], false);
                for schema in request["tools"].as_array().unwrap() {
                    assert!(!tools::is_mutating(
                        schema["function"]["name"].as_str().unwrap()
                    ));
                }
                if request["messages"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|m| m["role"] == "tool")
                {
                    assert!(request["messages"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .any(|m| m["content"]
                            .as_str()
                            .unwrap_or("")
                            .contains("proposal is read-only")));
                }
                let body = reply.to_string();
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{body}",
                    body.len()
                );
                reader.into_inner().write_all(response.as_bytes()).unwrap();
            }
        });
        let config = EngineConfig {
            base_url: url,
            model: "fixture".into(),
            max_iterations: 8,
        };
        let mut model = HttpModelClient::new(EngineConfig {
            base_url: config.base_url.clone(),
            model: config.model.clone(),
            max_iterations: 8,
        });
        model.memory_sample = healthy_sample;
        let mut controller = None;
        let mut dispatcher = Dispatcher {
            client: &mut controller,
            socket_path: "/missing".into(),
        };
        let result = ask_once(&mut model, &mut dispatcher, "inspect", &config).unwrap();
        worker.join().unwrap();
        assert_eq!(result.reply, "Review this proposal");
        assert_eq!(result.tool_calls_made, ["fleet_launch"]);
        assert_eq!(result.usage.input_tokens, 220);
        assert_eq!(result.usage.output_tokens, 40);
    }

    #[test]
    fn expired_turn_deadline_stops_before_model_call() {
        let mut model = ScriptedClient::new(vec![final_reply("must not be read")]);
        let mut controller = None;
        let mut dispatcher = Dispatcher {
            client: &mut controller,
            socket_path: "/missing".into(),
        };
        let mut history = Vec::new();
        let config = EngineConfig {
            base_url: String::new(),
            model: "scripted".into(),
            max_iterations: 8,
        };
        let error = run_turn_until(
            &mut model,
            &mut dispatcher,
            &mut history,
            "inspect",
            &config,
            Instant::now(),
        )
        .err()
        .unwrap();
        assert!(error.contains("deadline"));
        assert!(model.calls.borrow().is_empty());
    }
}
