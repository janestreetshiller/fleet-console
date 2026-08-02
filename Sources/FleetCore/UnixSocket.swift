import Foundation
import Darwin

// macOS peer-credential lookup constants (sys/socket.h, sys/un.h).
private let kSOL_LOCAL: Int32 = 0
private let kLOCAL_PEERCRED: Int32 = 0x001

private func makeSockaddr(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else {
        throw FleetError.io("socket path too long (\(bytes.count) >= \(capacity)): \(path)")
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return addr
}

private func posixError(_ context: String) -> FleetError {
    .io("\(context): \(String(cString: strerror(errno))) (errno \(errno))")
}

/// One accepted connection. Framing is newline-delimited JSON.
/// `@unchecked Sendable`, earned rather than asserted. Two disciplines make it
/// true, and they are different disciplines: `buffer` is touched only by
/// `readLine`/`takeRemainder`, which run on the one thread that owns this
/// connection (`SocketServer` starts exactly one per accept); `closed` and every
/// write are serialised by `writeLock`, because the broadcast path writes from the
/// controller's queue while that owning thread is parked in `read`.
public final class SocketConnection: @unchecked Sendable {
    public let fd: Int32
    public let peerUID: uid_t
    private var buffer = Data()
    private var closed = false
    private let writeLock = NSLock()

    init(fd: Int32, peerUID: uid_t) {
        self.fd = fd
        self.peerUID = peerUID
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // Without a send timeout a subscriber that stops draining wedges writeLine
        // forever. 5s is one daemon tick: a peer that far behind gets dropped.
        var sndTimeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sndTimeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Backstop for callers that drop the connection on an error path; `close()`
    /// is idempotent so this cannot double-close a reissued descriptor.
    deinit {
        close()
    }

    /// Blocking read of one newline-terminated message. nil = peer closed.
    public func readLine() throws -> Data? {
        while true {
            if let idx = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<idx]
                buffer.removeSubrange(buffer.startIndex...idx)
                if line.isEmpty { continue }
                return Data(line)
            }
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            let n = read(fd, &chunk, chunk.count)
            if n == 0 { return buffer.isEmpty ? nil : takeRemainder() }
            if n < 0 {
                if errno == EINTR { continue }
                throw posixError("read")
            }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > 8 * 1024 * 1024 {
                throw FleetError.io("message exceeds 8 MB, dropping connection")
            }
        }
    }

    private func takeRemainder() -> Data? {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? nil : buffer
    }

    public func writeLine(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { throw FleetError.io("connection closed") }
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { raw in
            var offset = 0
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while offset < payload.count {
                let n = write(fd, base + offset, payload.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw posixError("write")
                }
                offset += n
            }
        }
    }

    public func writeJSON<T: Encodable>(_ value: T) throws {
        try writeLine(try Codec.encode(value))
    }

    public func close() {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }

    public var isClosed: Bool {
        writeLock.lock()
        defer { writeLock.unlock() }
        return closed
    }
}

/// Listening socket. Created 0600 inside a 0700 directory; every accepted peer's
/// euid is verified against ours before a single byte is read (threat model T5).
public final class UnixSocketServer {
    private let path: String
    private var listenFD: Int32 = -1
    private let uid = geteuid()

    public var onRejectedPeer: ((uid_t) -> Void)?

    public init(path: String) {
        self.path = path
    }

    public func start(backlog: Int32 = 32) throws {
        try FleetPaths.ensureDirectories()
        // A stale socket file from a crash would block bind(); it is safe to remove
        // because we already verified no live daemon answers on it (see probeAlive).
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = try makeSockaddr(path)
        let previousMask = umask(0o177)  // resulting socket file is 0600
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw posixError("bind \(path)")
        }
        chmod(path, 0o600)
        guard listen(fd, backlog) == 0 else {
            Darwin.close(fd)
            throw posixError("listen")
        }
        listenFD = fd
    }

    /// Blocking accept loop. Each accepted connection is handed to `handler` on its
    /// own thread; the handler owns closing it.
    public func run(handler: @escaping @Sendable (SocketConnection) -> Void) {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if listenFD < 0 { break }
                usleep(50_000)
                continue
            }
            guard let peer = Self.peerUID(of: clientFD) else {
                Darwin.close(clientFD)
                continue
            }
            guard peer == uid else {
                onRejectedPeer?(peer)
                Darwin.close(clientFD)
                continue
            }
            let conn = SocketConnection(fd: clientFD, peerUID: peer)
            let thread = Thread { handler(conn) }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    public func stop() {
        if listenFD >= 0 {
            let fd = listenFD
            listenFD = -1
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        unlink(path)
    }

    static func peerUID(of fd: Int32) -> uid_t? {
        var cred = xucred()
        var len = socklen_t(MemoryLayout<xucred>.size)
        let rc = withUnsafeMutablePointer(to: &cred) { ptr -> Int32 in
            getsockopt(fd, kSOL_LOCAL, kLOCAL_PEERCRED, ptr, &len)
        }
        guard rc == 0 else { return nil }
        return cred.cr_uid
    }
}

/// Blocking client used by fleetctl and by the app's background connections.
public enum UnixSocketClient {
    public static func connect(path: String = FleetPaths.socket.path,
                               timeout: TimeInterval = 5) throws -> SocketConnection {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = try makeSockaddr(path)
        let rc = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            Darwin.close(fd)
            throw FleetError.daemonUnavailable("cannot connect to \(path): \(String(cString: strerror(errno)))")
        }
        return SocketConnection(fd: fd, peerUID: geteuid())
    }

    /// One request, one response. Used for every non-streaming operation.
    public static func send(_ request: RPCRequest,
                            path: String = FleetPaths.socket.path,
                            timeout: TimeInterval = 15) throws -> RPCResponse {
        let conn = try connect(path: path, timeout: timeout)
        defer { conn.close() }
        try conn.writeJSON(request)
        guard let line = try conn.readLine() else {
            throw FleetError.daemonUnavailable("controller closed the connection without replying")
        }
        return try Codec.decode(RPCResponse.self, from: line)
    }

    /// Cheap liveness probe used before removing a stale socket file.
    public static func probeAlive(path: String = FleetPaths.socket.path) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return (try? send(RPCRequest(op: .ping), path: path, timeout: 2))?.ok == true
    }
}
