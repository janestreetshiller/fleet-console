import Foundation

// One `orcs` invocation, and the pipe discipline that keeps it from leaking.
//
// The app spawns a process per request and lets the wrapper decide whether to
// reuse a running server. It never runs `orcs serve`, never binds a port and
// never manages a model's lifecycle — which is what lets a local model live in
// this window without making README's "no network listener, no telemetry" line
// a lie.
//
// The reads are `DispatchSource`-driven rather than two threads parked in
// `readDataToEndOfFile()`. `Shell.run` has to unblock its drain threads by
// closing the read ends underneath them: correct, but it leaves a window where a
// blocked reader holds a descriptor another thread is closing, and
// `readDataToEndOfFile` raises an Objective-C exception on `EBADF` rather than
// returning. A non-blocking read source never parks, so EOF, timeout and
// cancellation all converge on the same teardown: cancel the source, close the
// descriptor exactly once in its cancel handler.

/// What a finished — or abandoned — invocation produced.
struct OrcsRun: Sendable {
    enum Outcome: Equatable, Sendable {
        case exited(Int32)
        case timedOut
        case cancelled
        /// The binary could not be started at all; carries the reason verbatim.
        case spawnFailed(String)
    }

    var outcome: Outcome
    var stdout: String
    var stderr: String
    var duration: TimeInterval

    var succeeded: Bool { outcome == .exited(0) }
}

enum OrcsProcess {
    /// Runs `orcs` to completion off the main actor.
    ///
    /// The prompt travels as an argv element, never through a shell, so a
    /// subject name containing a backtick or a quote is text and cannot become a
    /// command. `onOutput` and `onDiagnostics` are called with everything read so
    /// far rather than the latest chunk — a chunk boundary can fall inside a
    /// UTF-8 sequence, and re-decoding the whole buffer is both cheaper than
    /// carrying a partial-sequence decoder and always well-formed.
    ///
    /// Both callbacks fire on a private serial queue; a main-actor caller has to
    /// hop for itself.
    static func run(executable: String,
                    arguments: [String],
                    workingDirectory: URL? = nil,
                    timeout: TimeInterval,
                    onOutput: (@Sendable (String) -> Void)? = nil,
                    onDiagnostics: (@Sendable (String) -> Void)? = nil) async -> OrcsRun {
        let invocation = OrcsInvocation(executable: executable,
                                       arguments: arguments,
                                       workingDirectory: workingDirectory,
                                       timeout: timeout,
                                       onOutput: onOutput,
                                       onDiagnostics: onDiagnostics)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                invocation.start { continuation.resume(returning: $0) }
            }
        } onCancel: {
            // Cancelling the Task must reach the child, or a 4B model keeps
            // burning the GPU for a question nobody is waiting on any more.
            invocation.cancel()
        }
    }
}

// MARK: - Invocation

/// One child process and its two pipes.
///
/// Every mutable field is touched only from `queue`, which is serial — that, and
/// not a lock, is what makes the `@unchecked Sendable` below true. `start`,
/// `cancel` and both dispatch-source handlers all funnel through it.
private final class OrcsInvocation: @unchecked Sendable {
    /// How long to keep draining after the child exits. A grandchild that
    /// inherited the write ends would hold EOF hostage forever, so the wait for
    /// it is bounded rather than trusted.
    private static let drainGrace: TimeInterval = 0.5
    /// SIGTERM to SIGKILL. `orcs` runs inference in-process and spawns nothing,
    /// so terminating the child is terminating the tree.
    private static let killGrace: TimeInterval = 1.0
    private static let readBufferSize = 16 * 1024

    private let queue = DispatchQueue(label: "com.fleetconsole.interpreter.orcs")
    private let executable: String
    private let arguments: [String]
    private let workingDirectory: URL?
    private let timeout: TimeInterval
    private let onOutput: (@Sendable (String) -> Void)?
    private let onDiagnostics: (@Sendable (String) -> Void)?

    private var process: Process?
    private var completion: (@Sendable (OrcsRun) -> Void)?
    private var sources: [DispatchSourceRead] = []
    private var openDescriptors = 0
    private var stdoutData = Data()
    private var stderrData = Data()
    private var exited = false
    private var status: Int32 = 0
    /// Set by timeout or cancellation; wins over the child's own exit status,
    /// because a process we killed did not "exit 143 for reasons of its own".
    private var override: OrcsRun.Outcome?
    private var cancelRequested = false
    private var timeoutItem: DispatchWorkItem?
    private var startedAt = Date()

    init(executable: String, arguments: [String], workingDirectory: URL?,
         timeout: TimeInterval, onOutput: (@Sendable (String) -> Void)?,
         onDiagnostics: (@Sendable (String) -> Void)?) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.onOutput = onOutput
        self.onDiagnostics = onDiagnostics
    }

    func start(completion: @escaping @Sendable (OrcsRun) -> Void) {
        queue.async { self.begin(completion) }
    }

    func cancel() {
        queue.async {
            self.cancelRequested = true
            self.abort(.cancelled)
        }
    }

    // MARK: Spawn

    private func begin(_ completion: @escaping @Sendable (OrcsRun) -> Void) {
        self.completion = completion
        startedAt = Date()

        // A Task cancelled before its body ran leaves the flag set, so the
        // process must not be spawned at all.
        guard !cancelRequested else { return finish(.cancelled) }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return finish(.spawnFailed("not executable: \(executable)"))
        }

        var outPipe = [Int32](repeating: -1, count: 2)
        var errPipe = [Int32](repeating: -1, count: 2)
        guard pipe(&outPipe) == 0 else {
            return finish(.spawnFailed("pipe() failed: \(String(cString: strerror(errno)))"))
        }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            return finish(.spawnFailed("pipe() failed: \(String(cString: strerror(errno)))"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        // Nothing to say on stdin, and a model wrapper that decided to read it
        // would otherwise hang until the timeout.
        process.standardInput = FileHandle.nullDevice
        // `closeOnDealloc: false` on both: these four descriptors are ours, and
        // each one is closed on exactly one path below. Handing that ownership
        // to a FileHandle's deinit as well is how a double close happens.
        process.standardOutput = FileHandle(fileDescriptor: outPipe[1], closeOnDealloc: false)
        process.standardError = FileHandle(fileDescriptor: errPipe[1], closeOnDealloc: false)
        process.terminationHandler = { [weak self] process in
            // Bind once and read the status here. The previous spelling reached
            // through `self?` a second time *inside* the queue block, which meant
            // two separate loads of a weak reference that could differ, and left
            // `process` being touched from the queue rather than from the handler
            // that owns it.
            guard let self else { return }
            let status = process.terminationStatus
            self.queue.async { self.handleExit(status) }
        }

        do {
            try process.run()
        } catch {
            for descriptor in [outPipe[0], outPipe[1], errPipe[0], errPipe[1]] { close(descriptor) }
            return finish(.spawnFailed("\(error)"))
        }
        self.process = process

        // The child holds its own dup of each write end. Ours has to go, or the
        // read ends never see EOF and every request waits out the timeout.
        close(outPipe[1])
        close(errPipe[1])

        attach(descriptor: outPipe[0], toStdout: true)
        attach(descriptor: errPipe[0], toStdout: false)

        let item = DispatchWorkItem { [weak self] in self?.abort(.timedOut) }
        timeoutItem = item
        queue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    // MARK: Draining

    private func attach(descriptor: Int32, toStdout: Bool) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL, 0) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    self.accept(Data(buffer[0..<count]), toStdout: toStdout)
                    continue
                }
                if count == 0 { return source.cancel() }        // EOF
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return source.cancel()                          // EBADF and friends
            }
        }
        source.setCancelHandler { [weak self] in
            close(descriptor)
            self?.descriptorClosed()
        }
        sources.append(source)
        openDescriptors += 1
        source.resume()
    }

    private func accept(_ data: Data, toStdout: Bool) {
        if toStdout {
            stdoutData.append(data)
            onOutput?(String(decoding: stdoutData, as: UTF8.self))
        } else {
            stderrData.append(data)
            onDiagnostics?(String(decoding: stderrData, as: UTF8.self))
        }
    }

    private func descriptorClosed() {
        openDescriptors -= 1
        finishIfDrained()
    }

    private func cancelSources() {
        for source in sources { source.cancel() }
        sources = []
    }

    // MARK: Exit paths

    private func handleExit(_ status: Int32) {
        exited = true
        self.status = status
        queue.asyncAfter(deadline: .now() + Self.drainGrace) { [weak self] in
            // Whatever is still holding a write end is not the child any more.
            self?.cancelSources()
        }
        finishIfDrained()
    }

    /// Timeout or cancellation: ask, then insist.
    private func abort(_ outcome: OrcsRun.Outcome) {
        guard completion != nil else { return }
        override = outcome
        if let process, process.isRunning { process.terminate() }
        queue.asyncAfter(deadline: .now() + Self.killGrace) { [weak self] in self?.hardStop() }
    }

    private func hardStop() {
        guard completion != nil else { return }
        // Guarded on `isRunning` because Foundation has already reaped an exited
        // child, and a signal to a recycled pid is the one mistake this codebase
        // refuses to make anywhere else either.
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        exited = true
        cancelSources()
        finishIfDrained()
    }

    private func finishIfDrained() {
        guard exited, openDescriptors == 0 else { return }
        finish(override ?? .exited(status))
    }

    private func finish(_ outcome: OrcsRun.Outcome) {
        guard let completion else { return }
        self.completion = nil
        timeoutItem?.cancel()
        timeoutItem = nil
        completion(OrcsRun(outcome: outcome,
                           stdout: String(decoding: stdoutData, as: UTF8.self),
                           stderr: String(decoding: stderrData, as: UTF8.self),
                           duration: Date().timeIntervalSince(startedAt)))
    }

    deinit {
        // Nothing should be open here — `finish` is only reached once both
        // descriptors are closed — but a source left resumed would keep its
        // descriptor alive past this object, so it is cancelled unconditionally.
        for source in sources { source.cancel() }
    }
}
