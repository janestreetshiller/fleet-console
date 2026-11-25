// Controller connection: a dedicated thread that subscribes to fleetd over
// its owner-only Unix socket and streams snapshots into the shell, with the
// Swift reconnect policy (DaemonClient.swift): backoff starts at 0.5s,
// doubles on each failure, and caps at 5s; a successful subscribe resets it.
// One-shot requests (markSeen, refreshDevices, service actions) use short
// separate connections, exactly like the Swift UnixSocketClient.send path.

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
        loop {
            match run_subscription(&path, &tx) {
                Ok(reset) => {
                    if reset {
                        backoff = BACKOFF_START;
                    }
                }
                Err(()) => {}
            }
            if tx.unbounded_send(ShellEvent::Connection(false)).is_err() {
                return;
            }
            std::thread::sleep(backoff);
            backoff = (backoff * 2).min(BACKOFF_CAP);
        }
    });
}

/// Runs one subscription until the stream ends or fails. Returns Ok(true)
/// when the subscribe itself succeeded (so the caller resets the backoff).
fn run_subscription(
    path: &std::path::Path,
    tx: &UnboundedSender<ShellEvent>,
) -> Result<bool, ()> {
    let stream = UnixStream::connect(path).map_err(|_| ())?;
    let mut writer = stream.try_clone().map_err(|_| ())?;
    let subscribe = fleet_proto::Client::encode(&fleet_proto::RpcRequest::new(
        fleet_proto::RpcOp::Subscribe,
    ));
    writer
        .write_all(subscribe.as_bytes())
        .and_then(|_| writer.write_all(b"\n"))
        .and_then(|_| writer.flush())
        .map_err(|_| ())?;
    if tx.unbounded_send(ShellEvent::Connection(true)).is_err() {
        return Ok(true);
    }
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    loop {
        line.clear();
        let read = reader.read_line(&mut line).map_err(|_| ())?;
        if read == 0 {
            return Ok(true);
        }
        let Ok(response) = serde_json::from_str::<fleet_proto::RpcResponse>(&line) else {
            continue;
        };
        let Some(snapshot_value) = response.snapshot else {
            continue;
        };
        let Ok(snapshot) = serde_json::from_value::<Snapshot>(snapshot_value) else {
            continue;
        };
        if tx.unbounded_send(ShellEvent::Snapshot(snapshot)).is_err() {
            return Ok(true);
        }
    }
}

/// Sends one request on a short-lived connection and returns the response.
/// Used for fire-and-forget ops whose result the subscription will reflect.
pub fn send_one_shot(request: &fleet_proto::RpcRequest) -> Result<fleet_proto::RpcResponse, ()> {
    let path = fleet_proto::default_socket_path();
    let mut client = fleet_proto::Client::connect(&path).map_err(|_| ())?;
    client.send(request).map_err(|_| ())
}
