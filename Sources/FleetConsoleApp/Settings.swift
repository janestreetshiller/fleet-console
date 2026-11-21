import Foundation
import FleetCore

@Observable
@MainActor
final class Settings {
    private(set) var config = FleetConfig()
    private(set) var loadError: String?

    @ObservationIgnored nonisolated(unsafe) private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored nonisolated(unsafe) private var watchedDescriptor: Int32 = -1

    var sections: FleetConfig.UIConfig.Sections { config.ui.sections }
    var intervals: FleetConfig.UIConfig.Intervals { config.ui.intervals }
    var features: FleetConfig.UIConfig.Features { config.ui.features }
    var consoles: FleetConfig.UIConfig.Consoles { config.ui.consoles }

    init() {
        reload()
        startWatching()
    }

    deinit {
        watcher?.cancel()
    }

    func reload() {
        defer {
            VLANRegistry.shared.adopt(config.networkSegments)
        }
        do {
            config = try FleetConfig.load()
            loadError = nil
        } catch {
            if FileManager.default.fileExists(atPath: FleetPaths.config.path) {
                loadError = error.localizedDescription
            } else {
                loadError = nil
            }
            config = FleetConfig()
        }
    }

    private func startWatching() {
        let directory = FleetPaths.config.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { [watchedDescriptor] in
            if watchedDescriptor >= 0 { close(watchedDescriptor) }
        }
        source.resume()
        watcher = source
    }
}
