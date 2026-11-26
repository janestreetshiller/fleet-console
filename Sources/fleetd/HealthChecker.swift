import Foundation
import Darwin
import FleetCore

enum HealthChecker {

    struct Outcome {
        var passed: Bool
        var detail: String
        var latencyMs: Double
    }

    static func check(_ spec: HealthSpec) -> Outcome? {
        switch spec.kind {
        case .none:
            return nil
        case .tcp:
            guard let target = spec.target, let (host, port) = splitHostPort(target) else {
                return Outcome(passed: false, detail: "malformed tcp target '\(spec.target ?? "")'", latencyMs: 0)
            }
            return tcpConnect(host: host, port: port, timeout: spec.timeoutSec)
        case .http:
            guard let target = spec.target, let url = URL(string: target) else {
                return Outcome(passed: false, detail: "malformed url '\(spec.target ?? "")'", latencyMs: 0)
            }
            return httpGet(url, expect: spec.expectStatus, timeout: spec.timeoutSec)
        }
    }

    static func splitHostPort(_ target: String) -> (String, Int)? {
        guard let idx = target.lastIndex(of: ":"),
              let port = Int(target[target.index(after: idx)...]) else { return nil }
        var host = String(target[target.startIndex..<idx])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return (host.isEmpty ? "127.0.0.1" : host, port)
    }

    static func tcpConnect(host: String, port: Int, timeout: TimeInterval) -> Outcome {
        let result = TCPProbe.connect(host: host, port: port, timeout: timeout)
        return Outcome(passed: result.ok, detail: result.detail, latencyMs: result.latencyMs)
    }

    static func isLoopbackHTTP(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    static func httpGet(_ url: URL, expect: Int, timeout: TimeInterval) -> Outcome {
        guard isLoopbackHTTP(url) else {
            return Outcome(passed: false, detail: "HTTP health checks must target localhost", latencyMs: 0)
        }
        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("FleetConsole/1.0 (health check)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        let settled = SettledOutcome()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: LoopbackRedirects.shared, delegateQueue: nil)
        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error {
                settled.settle(Outcome(passed: false,
                                       detail: "GET \(url.absoluteString) failed: \(error.localizedDescription)",
                                       latencyMs: elapsed(start)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            settled.settle(Outcome(passed: status == expect,
                                   detail: "GET \(url.path.isEmpty ? "/" : url.path) → \(status) (expected \(expect))",
                                   latencyMs: elapsed(start)))
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1) == .timedOut {
            settled.settle(Outcome(passed: false,
                                   detail: "GET \(url.absoluteString) timed out",
                                   latencyMs: elapsed(start)))
            task.cancel()
        }
        session.invalidateAndCancel()
        return settled.resolved(or: Outcome(passed: false, detail: "no response", latencyMs: elapsed(start)))
    }

    private final class LoopbackRedirects: NSObject, URLSessionTaskDelegate {
        static let shared = LoopbackRedirects()

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url.map(HealthChecker.isLoopbackHTTP) == true ? request : nil)
        }
    }

    private final class SettledOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Outcome?

        func settle(_ outcome: Outcome) {
            lock.lock()
            defer { lock.unlock() }
            guard value == nil else { return }
            value = outcome
        }

        func resolved(or fallback: Outcome) -> Outcome {
            lock.lock()
            defer { lock.unlock() }
            return value ?? fallback
        }
    }

    private static func elapsed(_ start: Date) -> Double {
        Date().timeIntervalSince(start) * 1000
    }
}
