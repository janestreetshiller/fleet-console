import Foundation
import Darwin
import FleetCore

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

do {
    try FleetPaths.ensureDirectories()
} catch {
    FileHandle.standardError.write(Data("fleetd: cannot create support directories: \(error)\n".utf8))
    exit(1)
}

FleetLog.shared.attachFile(at: FleetPaths.daemonLog)
FleetLog.shared.rotateIfNeeded(at: FleetPaths.daemonLog)
if ProcessInfo.processInfo.arguments.contains("--verbose") {
    FleetLog.shared.minimumLevel = .debug
}

if ProcessInfo.processInfo.arguments.contains("--version") {
    print("fleetd \(Controller.version)")
    exit(0)
}

if UnixSocketClient.probeAlive() {
    FleetLog.error("another fleetd is already listening on \(FleetPaths.socket.path); exiting")
    exit(0)
}

let controller: Controller
do {
    controller = try Controller()
} catch {
    FleetLog.error("startup failed: \(error.localizedDescription)")
    exit(1)
}

let signalQueue = DispatchQueue(label: "com.fleetconsole.signals")
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
    source.setEventHandler { @Sendable [controller] in
        StopMarker.write(signal: sig)
        FleetLog.info("received signal \(sig); shutting down")
        controller.shutdown()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

FleetLog.info("fleetd \(Controller.version) starting (pid \(getpid()), uid \(geteuid()))")

do {
    try controller.start()
} catch {
    FleetLog.error("fatal: \(error.localizedDescription)")
    exit(1)
}
dispatchMain()
