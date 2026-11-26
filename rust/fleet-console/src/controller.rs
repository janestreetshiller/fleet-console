
use futures::channel::mpsc::UnboundedSender;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use crate::snapshot::Snapshot;
use crate::ShellEvent;

const BACKOFF_START: Duration = Duration::from_millis(500);
const BACKOFF_CAP: Duration = Duration::from_secs(5);

pub fn spawn(tx: UnboundedSender<ShellEvent>) {
    std::thread::spawn(move || {
        let path = fleet_proto::default_socket_path();
        let mut backoff = BACKOFF_START;
        while !tx.is_closed() {
            if UnixStream::connect(&path).is_ok_and(|stream| run_subscription(stream, &tx)) {
                backoff = BACKOFF_START;
            }
            if tx.is_closed() {
                return;
            }
            std::thread::sleep(backoff);
            backoff = (backoff * 2).min(BACKOFF_CAP);
        }
    });
}

fn run_subscription(mut stream: UnixStream, tx: &UnboundedSender<ShellEvent>) -> bool {
    let Ok(mut subscribe) = serde_json::to_vec(&fleet_proto::RpcRequest::new(
        fleet_proto::RpcOp::Subscribe,
    )) else {
        return false;
    };
    subscribe.push(b'\n');
    if stream.write_all(&subscribe).is_err() {
        return false;
    }

    let mut reader = BufReader::new(stream);
    let mut line = Vec::new();
    let mut live = false;
    loop {
        line.clear();
        if !matches!(reader.read_until(b'\n', &mut line), Ok(1..)) {
            break;
        }
        let Ok(response) = serde_json::from_slice::<fleet_proto::RpcResponse>(&line) else {
            continue;
        };
        if !response.ok {
            break;
        }
        let Some(snapshot_value) = response.snapshot.filter(serde_json::Value::is_object) else {
            continue;
        };
        let Ok(snapshot) = serde_json::from_value::<Snapshot>(snapshot_value) else {
            continue;
        };
        if !live {
            if tx.unbounded_send(ShellEvent::Connection(true)).is_err() {
                return false;
            }
            live = true;
        }
        if tx.unbounded_send(ShellEvent::Snapshot(snapshot)).is_err() {
            return live;
        }
    }
    if live {
        let _ = tx.unbounded_send(ShellEvent::Connection(false));
    }
    live
}

pub fn send_one_shot(request: &fleet_proto::RpcRequest) -> Result<fleet_proto::RpcResponse, ()> {
    let path = fleet_proto::default_socket_path();
    match fleet_proto::Client::connect(&path).and_then(|mut client| client.send(request)) {
        Ok(response) if response.ok => Ok(response),
        Ok(response) => {
            let reason = response.error.as_deref().unwrap_or("unknown error");
            eprintln!("FleetConsole: controller {:?} rejected: {reason}", request.op);
            Err(())
        }
        Err(error) => {
            eprintln!("FleetConsole: controller {:?} failed: {error}", request.op);
            Err(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn exchange(replies: &[u8]) -> (bool, Vec<ShellEvent>) {
        let (client, daemon) = UnixStream::pair().unwrap();
        for stream in [&client, &daemon] {
            stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
            stream.set_write_timeout(Some(Duration::from_secs(2))).unwrap();
        }

        let (tx, rx) = futures::channel::mpsc::unbounded();
        let live = std::thread::scope(|scope| {
            let daemon = scope.spawn(move || {
                let mut daemon = BufReader::new(daemon);
                let mut request = String::new();
                daemon.read_line(&mut request).unwrap();
                assert!(request.ends_with('\n'));
                let request: fleet_proto::RpcRequest = serde_json::from_str(&request).unwrap();
                assert_eq!(request.op, fleet_proto::RpcOp::Subscribe);
                daemon.get_mut().write_all(replies).unwrap();
            });
            let live = run_subscription(client, &tx);
            daemon.join().unwrap();
            live
        });
        drop(tx);
        (live, futures::executor::block_on_stream(rx).collect())
    }

    fn reply(ok: bool) -> String {
        const SNAPSHOT: &str = r#"{"generatedAt":1000,"daemon":{"version":"1.3.0","pid":7,"startedAt":400,"tickIntervalSec":5,"socketPath":"/tmp/fleet.sock"},"services":[],"unmanaged":[],"devices":[],"attention":[],"recentEvents":[],"messages":[],"external":[],"sessions":[]}"#;
        format!("{{\"ok\":{ok},\"snapshot\":{SNAPSHOT}}}\n")
    }

    #[test]
    fn subscription_without_a_valid_snapshot_never_becomes_live() {
        for replies in [
            b"".as_slice(),
            b"\xff\nnot json\n{\"snapshot\":{}}\n{\"ok\":true}\n{\"ok\":true,\"snapshot\":{}}\n",
        ] {
            let (live, events) = exchange(replies);
            assert!(!live);
            assert!(events.is_empty());
        }
    }

    #[test]
    fn rejected_subscription_does_not_accept_snapshots() {
        let replies = format!("{}{}", reply(false), reply(true));
        let (live, events) = exchange(replies.as_bytes());
        assert!(!live);
        assert!(events.is_empty());
    }

    #[test]
    fn accepted_snapshots_connect_once_and_eof_disconnects_once() {
        let valid = reply(true);
        let replies = format!("not json\n{valid}{valid}");
        let (live, events) = exchange(replies.as_bytes());
        assert!(live);
        assert!(matches!(
            events.as_slice(),
            [
                ShellEvent::Connection(true),
                ShellEvent::Snapshot(first),
                ShellEvent::Snapshot(second),
                ShellEvent::Connection(false),
            ] if first.daemon.pid == 7 && second.generated_at == 1_000.0
        ));
    }
}
