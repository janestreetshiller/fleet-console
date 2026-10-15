//! Binary entry: `fleet-agent serve` (MCP stdio), `fleet-agent ask "…"`,
//! `fleet-agent meter` (read/total the ledger), `fleet-agent self-check`.

use fleet_agent::engine::{self, EngineConfig, HttpModelClient, ModelClient};
use fleet_agent::meter::{self, MeterRecord, TurnUsage};
use fleet_agent::{default_ledger_path, default_socket_path, guard, server, tools};
use serde_json::json;
use std::io::{IsTerminal, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "fleet-agent — the FleetConsole resident operations agent

USAGE:
    fleet-agent serve                    MCP stdio server (JSON-RPC 2.0)
    fleet-agent propose \"<question>\"     read-only proposal against a configured endpoint
    fleet-agent propose --json \"<question>\" machine-readable proposal
    fleet-agent propose --prompt-file PATH read the complete UTF-8 question from a file
    fleet-agent ask \"<question>\"         compatibility alias for propose
    fleet-agent meter [--days N]         metered usage ledger, signed totals
    fleet-agent self-check                schema hash, daemon reachability, passive configuration

ENVIRONMENT:
    FLEET_AGENT_LLM_URL   explicit already-running loopback endpoint (required for inference)
    FLEET_AGENT_MODEL     model alias (default local; never loads or starts a server)
    FLEET_AGENT_LEDGER   ledger path (default <support>/agent-billing/meter-ledger.txt)
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("serve") => cmd_serve(),
        Some("ask" | "propose") => cmd_ask(&args[1..]),
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
    let dispatcher = tools::Dispatcher {
        client: &mut client,
        socket_path: socket,
    };
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
    let question = match proposal_question(rest) {
        Ok(question) => question,
        Err(error) => return proposal_error(json, &error),
    };
    if question.trim().is_empty() {
        eprintln!("ask: a question is required\n{USAGE}");
        return ExitCode::from(2);
    }
    let config = EngineConfig::default();
    if let Err(error) = guard::check_question(&question).and_then(|_| config.validate()) {
        return proposal_error(json, &error);
    }
    if let Err(error) = guard::require_headroom(guard::sample_memory()) {
        return proposal_error(json, &error);
    }
    let _lease =
        match guard::InferenceLease::acquire(&fleet_agent::support_dir().join("inference.lock")) {
            Ok(lease) => lease,
            Err(error) => return proposal_error(json, &error),
        };
    let socket = default_socket_path();
    let mut client = fleet_agent::connect_controller(&socket);
    if client.is_none() && !json {
        eprintln!(
            "note: fleetd not reachable at {} — read-only answers unavailable",
            socket.display()
        );
    }
    let mut dispatcher = tools::Dispatcher {
        client: &mut client,
        socket_path: socket,
    };
    let mut model = HttpModelClient::new(EngineConfig {
        base_url: config.base_url.clone(),
        model: config.model.clone(),
        max_iterations: config.max_iterations,
    });

    let started = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let presentation = ProposalPresentation::for_stream(json, std::io::stdout().is_terminal());
    if presentation.terminal {
        print!("{}", presentation.started());
        // The status must reach the PTY while the request is still running.
        let _ = std::io::stdout().flush();
    }
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
                print!("{}", presentation.reply(&turn.reply));
            }
            ExitCode::SUCCESS
        }
        Err(e) => proposal_error(json, &e),
    }
}

fn proposal_error(json: bool, error: &str) -> ExitCode {
    if json {
        println!("{}", json!({ "error": error }));
    } else {
        let presentation = ProposalPresentation::for_stream(false, std::io::stderr().is_terminal());
        eprint!("{}", presentation.error(error));
    }
    ExitCode::FAILURE
}

/// File transport keeps the full request out of the shell's command echo. The
/// same byte limit applies to inline questions and files, without truncation.
fn proposal_question(rest: &[String]) -> Result<String, String> {
    let mut inline = Vec::new();
    let mut prompt_file = None;
    let mut arguments = rest.iter();
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--json" => {}
            "--prompt-file" => {
                if prompt_file.is_some() {
                    return Err("--prompt-file may be supplied only once".into());
                }
                let path = arguments
                    .next()
                    .filter(|path| !path.starts_with("--") && !path.is_empty())
                    .ok_or("--prompt-file requires a path")?;
                prompt_file = Some(path);
            }
            flag if flag.starts_with("--") => {
                return Err(format!("unknown proposal flag {flag}"));
            }
            _ => inline.push(argument.as_str()),
        }
    }
    let Some(path) = prompt_file else {
        return Ok(inline.join(" "));
    };
    if !inline.is_empty() {
        return Err("use either --prompt-file or an inline question, not both".into());
    }
    use std::os::unix::fs::OpenOptionsExt;
    // The package targets Darwin and Linux; opening a FIFO must not wait for a
    // writer before we can reject it. O_NONBLOCK does not alter regular files.
    #[cfg(target_os = "macos")]
    const NONBLOCK: i32 = 0x0004;
    #[cfg(not(target_os = "macos"))]
    const NONBLOCK: i32 = 0x0800;
    let file = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(NONBLOCK)
        .open(path)
        .map_err(|error| format!("cannot read prompt file {path}: {error}"))?;
    if !file
        .metadata()
        .map_err(|error| format!("cannot inspect prompt file {path}: {error}"))?
        .is_file()
    {
        return Err(format!("prompt file {path} must be a regular file"));
    }
    let mut bytes = Vec::new();
    file.take((guard::MAX_QUESTION_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|error| format!("cannot read prompt file {path}: {error}"))?;
    if bytes.len() > guard::MAX_QUESTION_BYTES {
        return Err(format!(
            "proposal input exceeds {} bytes",
            guard::MAX_QUESTION_BYTES
        ));
    }
    String::from_utf8(bytes)
        .map_err(|error| format!("prompt file {path} is not valid UTF-8: {error}"))
}

/// Only Fleet Agent's own labels are styled. Reply/error content and terminal
/// control sequences pass through unchanged; machine-readable output stays raw.
struct ProposalPresentation {
    terminal: bool,
    emphasis: bool,
}

impl ProposalPresentation {
    fn for_stream(json: bool, terminal: bool) -> Self {
        Self::new(
            json,
            terminal,
            std::env::var_os("NO_COLOR").is_some(),
            std::env::var("TERM").as_deref() == Ok("dumb"),
        )
    }

    fn new(json: bool, terminal: bool, no_color: bool, dumb: bool) -> Self {
        Self {
            terminal: terminal && !json,
            emphasis: terminal && !json && !no_color && !dumb,
        }
    }

    fn label(&self, text: &str) -> String {
        if self.emphasis {
            format!("\x1b[1m{text}\x1b[0m")
        } else {
            text.into()
        }
    }

    fn started(&self) -> String {
        if self.terminal {
            format!("\n{} · Preparing proposal…\n", self.label("Fleet Agent"))
        } else {
            String::new()
        }
    }

    fn reply(&self, reply: &str) -> String {
        if self.terminal {
            format!("\n{}\n\n{reply}\n\n", self.label("Proposal"))
        } else {
            format!("{reply}\n")
        }
    }

    fn error(&self, error: &str) -> String {
        if self.terminal {
            format!("\n{}\n\nfleet-agent: {error}\n\n", self.label("Error"))
        } else {
            format!("fleet-agent: {error}\n")
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
            println!(
                "records: {} total, {} in the last {days} day(s), {} invalid signature(s)",
                records.len(),
                recent.len(),
                invalid
            );
            println!(
                "usage (window): {} input + {} output tokens across {} turn(s)",
                period_usage.input_tokens,
                period_usage.output_tokens,
                recent.iter().map(|r| r.turns).sum::<u64>()
            );
            println!(
                "usage (all time): {} input + {} output tokens",
                usage.input_tokens, usage.output_tokens
            );
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
            Ok(r) if r.ok => println!(
                "✓ fleetd reachable at {} (v{})",
                socket.display(),
                r.daemon.map(|d| d.version).unwrap_or_default()
            ),
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
    if config.base_url.is_empty() {
        println!("✓ inference is disabled until FLEET_AGENT_LLM_URL is explicitly configured");
    } else {
        match config.validate() {
            Ok(()) => {
                println!("✓ model configuration is valid (passive check; no model request sent)")
            }
            Err(error) => {
                println!("✗ model configuration: {error}");
                ok = false;
            }
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

#[cfg(test)]
mod cli_tests {
    use super::*;

    fn arguments(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn prompt_file_preserves_exact_utf8_question_including_whitespace() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("prompt 'quoted' ü.txt");
        let question = "  café 'quoted' $HOME `printf untouched`\r\n\nTrailing spaces  \n\n";
        std::fs::write(&path, question).unwrap();
        let rest = arguments(&["--json", "--prompt-file", path.to_str().unwrap()]);
        assert_eq!(
            proposal_question(&rest).unwrap().as_bytes(),
            question.as_bytes()
        );
    }

    #[test]
    fn prompt_file_accepts_the_limit_and_rejects_one_more_byte_and_invalid_utf8() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("prompt.txt");
        let rest = arguments(&["--prompt-file", path.to_str().unwrap()]);
        let exact = "é".repeat(guard::MAX_QUESTION_BYTES / 2);
        std::fs::write(&path, &exact).unwrap();
        assert_eq!(proposal_question(&rest).unwrap(), exact);
        std::fs::write(&path, format!("{exact}x")).unwrap();
        assert!(proposal_question(&rest)
            .unwrap_err()
            .contains("input exceeds"));
        std::fs::write(&path, [0xff, 0xfe]).unwrap();
        assert!(proposal_question(&rest)
            .unwrap_err()
            .contains("not valid UTF-8"));
    }

    #[test]
    fn prompt_file_rejects_fifo_and_directory_but_accepts_regular_symlink() {
        let directory = tempfile::tempdir().unwrap();
        let fifo = directory.path().join("prompt.fifo");
        assert!(std::process::Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .unwrap()
            .success());
        for path in [&fifo, &directory.path().to_path_buf()] {
            let start = std::time::Instant::now();
            let error = proposal_question(&arguments(&["--prompt-file", path.to_str().unwrap()]))
                .unwrap_err();
            assert!(error.contains("must be a regular file"), "{error}");
            assert!(start.elapsed() < std::time::Duration::from_secs(1));
        }
        let regular = directory.path().join("prompt.txt");
        let link = directory.path().join("prompt-link.txt");
        std::fs::write(&regular, "Exact linked content\n").unwrap();
        std::os::unix::fs::symlink(&regular, &link).unwrap();
        assert_eq!(
            proposal_question(&arguments(&["--prompt-file", link.to_str().unwrap()])).unwrap(),
            "Exact linked content\n"
        );
    }

    #[test]
    fn proposal_arguments_reject_ambiguous_or_incomplete_transport() {
        for (rest, error) in [
            (arguments(&["--prompt-file"]), "requires a path"),
            (arguments(&["--prompt-file", "--json"]), "requires a path"),
            (arguments(&["--prompt-file", ""]), "requires a path"),
            (
                arguments(&["--prompt-file", "one", "--prompt-file", "two"]),
                "only once",
            ),
            (arguments(&["question", "--prompt-file", "one"]), "not both"),
            (arguments(&["--prompt-file", "one", "question"]), "not both"),
            (
                arguments(&["--unknown", "question"]),
                "unknown proposal flag",
            ),
        ] {
            assert!(proposal_question(&rest).unwrap_err().contains(error));
        }
        assert_eq!(
            proposal_question(&arguments(&["first", "--json", "second"])).unwrap(),
            "first second"
        );
    }

    #[test]
    fn terminal_labels_leave_reply_and_error_bytes_intact() {
        let presentation = ProposalPresentation::new(false, true, false, false);
        for reply in [
            "Short finding.",
            "A long result that wraps only in the terminal, with  spaces and\n    indentation.",
            "\x1b[31mcolour\x1b[0m\rreplace\x1b[K\n世界\n\n",
        ] {
            assert_eq!(
                presentation.reply(reply),
                format!("\n\x1b[1mProposal\x1b[0m\n\n{reply}\n\n")
            );
        }
        let error = "request failed\n  detail: \x1b[31mE42\x1b[0m";
        assert_eq!(
            presentation.error(error),
            format!("\n\x1b[1mError\x1b[0m\n\nfleet-agent: {error}\n\n")
        );
        assert_eq!(
            presentation.started().matches("Preparing proposal").count(),
            1
        );
        if let Some(directory) = std::env::var_os("FLEET_AGENT_PRESENTATION_EVIDENCE_DIR") {
            let directory = std::path::PathBuf::from(directory);
            std::fs::create_dir_all(&directory).unwrap();
            for (name, reply) in [
                ("short.ansi", "TEST DATA: A short read-only proposal for formatter/PTY verification.".to_string()),
                ("wrapped.ansi", format!("TEST DATA: A long formatter/PTY proposal that must wrap without losing content.\n\n{}\n\n    Indented evidence stays indented.\n    /a/long/path/whose/full/content/must/stay/copyable/without/truncation", "Evidence, command, result and status remain readable with every original word preserved. ".repeat(5))),
                ("controls.ansi", "TEST DATA: Original terminal controls follow.\n\x1b[31mred content\x1b[0m\nProgress 10%\rProgress 90%\x1b[K\nUnicode 世界 · café\n\nOriginal blank line above.".to_string()),
            ] {
                std::fs::write(directory.join(name), presentation.started() + &presentation.reply(&reply)).unwrap();
            }
            std::fs::write(directory.join("error.ansi"), presentation.error("TEST DATA: Failed command\n  Full detail: permission denied for /a/long/path; diagnostic E42 stays intact.")).unwrap();
        }
    }

    #[test]
    fn pipes_json_no_color_and_dumb_term_preserve_their_output_contracts() {
        for (json, terminal) in [(false, false), (true, false), (true, true)] {
            let presentation = ProposalPresentation::new(json, terminal, false, false);
            assert!(presentation.started().is_empty());
            assert_eq!(presentation.reply("body\n"), "body\n\n");
            assert_eq!(presentation.error("detail\n"), "fleet-agent: detail\n\n");
        }
        for (no_color, dumb) in [(true, false), (false, true)] {
            let presentation = ProposalPresentation::new(false, true, no_color, dumb);
            assert_eq!(presentation.reply("body"), "\nProposal\n\nbody\n\n");
            assert_eq!(
                presentation.error("detail"),
                "\nError\n\nfleet-agent: detail\n\n"
            );
            assert!(!presentation.started().contains('\x1b'));
        }
    }
}
