import Foundation
import FleetCore

/// The app's read-only view of `config.json`.
///
/// The controller owns the file — it writes the defaults on first run and it is
/// the only thing that mutates it, so this never writes. What it does is give
/// every surface one place to ask "is this section on", "how often should I
/// look", "is this verb unlocked", instead of each view inventing its own
/// answer.
///
/// **Reloaded on change, not polled.** A `DispatchSource` on the file descriptor
/// costs nothing while the file sits still, which is almost always. Editing the
/// config from the menu-bar dropdown and coming back to a UI that already
/// reflects it is the behaviour you would expect from a Mac app; making that
/// work by re-reading the file every few seconds is not.
@Observable
@MainActor
final class Settings {
    private(set) var config = FleetConfig()
    /// Non-nil when the file exists and could not be parsed. Surfaced rather
    /// than swallowed: silently running on defaults because a file is malformed
    /// is how you lose an afternoon.
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
            // The declared segments are config, so the registry follows the file
            // the same way every other setting does.
            VLANRegistry.shared.adopt(config.networkSegments)
        }
        do {
            config = try FleetConfig.load()
            loadError = nil
        } catch {
            // A missing file is the zero-setup case and is not an error: the
            // defaults *are* the configuration until the controller writes one.
            if FileManager.default.fileExists(atPath: FleetPaths.config.path) {
                loadError = error.localizedDescription
            } else {
                loadError = nil
            }
            config = FleetConfig()
        }
    }

    /// Watches the directory rather than the file.
    ///
    /// `FleetConfig.save()` writes atomically, which replaces the inode — a
    /// descriptor held on the old file would go on reporting nothing forever
    /// while the config on disk changed underneath it. The containing directory
    /// survives the swap, so that is what is watched.
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
