//! Binary entry: `fleet-agent serve` (MCP stdio), `fleet-agent ask "…"`,
//! `fleet-agent meter` (read/total the ledger), `fleet-agent self-check`.

use fleet_agent::engine::{self, EngineConfig, HttpModelClient, ModelClient};
use fleet_agent::meter::{self, MeterRecord, TurnUsage};
use fleet_agent::{default_ledger_path, default_socket_path, server, tools};
use serde_json::json;
use std::io::{IsTerminal, Write};
use std::process::ExitCode;

const USAGE: &str = "fleet-agent — the FleetConsole resident operations agent

USAGE:
    fleet-agent serve                    MCP stdio server (JSON-RPC 2.0)
    fleet-agent ask \"<question>\"         one agent turn against the local model
    fleet-agent ask --json \"<question>\"  machine-readable turn result
    fleet-agent meter [--days N]         metered usage ledger, signed totals
    fleet-agent self-check                schema hash, daemon reachability, model health

ENVIRONMENT:
    FLEET_AGENT_LLM_URL   local model endpoint (default http://127.0.0.1:53144)
    FLEET_AGENT_MODEL     model name (default qwen3.5-9b-local)
    FLEET_AGENT_LEDGER   ledger path (default <support>/agent-billing/meter-ledger.txt)
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("serve") => cmd_serve(),
        Some("ask") => cmd_ask(&args[1..]),
        Some("meter") => cmd_meter(&args[1..]),
        Some("self-check") => cmd_self_check(),
        Some("--help" | "-h" | "help") | None => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Some(other) => {
            eprintln!("unknown command `{other}`\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

fn cmd_serve() -> ExitCode {
    let socket = default_socket_path();
    let mut client = fleet_agent::connect_controller(&socket);
    if client.is_none() {
        // Fail closed but keep serving: the host sees per-call errors naming
        // the socket, which is the contract. A server that refuses to start
        // leaves the host with no tools/list at all.
        eprintln!(
            "fleet-agent: fleetd socket {} not reachable — tools/call will fail closed until the controller is up",
            socket.display()
        );
    }
    let dispatcher = tools::Dispatcher { client: &mut client, socket_path: socket };
    let mut srv = server::Server::new(dispatcher);
    match srv.serve(std::io::stdin().lock(), std::io::stdout().lock()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fleet-agent: stdio error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn cmd_ask(rest: &[String]) -> ExitCode {
    let json = rest.iter().any(|a| a == "--json");
    let question = rest
        .iter()
        .filter(|a| !a.starts_with("--"))
        .cloned()
        .collect::<Vec<_>>()
        .join(" ");
    if question.trim().is_empty() {
        eprintln!("ask: a question is required\n{USAGE}");
        return ExitCode::from(2);
    }
    let socket = default_socket_path();
    let mut client = fleet_agent::connect_controller(&socket);
    if client.is_none() && !json {
        eprintln!("note: fleetd not reachable at {} — read-only answers unavailable", socket.display());
    }
    let mut dispatcher = tools::Dispatcher { client: &mut client, socket_path: socket };
    let config = EngineConfig::default();
    let mut model = HttpModelClient::new(EngineConfig {
        base_url: config.base_url.clone(),
        model: config.model.clone(),
        max_iterations: config.max_iterations,
    });

    let started = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let result = engine::ask_once(&mut model, &mut dispatcher, &question, &config);
    match result {
        Ok(turn) => {
            // Meter the turn: one signed record appended per ask.
            let ledger = std::env::var("FLEET_AGENT_LEDGER")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| default_ledger_path());
            let record = MeterRecord {
                agent: tools::FLEET_AGENT_ID.to_string(),
                period: meter::period_for_timestamp(started),
                model: model.name(),
                input_tokens: turn.usage.input_tokens,
                output_tokens: turn.usage.output_tokens,
                turns: 1,
            };
            let metered = meter::append_ledger(&ledger, &record, meter::VENDOR_SECRET);
            if let Err(e) = metered {
                eprintln!("warning: could not append meter record: {e}");
            }
            if json {
                let out = json!({
                    "reply": turn.reply,
                    "toolCalls": turn.tool_calls_made,
                    "usage": {
                        "inputTokens": turn.usage.input_tokens,
                        "outputTokens": turn.usage.output_tokens,
                    },
                    "iterations": turn.iterations,
                    "model": model.name(),
                });
                println!("{}", out);
            } else {
                println!("{}", turn.reply);
            }
            ExitCode::SUCCESS
        }
        Err(e) => {
            if json {
                println!("{}", json!({ "error": e }));
            } else {
                eprintln!("fleet-agent: {e}");
            }
            ExitCode::FAILURE
        }
    }
}

fn cmd_meter(rest: &[String]) -> ExitCode {
    let path = std::env::var("FLEET_AGENT_LEDGER")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| default_ledger_path());
    let days = rest
        .iter()
        .position(|a| a == "--days")
        .and_then(|i| rest.get(i + 1))
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(7);
    match meter::total_ledger(&path, meter::VENDOR_SECRET) {
        Ok((records, invalid, usage)) => {
            let cutoff = (std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0)
                - (days as i64) * 86_400)
                .to_string();
            let recent: Vec<&MeterRecord> = records
                .iter()
                .filter(|r| r.period.as_str() >= cutoff.as_str())
                .collect();
            let period_usage = recent.iter().fold(TurnUsage::default(), |mut acc, r| {
                acc.input_tokens += r.input_tokens;
                acc.output_tokens += r.output_tokens;
                acc
            });
            println!("ledger: {}", path.display());
            println!("records: {} total, {} in the last {days} day(s), {} invalid signature(s)",
                records.len(), recent.len(), invalid);
            println!(
                "usage (window): {} input + {} output tokens across {} turn(s)",
                period_usage.input_tokens, period_usage.output_tokens,
                recent.iter().map(|r| r.turns).sum::<u64>()
            );
            println!("usage (all time): {} input + {} output tokens", usage.input_tokens, usage.output_tokens);
            if invalid > 0 {
                eprintln!(
                    "warning: {invalid} ledger line(s) failed signature validation and were excluded — inspect the file before billing from it"
                );
            }
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("meter: cannot read {}: {e}", path.display());
            ExitCode::FAILURE
        }
    }
}

fn cmd_self_check() -> ExitCode {
    use sha2::Digest;
    let mut ok = true;

    let payload = tools::tools_list_payload();
    let digest = sha2::Sha256::digest(payload.as_bytes());
    let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
    let pinned = tools::SCHEMA_SHA256;
    if hex == pinned {
        println!("✓ tool schema pinned: {hex}");
    } else {
        println!("✗ tool schema DRIFTED: pinned {pinned}, actual {hex}");
        ok = false;
    }

    let socket = default_socket_path();
    let mut client = fleet_agent::connect_controller(&socket);
    if let Some(ref mut c) = client {
        let response = c.send(&fleet_proto::RpcRequest::new(fleet_proto::RpcOp::Ping));
        match response {
            Ok(r) if r.ok => println!("✓ fleetd reachable at {} (v{})", socket.display(),
                r.daemon.map(|d| d.version).unwrap_or_default()),
            _ => {
                println!("✗ fleetd at {} answered with an error", socket.display());
                ok = false;
            }
        }
    } else {
        println!("✗ fleetd socket {} not reachable", socket.display());
        ok = false;
    }

    let config = EngineConfig::default();
    let mut model = HttpModelClient::new(EngineConfig {
        base_url: config.base_url.clone(),
        model: config.model.clone(),
        max_iterations: config.max_iterations,
    });
    let probe = model.chat(&[json!({
        "role": "user",
        "content": "Reply with the single word: ok"
    })]);
    match probe {
        Ok(response) => {
            let content = response
                .get("choices")
                .and_then(|c| c.get(0))
                .and_then(|c| c.get("message"))
                .and_then(|m| m.get("content"))
                .and_then(|c| c.as_str())
                .unwrap_or("");
            println!("✓ local model {} answered: {}", model.name(), content.chars().take(60).collect::<String>());
        }
        Err(e) => {
            println!("✗ local model {} at {}: {e}", model.name(), config.base_url);
            ok = false;
        }
    }

    if std::io::stdout().is_terminal() {
        let _ = std::io::stdout().flush();
    }
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
