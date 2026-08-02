import Foundation
import IOKit
import Darwin

/// Host resource sampling — CPU, GPU, memory and the internal SSD.
///
/// Like `NetworkMonitor`, this runs in the app rather than the daemon, and for the
/// same reason: it is read-only, needs no privilege, and nothing here is worth
/// waking the controller for. Every number comes from a kernel interface the
/// logged-in user can already read — Mach `host_statistics`, the IOKit registry,
/// and `sysctl`. There is no `powermetrics`, because that wants root, and a
/// resource monitor that prompts for an admin password to draw a bar chart is a
/// worse trade than not drawing it.
///
/// The honesty rules from the rest of the app apply unchanged. A utilisation
/// figure is a *difference between two samples*, so the first tick after launch
/// has no value to report and says so rather than drawing a confident 0%. A key
/// missing from the IOKit registry renders `unknown`, never zero.

// MARK: - Samples

/// CPU load, derived from per-core Mach tick counters.
struct CPUSample: Equatable {
    /// False until two ticks have been differenced. Nothing is drawn as a value
    /// before this is true — a rate needs an interval.
    var sampled = false
    /// 0…1 across all cores.
    var usage: Double = 0
    var userShare: Double = 0
    var systemShare: Double = 0
    var idleShare: Double = 1
    /// 0…1 per logical core, in Mach's enumeration order.
    var perCore: [Double] = []
    /// 0…1 averaged over each cluster, or nil when the split is unknown.
    var efficiencyUsage: Double?
    var performanceUsage: Double?
    var loadAverage: [Double] = []
    var checkedAt = Date()

    var busyShare: Double { userShare + systemShare }
}

/// Static facts about the CPU, read once.
struct CPUTopology: Equatable {
    var brand = "CPU"
    var logicalCores = 0
    var efficiencyCores = 0
    var performanceCores = 0
    /// Index range of each cluster within `perCore`, when Apple Silicon reports one.
    var efficiencyRange: Range<Int>?
    var performanceRange: Range<Int>?

    var hasClusters: Bool { efficiencyRange != nil && performanceRange != nil }

    var coreSummary: String {
        hasClusters
            ? "\(performanceCores)P + \(efficiencyCores)E"
            : "\(logicalCores) cores"
    }
}

/// Apple Silicon GPU statistics from the IOAccelerator registry entry.
struct GPUSample: Equatable {
    /// False when no accelerator published `PerformanceStatistics` — the honest
    /// state for a machine or OS build that does not expose it.
    var available = false
    var model: String?
    var coreCount: Int?
    /// 0…1. Nil when the accelerator exists but withheld the key.
    var utilization: Double?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var inUseMemoryBytes: Int64?
    var allocatedMemoryBytes: Int64?
    var checkedAt = Date()
}

/// Unified memory, split the way Activity Monitor splits it.
struct MemorySample: Equatable {
    enum Pressure: Equatable {
        case normal, warning, critical, unknown

        /// Reads as the object of "pressure …", which is where it is always shown.
        var label: String {
            switch self {
            case .normal: return "normal"
            case .warning: return "elevated"
            case .critical: return "critical"
            case .unknown: return "unknown"
            }
        }
    }

    var totalBytes: Int64 = 0
    var usedBytes: Int64 = 0
    var appBytes: Int64 = 0
    var wiredBytes: Int64 = 0
    var compressedBytes: Int64 = 0
    var cachedBytes: Int64 = 0
    var swapUsedBytes: Int64 = 0
    var swapTotalBytes: Int64 = 0
    var pressure: Pressure = .unknown
    var checkedAt = Date()

    var usedShare: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

/// The boot volume plus throughput for the physical device behind it.
struct StorageSample: Equatable {
    var volumeName = "Macintosh HD"
    var totalBytes: Int64 = 0
    /// What Finder reports as available — purgeable space counted the way the
    /// system will actually let you use it.
    var availableBytes: Int64 = 0
    var device: String?
    var model: String?
    /// Nil until two samples have been differenced.
    var readBytesPerSec: Double?
    var writeBytesPerSec: Double?
    var readOpsPerSec: Double?
    var writeOpsPerSec: Double?
    var checkedAt = Date()

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    var usedShare: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    var sampled: Bool { readBytesPerSec != nil }
}

/// `ProcessInfo.thermalState` — the one thermal fact macOS gives an unprivileged
/// process, and the one that explains a sudden drop in clock speed.
struct ThermalSample: Equatable {
    var state: ProcessInfo.ThermalState = .nominal

    var label: String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious — CPU is being throttled"
        case .critical: return "critical — heavy throttling"
        @unknown default: return "unknown"
        }
    }
}

/// Typed `sysctlbyname`. Shared with `HostProbe`, which reports the same facts
/// about this machine that it asks other machines for.
enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(nulTerminated: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Sampler
//
// Owns the previous counter values, and is touched only from the monitor's serial
// probe queue. Kept separate from the `@MainActor` monitor so the delta state can
// never be read from two threads at once — which is also what makes the
// `@unchecked Sendable` below true rather than merely convenient.

private final class HostSampler: @unchecked Sendable {
    private var previousCPUTicks: [[UInt32]] = []
    private var previousDisk: (read: Int64, write: Int64, readOps: Int64,
                               writeOps: Int64, at: Date)?

    let topology: CPUTopology

    init() {
        topology = Self.readTopology()
    }

    // MARK: CPU

    /// Differences the per-core tick counters against the previous call. The first
    /// call establishes a baseline and reports `sampled == false`.
    func cpu() -> CPUSample {
        var sample = CPUSample()
        sample.loadAverage = Self.loadAverage()

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else { return sample }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            var perState: [UInt32] = []
            perState.reserveCapacity(states)
            for state in 0..<states {
                perState.append(UInt32(bitPattern: info[core * states + state]))
            }
            ticks.append(perState)
        }

        defer { previousCPUTicks = ticks }
        guard previousCPUTicks.count == ticks.count else { return sample }

        var totals = (user: 0.0, system: 0.0, idle: 0.0, all: 0.0)
        var perCore: [Double] = []
        perCore.reserveCapacity(ticks.count)

        for (core, current) in ticks.enumerated() {
            let previous = previousCPUTicks[core]
            // Tick counters are monotonic but can be reset by a core going offline;
            // a negative delta means the baseline is meaningless, so skip the core.
            let user = delta(current[Int(CPU_STATE_USER)], previous[Int(CPU_STATE_USER)])
            let system = delta(current[Int(CPU_STATE_SYSTEM)], previous[Int(CPU_STATE_SYSTEM)])
            let idle = delta(current[Int(CPU_STATE_IDLE)], previous[Int(CPU_STATE_IDLE)])
            let nice = delta(current[Int(CPU_STATE_NICE)], previous[Int(CPU_STATE_NICE)])
            let all = user + system + idle + nice
            guard all > 0 else { perCore.append(0); continue }

            perCore.append((user + system + nice) / all)
            totals.user += user + nice
            totals.system += system
            totals.idle += idle
            totals.all += all
        }

        guard totals.all > 0 else { return sample }
        sample.sampled = true
        sample.perCore = perCore
        sample.userShare = totals.user / totals.all
        sample.systemShare = totals.system / totals.all
        sample.idleShare = totals.idle / totals.all
        sample.usage = 1 - sample.idleShare

        if let range = topology.efficiencyRange, range.upperBound <= perCore.count {
            sample.efficiencyUsage = mean(perCore[range])
        }
        if let range = topology.performanceRange, range.upperBound <= perCore.count {
            sample.performanceUsage = mean(perCore[range])
        }
        return sample
    }

    private func delta(_ current: UInt32, _ previous: UInt32) -> Double {
        current >= previous ? Double(current - previous) : 0
    }

    private func mean(_ values: ArraySlice<Double>) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // MARK: GPU

    func gpu() -> GPUSample {
        var sample = GPUSample()
        guard let matching = IOServiceMatching("IOAccelerator") else { return sample }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return sample }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let properties = Self.properties(of: entry) else { continue }
            guard let stats = properties["PerformanceStatistics"] as? [String: Any] else { continue }

            sample.available = true
            sample.model = properties["model"] as? String
                ?? (properties["model"] as? Data).flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            sample.coreCount = (properties["gpu-core-count"] as? NSNumber)?.intValue

            // The accelerator reports whole percentages; absent keys stay nil so the
            // UI can say "not reported" instead of drawing an idle GPU.
            sample.utilization = Self.percent(stats["Device Utilization %"])
            sample.rendererUtilization = Self.percent(stats["Renderer Utilization %"])
            sample.tilerUtilization = Self.percent(stats["Tiler Utilization %"])
            sample.inUseMemoryBytes = (stats["In use system memory"] as? NSNumber)?.int64Value
            sample.allocatedMemoryBytes = (stats["Alloc system memory"] as? NSNumber)?.int64Value
            break
        }
        return sample
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return min(1, max(0, number.doubleValue / 100))
    }

    // MARK: Memory

    func memory() -> MemorySample {
        var sample = MemorySample()
        sample.totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return sample }

        // `host_page_size` rather than the `vm_kernel_page_size` global: the global
        // is a `var` the kernel fills in before main and never touches again, which
        // Swift 6 cannot tell apart from state someone might write to. The call is
        // also the documented pairing for the counts `host_statistics64` just
        // returned, so this is the more correct of the two reads, not a workaround.
        // Both report 16384 here; the point is which one is *defined* to match.
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return sample }
        let page = Int64(pageSize)
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let active = Int64(stats.active_count) * page
        let inactive = Int64(stats.inactive_count) * page
        let speculative = Int64(stats.speculative_count) * page
        let purgeable = Int64(stats.purgeable_count) * page
        let external = Int64(stats.external_page_count) * page

        // Activity Monitor's "Memory Used" = app + wired + compressed, where file-backed
        // and purgeable pages are cache the system can reclaim, not memory in use.
        sample.wiredBytes = wired
        sample.compressedBytes = compressed
        sample.cachedBytes = max(0, external + purgeable)
        sample.appBytes = max(0, active + inactive + speculative - sample.cachedBytes)
        sample.usedBytes = sample.appBytes + wired + compressed
        sample.pressure = Self.memoryPressure()

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            sample.swapUsedBytes = Int64(swap.xsu_used)
            sample.swapTotalBytes = Int64(swap.xsu_total)
        }
        return sample
    }

    private static func memoryPressure() -> MemorySample.Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .unknown }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    // MARK: Storage

    func storage() -> StorageSample {
        var sample = StorageSample()
        let url = URL(fileURLWithPath: "/")

        if let values = try? url.resourceValues(forKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) {
            sample.volumeName = values.volumeName ?? "Macintosh HD"
            sample.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            sample.availableBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        guard let disk = Self.busiestBlockStorage() else { return sample }
        sample.device = disk.bsdName
        sample.model = disk.model

        let now = Date()
        if let previous = previousDisk {
            let interval = now.timeIntervalSince(previous.at)
            if interval > 0.05 {
                sample.readBytesPerSec = rate(disk.read, previous.read, interval)
                sample.writeBytesPerSec = rate(disk.write, previous.write, interval)
                sample.readOpsPerSec = rate(disk.readOps, previous.readOps, interval)
                sample.writeOpsPerSec = rate(disk.writeOps, previous.writeOps, interval)
            }
        }
        previousDisk = (disk.read, disk.write, disk.readOps, disk.writeOps, now)
        return sample
    }

    private func rate(_ current: Int64, _ previous: Int64, _ interval: TimeInterval) -> Double {
        current >= previous ? Double(current - previous) / interval : 0
    }

    private struct BlockStorage {
        var bsdName: String?
        var model: String?
        var size: Int64
        var read: Int64
        var write: Int64
        var readOps: Int64
        var writeOps: Int64
    }

    /// The registry lists a driver per block device, including the synthesised ones
    /// backing disk images. The internal SSD is the one with the largest whole-media
    /// child, which is a more durable rule than assuming `disk0`.
    private static func busiestBlockStorage() -> BlockStorage? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: BlockStorage?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let driver = properties(of: entry),
                  let stats = driver["Statistics"] as? [String: Any] else { continue }

            var candidate = BlockStorage(
                bsdName: nil, model: nil, size: 0,
                read: (stats["Bytes (Read)"] as? NSNumber)?.int64Value ?? 0,
                write: (stats["Bytes (Write)"] as? NSNumber)?.int64Value ?? 0,
                readOps: (stats["Operations (Read)"] as? NSNumber)?.int64Value ?? 0,
                writeOps: (stats["Operations (Write)"] as? NSNumber)?.int64Value ?? 0)

            var media: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &media) == KERN_SUCCESS {
                defer { IOObjectRelease(media) }
                while case let child = IOIteratorNext(media), child != 0 {
                    defer { IOObjectRelease(child) }
                    guard let childProperties = properties(of: child),
                          (childProperties["Whole"] as? Bool) == true else { continue }
                    candidate.bsdName = childProperties["BSD Name"] as? String
                    candidate.size = (childProperties["Size"] as? NSNumber)?.int64Value ?? 0
                }
            }

            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS {
                defer { IOObjectRelease(parent) }
                if let parentProperties = properties(of: parent) {
                    candidate.model = (parentProperties["Device Characteristics"] as? [String: Any])?["Product Name"] as? String
                }
            }

            if candidate.size > (best?.size ?? -1) { best = candidate }
        }
        return best
    }

    // MARK: Topology

    private static func readTopology() -> CPUTopology {
        var topology = CPUTopology()
        topology.brand = sysctlString("machdep.cpu.brand_string") ?? "CPU"
        topology.logicalCores = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount

        // Apple Silicon publishes one perflevel per cluster type, ordered fastest
        // first. Mach enumerates logical CPUs the other way round — efficiency
        // cores lead — which is asserted by a test, not assumed here.
        guard let level0 = sysctlInt("hw.perflevel0.logicalcpu"),
              let level1 = sysctlInt("hw.perflevel1.logicalcpu"),
              level0 + level1 == topology.logicalCores else { return topology }

        let level0Name = sysctlString("hw.perflevel0.name")?.lowercased() ?? "performance"
        let performanceFirst = level0Name.hasPrefix("p")
        topology.performanceCores = performanceFirst ? level0 : level1
        topology.efficiencyCores = performanceFirst ? level1 : level0
        topology.efficiencyRange = 0..<topology.efficiencyCores
        topology.performanceRange = topology.efficiencyCores..<topology.logicalCores
        return topology
    }

    private static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : []
    }

    static func sysctlInt(_ name: String) -> Int? { Sysctl.int(name) }
    static func sysctlString(_ name: String) -> String? { Sysctl.string(name) }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }
}

// MARK: - Monitor

/// Samples the host on a fixed cadence and publishes immutable value types.
///
/// The cadence is 2 s. `NetworkMonitor` re-probes every 20 s because a Wi-Fi SSID
/// does not change faster than that, but utilisation is only meaningful as a
/// recent average, and a slower tick makes a bar that is always describing the
/// past. Two seconds also keeps the sampler's own cost off the graph.
@Observable
@MainActor
final class SystemMonitor {
    private(set) var cpu = CPUSample()
    private(set) var gpu = GPUSample()
    private(set) var memory = MemorySample()
    private(set) var storage = StorageSample()
    private(set) var thermal = ThermalSample()
    private(set) var topology = CPUTopology()

    /// Ring buffers behind the live charts. Bounded so a long-running app
    /// cannot grow them without limit. Disk I/O is kept as separate read/write
    /// series — a combined "I/O" number hides a write storm behind idle reads,
    /// which is precisely the case the chart exists to catch.
    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []

    static let historyLength = 60
    static let interval: TimeInterval = 2

    private let sampler = HostSampler()
    private let queue = DispatchQueue(label: "com.fleetconsole.app.system")
    // Nonisolated so `deinit` can invalidate it; nothing observes this handle.
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    private var sampling = false

    init() {
        topology = sampler.topology
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        sample()
    }

    /// The run loop holds the timer even though the closure is weak, so it has to
    /// be invalidated here or a per-view instance would strand a live sampler.
    deinit {
        timer?.invalidate()
    }

    /// Re-samples now. Safe to call from a refresh button — an in-flight sample is
    /// not queued behind another.
    func sample() {
        guard !sampling else { return }
        sampling = true
        let sampler = self.sampler
        queue.async { [weak self] in
            let cpu = sampler.cpu()
            let gpu = sampler.gpu()
            let memory = sampler.memory()
            let storage = sampler.storage()
            Task { @MainActor in
                self?.publish(cpu: cpu, gpu: gpu, memory: memory, storage: storage)
            }
        }
    }

    /// Assigns only what changed, so one moving number does not invalidate every
    /// row that reads this object.
    private func publish(cpu: CPUSample, gpu: GPUSample, memory: MemorySample,
                         storage: StorageSample) {
        if self.cpu != cpu { self.cpu = cpu }
        if self.gpu != gpu { self.gpu = gpu }
        if self.memory != memory { self.memory = memory }
        if self.storage != storage { self.storage = storage }
        let thermal = ThermalSample(state: ProcessInfo.processInfo.thermalState)
        if self.thermal != thermal { self.thermal = thermal }

        if cpu.sampled { append(cpu.usage, to: &cpuHistory) }
        if let utilization = gpu.utilization { append(utilization, to: &gpuHistory) }
        append(memory.usedShare, to: &memoryHistory)
        if let read = storage.readBytesPerSec, let write = storage.writeBytesPerSec {
            append(read, to: &diskReadHistory)
            append(write, to: &diskWriteHistory)
        }
        sampling = false
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }
}

// MARK: - Thresholds
//
// One place decides when a number turns amber or red, so CPU and GPU cannot
// disagree about what "busy" means. The bands are deliberately generous: a
// resource monitor that goes red whenever a build runs teaches you to ignore red.

enum SystemThresholds {
    static func utilization(_ value: Double) -> StatusTone {
        switch value {
        case ..<0.75: return .good
        case ..<0.90: return .warn
        default: return .bad
        }
    }

    /// Free space is the one metric where the warning has to arrive early — by the
    /// time a disk is 99% full, macOS is already failing writes.
    static func freeSpace(share: Double) -> StatusTone {
        switch share {
        case ..<0.85: return .good
        case ..<0.95: return .warn
        default: return .bad
        }
    }

    static func memory(_ sample: MemorySample) -> StatusTone {
        switch sample.pressure {
        case .critical: return .bad
        case .warning: return .warn
        case .normal: return .good
        case .unknown: return utilization(sample.usedShare)
        }
    }

    /// Colour for a process on the map. Deliberately *not* derived from its size:
    /// area already encodes that, and a heatmap whose colour repeats its geometry
    /// carries one dimension of information while looking like two. Size is the
    /// market cap, CPU is the day's move.
    static func cpuActivity(percent: Double) -> StatusTone {
        switch percent {
        case ..<10: return .good
        case ..<50: return .warn
        default: return .bad
        }
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> StatusTone {
        switch state {
        case .nominal: return .good
        case .fair: return .good
        case .serious: return .warn
        case .critical: return .bad
        @unknown default: return .unknown
        }
    }
}

// MARK: - Formatting

enum SystemFmt {
    /// The same shared formatter type the console uses. It was a second private
    /// `ByteCountFormatter` configured identically to `ConsoleFmt`'s, which is two
    /// places for "how this app writes a byte count" to drift apart — the exact
    /// thing the file header of `Formatters.swift` says must not happen.
    private static let byteFormatter = SharedByteFormatter(countStyle: .file)

    static func size(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 1024 { return "0 KB/s" }
        return byteFormatter.string(fromByteCount: Int64(value)) + "/s"
    }

    /// Percentages are shown whole. A utilisation figure with a decimal point
    /// implies a precision that a two-second average does not have.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
