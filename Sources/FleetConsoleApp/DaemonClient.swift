import Foundation
import FleetCore

final class DaemonClient: @unchecked Sendable {
    static let shared = DaemonClient()

    let requestPolicy: RPCRequestPolicy
    let socketPath: String

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if FLEET_SURFACE_RENDERER
        let reviewSocket = Bundle.main.object(forInfoDictionaryKey: "FleetConsoleVerificationDaemonSocket") as? String
        requestPolicy = arguments.contains(SurfaceRenderer.flag) || reviewSocket != nil
            ? .observational : RPCRequestPolicy.forArguments(arguments)
        socketPath = reviewSocket ?? RPCRequestPolicy.daemonSocketPath(forArguments: arguments,
                                                                      surfaceRenderer: true)
        #else
        requestPolicy = RPCRequestPolicy.forArguments(arguments)
        socketPath = FleetPaths.socket.path
        #endif
    }

    private let requestQueue = DispatchQueue(label: "com.fleetconsole.app.requests", attributes: .concurrent)

    private let lock = NSLock()
    private var subscribeThread: Thread?
    private var running = true
    private var observationalOperations: Set<String> = []

    var submittedObservationalOperations: [String] {
        lock.withLock { observationalOperations.sorted() }
    }

    private func record(_ operation: RPCOp) {
        guard requestPolicy == .observational else { return }
        lock.withLock { _ = observationalOperations.insert(operation.rawValue) }
    }

    private var shouldRun: Bool {
        lock.withLock { running }
    }

    func startSubscription(onSnapshot: @escaping @MainActor (Snapshot) -> Void,
                           onConnection: @escaping @MainActor (Bool, String?) -> Void) {
        #if FLEET_SURFACE_RENDERER
        if ProcessInfo.processInfo.arguments.contains(SurfaceRenderer.flag) { return }
        #endif
        let thread = Thread { [weak self] in
            guard let self else { return }
            var backoff: useconds_t = 500_000
            while self.shouldRun {
                do {
                    let conn = try UnixSocketClient.connect(path: self.socketPath, timeout: 0)
                    defer { conn.close() }
                    try conn.writeJSON(RPCRequest(op: .subscribe))
                    self.record(.subscribe)
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
        #if FLEET_SURFACE_RENDERER
        if ProcessInfo.processInfo.arguments.contains(SurfaceRenderer.flag), request.op == .snapshot {
            Self.onMain { completion(.failure(FleetError.rejected("Live snapshots are disabled in fixture capture."))) }
            return
        }
        #endif
        guard requestPolicy.allows(request.op) else {
            Self.onMain {
                completion(.failure(FleetError.rejected(
                    "\(request.op.rawValue) is not permitted in observational mode"
                )))
            }
            return
        }
        record(request.op)
        requestQueue.async { [self] in
            do {
                let response = try UnixSocketClient.send(request, path: socketPath,
                                                         timeout: timeout, policy: requestPolicy)
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

    func launch(_ request: LaunchRequest,
                completion: @escaping @MainActor (Result<RPCResponse, Error>) -> Void) {
        send(RPCRequest(op: .launch, launch: request), completion: completion)
    }

    func agentIsRegistered() -> Bool {
        let result = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(FleetPaths.agentLabel)"], timeout: 5)
        return result.succeeded
    }

    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}
