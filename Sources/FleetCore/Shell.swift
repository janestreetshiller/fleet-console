import Foundation

private final class DrainedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        defer { lock.unlock() }
        data = value
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public enum Shell {
    public struct Result {
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public var succeeded: Bool { status == 0 }
    }

    @discardableResult
    public static func run(_ executable: String, _ arguments: [String],
                           timeout: TimeInterval = 10) -> Result {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return Result(status: 127, stdout: "", stderr: "not executable: \(executable)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return Result(status: 126, stdout: "", stderr: "\(error)")
        }

        let outData = DrainedOutput(), errData = DrainedOutput()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "fleet.shell.drain", attributes: .concurrent)
        queue.async(group: group) { outData.set(outPipe.fileHandleForReading.readDataToEndOfFile()) }
        queue.async(group: group) { errData.set(errPipe.fileHandleForReading.readDataToEndOfFile()) }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        if group.wait(timeout: .now() + 2) == .timedOut {
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }

        return Result(status: process.terminationStatus,
                      stdout: String(data: outData.value, encoding: .utf8) ?? "",
                      stderr: String(data: errData.value, encoding: .utf8) ?? "")
    }

    public static func which(_ name: String, candidates: [String] = []) -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }
        let searchPath = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        for dir in searchPath {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
