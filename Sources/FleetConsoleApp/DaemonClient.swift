import Foundation
import FleetCore

/// Talks to fleetd over the local socket. The app is a client and a dashboard —
/// it never supervises the controller and never touches processes directly.
final class DaemonClient {
    static let shared = DaemonClient()

    private let requestQueue = DispatchQueue(label: "com.fleetconsole.app.requests", attributes: .concurrent)
    private var subscribeThread: Thread?
    private var shouldRun = true

    /// Long-lived subscription with automatic reconnect. fleetd pushes a snapshot
    /// on every state change, so the UI never polls.
    func startSubscription(onSnapshot: @escaping (Snapshot) -> Void,
                           onConnection: @escaping (Bool, String?) -> Void) {
        let thread = Thread { [weak self] in
            guard let self else { return }
            var backoff: useconds_t = 500_000
            while self.shouldRun {
                do {
                    // timeout 0 = block indefinitely: this connection stays open.
                    let conn = try UnixSocketClient.connect(timeout: 0)
                    // Both the write and the reads below throw when fleetd restarts,
                    // and this loop reconnects forever — the fd has to go back on
                    // every exit path, not just the clean one.
                    defer { conn.close() }
                    try conn.writeJSON(RPCRequest(op: .subscribe))
                    DispatchQueue.main.async { onConnection(true, nil) }
                    backoff = 500_000
                    while self.shouldRun, let line = try conn.readLine() {
                        guard let response = try? Codec.decode(RPCResponse.self, from: line),
                              let snapshot = response.snapshot else { continue }
                        DispatchQueue.main.async { onSnapshot(snapshot) }
                    }
                    DispatchQueue.main.async { onConnection(false, "controller closed the connection") }
                } catch {
                    DispatchQueue.main.async { onConnection(false, error.localizedDescription) }
                }
                usleep(backoff)
                backoff = min(backoff * 2, 5_000_000)
            }
        }
        thread.name = "fleet.subscribe"
        thread.start()
        subscribeThread = thread
    }

    func stop() {
        shouldRun = false
    }

    func send(_ request: RPCRequest, timeout: TimeInterval = 30,
              completion: @escaping (Result<RPCResponse, Error>) -> Void) {
        requestQueue.async {
            do {
                let response = try UnixSocketClient.send(request, timeout: timeout)
                DispatchQueue.main.async {
                    if response.ok {
                        completion(.success(response))
                    } else {
                        completion(.failure(FleetError.rejected(response.error ?? "unknown error")))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Whether the launchd agent is registered, so the UI can tell "not installed"
    /// apart from "installed but down".
    func agentIsRegistered() -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(FleetPaths.agentLabel)"], timeout: 5)
        return result.succeeded
    }
}
