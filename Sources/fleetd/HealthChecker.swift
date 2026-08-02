import Foundation
import Darwin
import FleetCore

/// Application-level health checks. Deliberately separate from liveness: a pid that
/// exists and a port that listens prove nothing about the app behind them.
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

    /// Delegates to the shared probe in FleetCore so the app's connection checks
    /// and the daemon's health checks cannot drift apart.
    static func tcpConnect(host: String, port: Int, timeout: TimeInterval) -> Outcome {
        let result = TCPProbe.connect(host: host, port: port, timeout: timeout)
        return Outcome(passed: result.ok, detail: result.detail, latencyMs: result.latencyMs)
    }

    static func httpGet(_ url: URL, expect: Int, timeout: TimeInterval) -> Outcome {
        let start = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("FleetConsole/1.0 (health check)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome = Outcome(passed: false, detail: "no response", latencyMs: 0)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = Outcome(passed: false,
                                  detail: "GET \(url.absoluteString) failed: \(error.localizedDescription)",
                                  latencyMs: elapsed(start))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            outcome = Outcome(passed: status == expect,
                              detail: "GET \(url.path.isEmpty ? "/" : url.path) → \(status) (expected \(expect))",
                              latencyMs: elapsed(start))
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
            outcome = Outcome(passed: false, detail: "GET \(url.absoluteString) timed out", latencyMs: elapsed(start))
        }
        session.invalidateAndCancel()
        return outcome
    }

    private static func elapsed(_ start: Date) -> Double {
        Date().timeIntervalSince(start) * 1000
    }
}
