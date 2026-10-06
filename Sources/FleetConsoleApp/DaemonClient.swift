import Foundation
import FleetCore

/// Talks to fleetd over the local socket. The app is a client and a dashboard —
/// it never supervises the controller and never touches processes directly.
///
/// `@unchecked Sendable`: every stored property is behind `lock`; the request
/// queue is immutable. The subscription runs on its own `Thread`, so this really
/// is shared across threads.
final class DaemonClient: @unchecked Sendable {
    static let shared = DaemonClient()

    private let requestQueue = DispatchQueue(label: "com.fleetconsole.app.requests", attributes: .concurrent)

    private let lock = NSLock()
    private var subscribeThread: Thread?
    private var running = true

    /// Read every pass of the subscribe loop, written by `stop()` from the main
    /// thread. It is the only thing that ends that loop, so a missed write is a
    /// thread that never stops.
    private var shouldRun: Bool {
        lock.withLock { running }
    }

    /// Long-lived subscription with automatic reconnect. fleetd pushes a snapshot
    /// on every state change, so the UI never polls.
    ///
    /// The callbacks are `@MainActor` in the signature rather than by convention.
    /// Delivery goes through `DispatchQueue.main.async` rather than
    /// `Task { @MainActor }` because snapshots must be applied in arrival order,
    /// and the queue is FIFO where unstructured tasks are not.
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

    /// The one verb the Task Composer uses: hand the controller a supervised
    /// service. It is a request, not a command — the controller alone launches
    /// and reaps, and this reply carries the resulting `ServiceRecord`.
    func launch(_ request: LaunchRequest,
                completion: @escaping @MainActor (Result<RPCResponse, Error>) -> Void) {
        send(RPCRequest(op: .launch, launch: request), completion: completion)
    }

    /// Whether the launchd agent is registered, so the UI can tell "not installed"
    /// apart from "installed but down".
    func agentIsRegistered() -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(FleetPaths.agentLabel)"], timeout: 5)
        return result.succeeded
    }

    /// Hop to the main actor while keeping `DispatchQueue.main`'s FIFO ordering.
    /// The block is already on the main thread, so `assumeIsolated` states a fact
    /// rather than escaping a check.
    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}
