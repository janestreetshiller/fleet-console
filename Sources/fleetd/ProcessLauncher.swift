import Foundation
import Darwin
import FleetCore

enum ProcessLauncher {

    struct Spawned {
        var pid: Int32
        var pgid: Int32
        var startSignature: String?
        var stdoutPath: String
        var stderrPath: String
    }

    static func validate(_ request: LaunchRequest, config: FleetConfig) throws -> (argv: [String], cwd: String) {
        guard !request.command.isEmpty else {
            throw FleetError.rejected("command is empty")
        }
        guard !request.friendlyName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.rejected("--name is required")
        }
        guard !request.ownerAgent.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.rejected("--owner is required: every managed service must have an owner")
        }
        guard !request.purpose.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FleetError.rejected("--purpose is required: every managed service must say why it exists")
        }

        let cwd = (request.cwd as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else {
            throw FleetError.rejected("working directory does not exist: \(cwd)")
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cwd),
           let owner = attrs[.ownerAccountID] as? NSNumber,
           uid_t(owner.uint32Value) != geteuid() {
            throw FleetError.rejected("working directory is not owned by this user: \(cwd)")
        }

        guard let executable = resolveExecutable(request.command[0]) else {
            throw FleetError.rejected("executable not found or not executable: \(request.command[0])")
        }

        for port in request.declaredPorts where !(1...65535).contains(port) {
            throw FleetError.rejected("invalid port: \(port)")
        }
        if !request.budget.allowedPorts.isEmpty {
            let undeclared = request.declaredPorts.filter { !request.budget.allowedPorts.contains($0) }
            if !undeclared.isEmpty {
                throw FleetError.rejected("declared ports \(undeclared) are outside --allow-port \(request.budget.allowedPorts)")
            }
        }
        if request.health.kind == .http {
            guard let target = request.health.target, let url = URL(string: target),
                  HealthChecker.isLoopbackHTTP(url) else {
                throw FleetError.rejected("HTTP health checks must target localhost")
            }
        }

        var argv = request.command
        argv[0] = executable
        return (argv, cwd)
    }

    static func resolveExecutable(_ command: String) -> String? {
        if command.contains("/") {
            let path = (command as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
        return Shell.which(command)
    }

    static func spawn(id: String, argv: [String], cwd: String,
                      extraEnv: [String: String]) throws -> Spawned {
        try FleetPaths.ensureDirectories()
        let outPath = FleetPaths.stdoutPath(for: id)
        let errPath = FleetPaths.stderrPath(for: id)

        let outFD = open(outPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard outFD >= 0 else { throw FleetError.io("cannot open \(outPath)") }
        let errFD = open(errPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard errFD >= 0 else {
            close(outFD)
            throw FleetError.io("cannot open \(errPath)")
        }
        let nullFD = open("/dev/null", O_RDONLY)
        defer {
            close(outFD); close(errFD)
            if nullFD >= 0 { close(nullFD) }
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        if nullFD >= 0 { posix_spawn_file_actions_adddup2(&fileActions, nullFD, 0) }
        posix_spawn_file_actions_adddup2(&fileActions, outFD, 1)
        posix_spawn_file_actions_adddup2(&fileActions, errFD, 2)
        posix_spawn_file_actions_addchdir_np(&fileActions, cwd)

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        posix_spawnattr_setpgroup(&attrs, 0)

        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attrs, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attrs, &emptyMask)

        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP
                                               | POSIX_SPAWN_SETSIGDEF
                                               | POSIX_SPAWN_SETSIGMASK))

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "FLEET_SERVICE_ID")
        for (key, value) in extraEnv { environment[key] = value }
        environment["FLEET_SERVICE_ID"] = id
        environment["FLEET_MANAGED"] = "1"

        let argvC: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        let envC: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argvC.forEach { free($0) }
            envC.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, argv[0], &fileActions, &attrs, argvC, envC)
        guard rc == 0 else {
            throw FleetError.io("posix_spawn failed: \(String(cString: strerror(rc)))")
        }

        return Spawned(pid: pid,
                       pgid: pid,
                       startSignature: startSignature(of: pid),
                       stdoutPath: outPath,
                       stderrPath: errPath)
    }

    static func startSignature(of pid: Int32) -> String? {
        let result = Shell.run("/bin/ps", ["-o", "lstart=", "-p", "\(pid)"], timeout: 3)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
