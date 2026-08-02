import Foundation
import Darwin

/// One TCP reachability implementation, shared by the daemon's health checks and
/// the app's connection probes so the two can never disagree about what
/// "reachable" means.
public enum TCPProbe {
    public struct Result: Sendable {
        public var ok: Bool
        public var detail: String
        public var latencyMs: Double
    }

    /// Non-blocking connect + select, so the timeout is real rather than whatever
    /// the kernel's default happens to be.
    public static func connect(host: String, port: Int, timeout: TimeInterval = 3) -> Result {
        let start = Date()
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let list = info else {
            return Result(ok: false, detail: "cannot resolve \(host)", latencyMs: elapsed(start))
        }
        defer { freeaddrinfo(list) }

        var node: UnsafeMutablePointer<addrinfo>? = list
        var lastError = "connection refused"
        while let candidate = node {
            let fd = socket(candidate.pointee.ai_family, candidate.pointee.ai_socktype, candidate.pointee.ai_protocol)
            if fd >= 0 {
                var flags = fcntl(fd, F_GETFL, 0)
                flags |= O_NONBLOCK
                _ = fcntl(fd, F_SETFL, flags)
                let rc = Darwin.connect(fd, candidate.pointee.ai_addr, candidate.pointee.ai_addrlen)
                if rc == 0 {
                    close(fd)
                    return Result(ok: true, detail: "tcp connect to \(host):\(port) succeeded",
                                  latencyMs: elapsed(start))
                }
                if errno == EINPROGRESS {
                    var writeSet = fd_set()
                    fdZero(&writeSet)
                    guard fdSet(fd, &writeSet) else {
                        close(fd)
                        return Result(ok: false,
                                      detail: "cannot probe \(host):\(port): descriptor \(fd) is above select's 1024 limit",
                                      latencyMs: elapsed(start))
                    }
                    var tv = timeval(tv_sec: Int(timeout),
                                     tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
                    if select(fd + 1, nil, &writeSet, nil, &tv) > 0 {
                        var soError: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                        close(fd)
                        if soError == 0 {
                            return Result(ok: true, detail: "tcp connect to \(host):\(port) succeeded",
                                          latencyMs: elapsed(start))
                        }
                        lastError = String(cString: strerror(soError))
                    } else {
                        close(fd)
                        lastError = "timed out after \(Int(timeout))s"
                    }
                } else {
                    lastError = String(cString: strerror(errno))
                    close(fd)
                }
            }
            node = candidate.pointee.ai_next
        }
        return Result(ok: false, detail: "tcp connect to \(host):\(port) failed: \(lastError)",
                      latencyMs: elapsed(start))
    }

    private static func elapsed(_ start: Date) -> Double {
        Date().timeIntervalSince(start) * 1000
    }
}

// fd_set manipulation is not exposed to Swift; these are the standard shims.
// Darwin's fd_set is 1024 bits held as 32 Int32 words.
let fdSetWords = 32

func fdZero(_ set: inout fd_set) {
    _ = withUnsafeMutableBytes(of: &set.fds_bits) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
}

/// Returns false when the descriptor is outside the fixed 1024-bit map, which
/// `select` cannot represent — the caller has to report that as a probe failure
/// rather than write past the end of the set.
@discardableResult
func fdSet(_ fd: Int32, _ set: inout fd_set) -> Bool {
    guard fd >= 0, Int(fd) < fdSetWords * 32 else { return false }
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    // Bit 31 is Int32's sign bit, so `Int32(1 << 31)` traps on "not enough bits";
    // build the mask unsigned and reinterpret it.
    let mask = Int32(bitPattern: UInt32(1) << UInt32(bitOffset))
    withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: fdSetWords) { bits in
            bits[intOffset] |= mask
        }
    }
    return true
}
