use fleet_agent::engine::EngineConfig;

#[test]
fn inference_requires_an_explicit_endpoint() {
    std::env::remove_var("FLEET_AGENT_LLM_URL");
    assert!(
        EngineConfig::default().base_url.is_empty(),
        "bundling must not opt into RX's 9B model endpoint"
    );
}

use fleet_agent::engine::{ask_once, tool_schemas, ScriptedClient};
use fleet_agent::guard::{
    InferenceLease, MAX_HISTORY_BYTES, MAX_QUESTION_BYTES, MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES,
};
use fleet_agent::http::Http;
use fleet_agent::tools::Dispatcher;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::process::Command;
use std::time::{Duration, Instant};

#[test]
fn proposal_schema_has_no_state_changing_tools() {
    let schemas = tool_schemas();
    let names: Vec<&str> = schemas
        .as_array()
        .unwrap()
        .iter()
        .map(|schema| schema["function"]["name"].as_str().unwrap())
        .collect();
    assert_eq!(names.len(), fleet_agent::tools::READ_ONLY_TOOLS.len());
    for name in names {
        assert!(!fleet_agent::tools::is_mutating(name), "{name}");
    }
}
fn cli() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_fleet-agent"));
    command
        .env_remove("FLEET_AGENT_LLM_URL")
        .env_remove("FLEET_AGENT_MODEL");
    command
}
#[test]
fn executable_propose_and_ask_refuse_unconfigured_inference_as_json() {
    for verb in ["propose", "ask"] {
        let output = cli()
            .args([verb, "--json", "inspect memory"])
            .output()
            .unwrap();
        assert!(!output.status.success());
        let value: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert!(value["error"]
            .as_str()
            .unwrap()
            .contains("set FLEET_AGENT_LLM_URL"));
    }
}
#[test]
fn executable_rejects_oversized_input_before_any_model_connection() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let output = cli()
        .env(
            "FLEET_AGENT_LLM_URL",
            format!("http://{}", listener.local_addr().unwrap()),
        )
        .args(["propose", "--json", &"x".repeat(MAX_QUESTION_BYTES + 1)])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8(output.stdout)
        .unwrap()
        .contains("input exceeds"));
    assert_eq!(
        listener.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
}
#[test]
fn executable_self_check_never_sends_a_model_request() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let output = cli()
        .env(
            "FLEET_AGENT_LLM_URL",
            format!("http://{}", listener.local_addr().unwrap()),
        )
        .arg("self-check")
        .output()
        .unwrap();
    assert!(String::from_utf8(output.stdout)
        .unwrap()
        .contains("passive check; no model request sent"));
    assert_eq!(
        listener.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
}
#[test]
fn executable_remote_endpoint_fails_before_network() {
    let output = cli()
        .env("FLEET_AGENT_LLM_URL", "http://example.com:53144")
        .args(["propose", "--json", "inspect"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8(output.stdout)
        .unwrap()
        .contains("non-loopback"));
}
fn final_reply(content: &str) -> Value {
    json!({"choices":[{"message":{"role":"assistant","content":content}}]})
}
fn config() -> EngineConfig {
    EngineConfig {
        base_url: String::new(),
        model: "scripted".into(),
        max_iterations: 8,
    }
}

#[test]
fn proposal_mutation_is_refused_before_a_live_controller_rpc() {
    use std::os::unix::net::UnixListener;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("fleetd.sock");
    let listener = UnixListener::bind(&path).unwrap();
    let mut controller = Some(fleet_proto::Client::connect(&path).unwrap());
    let (mut connection, _) = listener.accept().unwrap();
    connection
        .set_read_timeout(Some(Duration::from_millis(50)))
        .unwrap();
    let mut dispatcher = Dispatcher {
        client: &mut controller,
        socket_path: path,
    };
    for name in [
        "fleet_launch",
        "fleet_restart",
        "fleet_stop",
        "fleet_pause",
        "fleet_resume",
        "fleet_kill",
        "fleet_reconcile",
        "fleet_renew",
        "fleet_message",
    ] {
        let denied = dispatcher.call_read_only(name, &json!({"confirm":true,"command":["llama-server"],"ttlSeconds":3600,"body":"hello"}), Instant::now()+Duration::from_secs(1)).unwrap_err();
        assert!(denied.to_string().contains("read-only"), "{name}: {denied}");
    }
    let mut byte = [0];
    let error = connection.read(&mut byte).unwrap_err();
    assert!(matches!(
        error.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    ));
}
#[test]
fn model_confirm_cannot_authorize_mutation_in_real_turn() {
    let mut scripted = ScriptedClient::new(vec![
        json!({"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"1","function":{"name":"fleet_launch","arguments":"{\"confirm\":true,\"command\":[\"llama-server\"]}"}}]}}]}),
        final_reply("review the proposal"),
    ]);
    let mut controller = None;
    let mut dispatcher = Dispatcher {
        client: &mut controller,
        socket_path: "/missing".into(),
    };
    let mut history = Vec::new();
    let result = fleet_agent::engine::run_turn(
        &mut scripted,
        &mut dispatcher,
        &mut history,
        "inspect",
        &config(),
    )
    .unwrap();
    assert_eq!(result.tool_calls_made, ["fleet_launch"]);
    assert!(history.iter().any(|m| m["role"] == "tool"
        && m["content"]
            .as_str()
            .unwrap_or("")
            .contains("proposal is read-only")));
}
#[test]
fn history_and_total_tool_calls_are_bounded_before_additional_work() {
    let mut controller = None;
    let mut dispatcher = Dispatcher {
        client: &mut controller,
        socket_path: "/missing".into(),
    };
    let mut scripted = ScriptedClient::new(vec![final_reply("must not be read")]);
    let mut history = vec![json!({"role":"system","content":"x".repeat(MAX_HISTORY_BYTES+1)})];
    let error = fleet_agent::engine::run_turn(
        &mut scripted,
        &mut dispatcher,
        &mut history,
        "inspect",
        &config(),
    )
    .err()
    .unwrap();
    assert!(error.contains("history exceeds"));
    assert!(scripted.calls.borrow().is_empty());
    let calls: Vec<Value> = (0..17)
        .map(|id| json!({"id":id.to_string(),"function":{"name":"fleet_ps","arguments":"{}"}}))
        .collect();
    let mut scripted = ScriptedClient::new(vec![
        json!({"choices":[{"message":{"role":"assistant","tool_calls":calls}}]}),
    ]);
    let error = ask_once(&mut scripted, &mut dispatcher, "inspect", &config())
        .err()
        .unwrap();
    assert!(error.contains("total tool calls"));
}
fn response_server(wire: Vec<u8>, trickle: bool) -> (String, std::thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!(
        "http://{}/v1/chat/completions",
        listener.local_addr().unwrap()
    );
    let handle = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(1)))
            .unwrap();
        let mut reader = BufReader::new(stream);
        let mut size = 0;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).unwrap() == 0 {
                return;
            }
            if line.trim().is_empty() {
                break;
            }
            if let Some(value) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                size = value.trim().parse::<usize>().unwrap();
            }
        }
        let mut body = vec![0; size];
        reader.read_exact(&mut body).unwrap();
        let mut stream = reader.into_inner();
        if trickle {
            for byte in wire {
                if stream.write_all(&[byte]).is_err() {
                    break;
                }
                std::thread::sleep(Duration::from_millis(10));
            }
        } else {
            let _ = stream.write_all(&wire);
        }
    });
    (url, handle)
}
#[test]
fn fake_http_accepts_valid_json_with_all_supported_body_framings() {
    for wire in [
        b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}".to_vec(),
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\n{\"ok\":true}\r\n0\r\n\r\n"
            .to_vec(),
        b"HTTP/1.1 200 OK\r\n\r\n{\"ok\":true}".to_vec(),
    ] {
        let (url, server) = response_server(wire, false);
        assert_eq!(
            Http::new(Duration::from_secs(1))
                .post_json(&url, &json!({}))
                .unwrap(),
            json!({"ok":true})
        );
        server.join().unwrap();
    }
}
#[test]
fn response_caps_reject_content_length_chunked_and_eof_bodies() {
    let oversized = MAX_RESPONSE_BYTES + 1;
    let mut eof = b"HTTP/1.1 200 OK\r\n\r\n".to_vec();
    eof.extend(std::iter::repeat(b'x').take(oversized));
    for wire in [
        format!("HTTP/1.1 200 OK\r\nContent-Length: {oversized}\r\n\r\n").into_bytes(),
        format!("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n{oversized:x}\r\n")
            .into_bytes(),
        eof,
    ] {
        let (url, server) = response_server(wire, false);
        let error = Http::new(Duration::from_secs(1))
            .post_json(&url, &json!({}))
            .unwrap_err();
        assert!(error.contains("response exceeds"), "{error}");
        server.join().unwrap();
    }
}
#[test]
fn request_cap_is_checked_before_connection() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let error = Http::new(Duration::from_secs(1))
        .post_json(
            &format!("http://{}", listener.local_addr().unwrap()),
            &json!({"x":"x".repeat(MAX_REQUEST_BYTES)}),
        )
        .unwrap_err();
    assert!(error.contains("request exceeds"));
    assert_eq!(
        listener.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
}
#[test]
fn trickled_headers_cannot_extend_absolute_deadline() {
    let (url, server) = response_server(
        b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}".to_vec(),
        true,
    );
    let start = Instant::now();
    let error = Http::new(Duration::from_millis(65))
        .post_json(&url, &json!({}))
        .unwrap_err();
    assert!(
        error.contains("read") || error.contains("deadline"),
        "{error}"
    );
    assert!(start.elapsed() < Duration::from_millis(250));
    server.join().unwrap();
}
#[test]
fn lock_child() {
    let Ok(path) = std::env::var("FLEET_GUARD_TEST_LOCK") else {
        return;
    };
    let result = InferenceLease::acquire(std::path::Path::new(&path));
    if std::env::var("FLEET_GUARD_TEST_EXPECT_BUSY").as_deref() == Ok("1") {
        assert!(result.unwrap_err().contains("busy"));
    } else {
        assert!(result.is_ok());
    }
}
#[test]
fn inference_is_serialized_across_processes() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("inference.lock");
    let lease = InferenceLease::acquire(&path).unwrap();
    let run = |busy: bool| {
        Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "lock_child", "--test-threads=1"])
            .env("FLEET_GUARD_TEST_LOCK", &path)
            .env("FLEET_GUARD_TEST_EXPECT_BUSY", if busy { "1" } else { "0" })
            .output()
            .unwrap()
    };
    let denied = run(true);
    assert!(
        denied.status.success(),
        "{}",
        String::from_utf8_lossy(&denied.stdout)
    );
    drop(lease);
    let released = run(false);
    assert!(
        released.status.success(),
        "{}",
        String::from_utf8_lossy(&released.stdout)
    );
}

#[test]
fn controller_response_cap_and_trickle_deadline_close_the_connection() {
    use std::os::unix::net::UnixListener;
    for trickle in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("fleetd.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let mut controller = Some(fleet_proto::Client::connect(&path).unwrap());
        let worker = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream);
            let mut request = String::new();
            reader.read_line(&mut request).unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&request).unwrap()["op"],
                "snapshot"
            );
            let mut stream = reader.into_inner();
            if trickle {
                for byte in b"{\"ok\":true}\n" {
                    if stream.write_all(&[*byte]).is_err() {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(10));
                }
            } else {
                let _ = stream.write_all(&vec![b'x'; MAX_RESPONSE_BYTES + 1]);
            }
        });
        let start = Instant::now();
        let mut dispatcher = Dispatcher {
            client: &mut controller,
            socket_path: path,
        };
        let budget = if trickle {
            Duration::from_millis(65)
        } else {
            Duration::from_secs(1)
        };
        let error = dispatcher
            .call_read_only("fleet_ps", &json!({}), start + budget)
            .unwrap_err();
        if !trickle {
            assert!(error.to_string().contains("byte limit"), "{error}");
        }
        assert!(
            controller.is_none(),
            "partial response must not leak into later tool calls"
        );
        assert!(start.elapsed() < Duration::from_secs(2));
        worker.join().unwrap();
    }
}

#[test]
fn offline_endpoint_fails_without_any_retry_or_model_startup() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    drop(listener);
    let start = Instant::now();
    let error = Http::new(Duration::from_secs(15))
        .post_json(&url, &json!({}))
        .unwrap_err();
    assert!(error.contains("unavailable"), "{error}");
    assert!(start.elapsed() < Duration::from_millis(500));
}
