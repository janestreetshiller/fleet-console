import Foundation
import FleetCore

/// Talks to fleetd over the local socket. The app is a client and a dashboard —
/// it never supervises the controller and never touches processes directly.
///
/// `@unchecked Sendable`, earned: every stored property is behind `lock`, and the
/// only other state is the request queue, which is immutable. The subscription
/// runs on its own `Thread` rather than a task, so the class genuinely is shared
/// across threads and `shouldRun` genuinely is read by one while written by
/// another — see `stop()`.
final class DaemonClient: @unchecked Sendable {
    static let shared = DaemonClient()

    private let requestQueue = DispatchQueue(label: "com.fleetconsole.app.requests", attributes: .concurrent)

    private let lock = NSLock()
    private var subscribeThread: Thread?
    private var running = true

    /// Read on every pass of the subscribe loop and written by `stop()` from the
    /// main thread. It was a plain `Bool` before, which is a torn read waiting to
    /// happen and the reason the loop could miss a shutdown: the flag is the only
    /// thing that ends it.
    private var shouldRun: Bool {
        lock.withLock { running }
    }

    /// Long-lived subscription with automatic reconnect. fleetd pushes a snapshot
    /// on every state change, so the UI never polls.
    ///
    /// The callbacks are `@MainActor` in the signature rather than by convention —
    /// they mutate `AppModel`, which is main-actor isolated, and the previous
    /// signature left that as something each call site had to remember. They are
    /// delivered through `DispatchQueue.main.async` rather than `Task { @MainActor }`
    /// deliberately: snapshots have to be applied in arrival order, and the queue
    /// is FIFO where a series of unstructured tasks is not.
    func startSubscription(onSnapshot: @escaping @MainActor (Snapshot) -> Void,
                           onConnection: @escaping @MainActor (Bool, String?) -> Void) {
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
                    Self.onMain { onConnection(true, nil) }
                    backoff = 500_000
                    while self.shouldRun, let line = try conn.readLine() {
                        guard let response = try? Codec.decode(RPCResponse.self, from: line),
                              let snapshot = response.snapshot else { continue }
                        Self.onMain { onSnapshot(snapshot) }
                    }
                    Self.onMain { onConnection(false, "controller closed the connection") }
                } catch {
                    let message = error.localizedDescription
                    Self.onMain { onConnection(false, message) }
                }
                usleep(backoff)
                backoff = min(backoff * 2, 5_000_000)
            }
        }
        thread.name = "fleet.subscribe"
        thread.start()
        lock.withLock { subscribeThread = thread }
    }

    func stop() {
        lock.withLock { running = false }
    }

    func send(_ request: RPCRequest, timeout: TimeInterval = 30,
              completion: @escaping @MainActor (Result<RPCResponse, Error>) -> Void) {
        requestQueue.async {
            do {
                let response = try UnixSocketClient.send(request, timeout: timeout)
                Self.onMain {
                    if response.ok {
                        completion(.success(response))
                    } else {
                        completion(.failure(FleetError.rejected(response.error ?? "unknown error")))
                    }
                }
            } catch {
                Self.onMain { completion(.failure(error)) }
            }
        }
    }

    /// Whether the launchd agent is registered, so the UI can tell "not installed"
    /// apart from "installed but down".
    func agentIsRegistered() -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(FleetPaths.agentLabel)"], timeout: 5)
        return result.succeeded
    }

    /// Hop to the main actor while keeping `DispatchQueue.main`'s ordering.
    ///
    /// `assumeIsolated` inside `main.async` is the honest spelling of what this code
    /// has always done: the block is already on the main thread, so the assumption is
    /// a statement of fact rather than an escape hatch, and it buys FIFO delivery
    /// that `Task { @MainActor }` does not promise.
    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}
