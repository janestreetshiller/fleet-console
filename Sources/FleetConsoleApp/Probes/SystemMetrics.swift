import Foundation
import FleetCore
import IOKit
import IOKit.ps
import Darwin

struct CPUSample: Equatable {
    var sampled = false
    var usage: Double = 0
    var userShare: Double = 0
    var systemShare: Double = 0
    var idleShare: Double = 1
    var perCore: [Double] = []
    var efficiencyUsage: Double?
    var performanceUsage: Double?
    var loadAverage: [Double] = []
    var checkedAt = Date()

    var busyShare: Double { userShare + systemShare }
}

struct CPUTopology: Equatable {
    var brand = "CPU"
    var logicalCores = 0
    var efficiencyCores = 0
    var performanceCores = 0
    var efficiencyRange: Range<Int>?
    var performanceRange: Range<Int>?

    var hasClusters: Bool { efficiencyRange != nil && performanceRange != nil }

    var coreSummary: String {
        hasClusters
            ? "\(performanceCores)P + \(efficiencyCores)E"
            : "\(logicalCores) cores"
    }
}

struct GPUSample: Equatable {
    var available = false
    var model: String?
    var coreCount: Int?
    var utilization: Double?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var inUseMemoryBytes: Int64?
    var allocatedMemoryBytes: Int64?
    var checkedAt = Date()
}

struct MemorySample: Equatable {
    enum Pressure: Equatable {
        case normal, warning, critical, unknown

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

struct StorageSample: Equatable {
    var volumeName = "Macintosh HD"
    var totalBytes: Int64 = 0
    var availableBytes: Int64 = 0
    var device: String?
    var model: String?
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

private final class HostSampler: @unchecked Sendable {
    private var previousCPUTicks: [[UInt32]] = []
    private var previousDisk: (read: Int64, write: Int64, readOps: Int64,
                               writeOps: Int64, at: Date)?
    private var previousNetwork: (counters: [String: NetworkInterfaceCounters],
                                  at: ContinuousClock.Instant)?

    let topology: CPUTopology

    init() {
        topology = Self.readTopology()
    }

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

        sample.wiredBytes = wired
        sample.compressedBytes = compressed
        sample.cachedBytes = max(0, external + purgeable)
        sample.appBytes = max(0, active + inactive + speculative - sample.cachedBytes)
        sample.usedBytes = min(sample.totalBytes,
                               sample.appBytes + wired + compressed)
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

    func network() -> NetworkTrafficSample {
        guard let counters = NativeNetworkCounters.read() else {
            previousNetwork = nil
            return NetworkTrafficSample()
        }
        let now = ContinuousClock.now
        let duration = previousNetwork.map { $0.at.duration(to: now).components }
        let elapsed = duration.map {
            Double($0.seconds) + Double($0.attoseconds) / 1e18
        } ?? 0
        let sample = NetworkTrafficRates.sample(current: counters,
                                                previous: previousNetwork?.counters,
                                                elapsed: elapsed)
        previousNetwork = (counters, now)
        return sample
    }

    func power() -> PowerSample {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return PowerSample() }

        var descriptions: [[String: Any]] = []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any] else { return PowerSample() }
            descriptions.append(description)
        }
        return PowerSourceDecoder.sample(descriptions: descriptions)
    }

    private static func readTopology() -> CPUTopology {
        var topology = CPUTopology()
        topology.brand = sysctlString("machdep.cpu.brand_string") ?? "CPU"
        topology.logicalCores = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount

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

@Observable
@MainActor
final class SystemMonitor {
    private(set) var cpu = CPUSample()
    private(set) var gpu = GPUSample()
    private(set) var memory = MemorySample()
    private(set) var storage = StorageSample()
    private(set) var network = NetworkTrafficSample()
    private(set) var power = PowerSample()
    private(set) var thermal = ThermalSample()
    private(set) var topology = CPUTopology()
    private(set) var sensors = SensorSample()

    private(set) var cpuSeries = MetricHistory()
    var cpuHistory: [Double] { cpuSeries.samples.map(\.value) }
    private(set) var gpuSeries = MetricHistory()
    var gpuHistory: [Double] { gpuSeries.samples.map(\.value) }
    private(set) var memorySeries = MetricHistory()
    var memoryHistory: [Double] { memorySeries.samples.map(\.value) }
    private(set) var diskReadSeries = MetricHistory()
    var diskReadHistory: [Double] { diskReadSeries.samples.map(\.value) }
    private(set) var diskWriteSeries = MetricHistory()
    var diskWriteHistory: [Double] { diskWriteSeries.samples.map(\.value) }
    private(set) var networkDownloadSeries = MetricHistory()
    var networkDownloadHistory: [Double] { networkDownloadSeries.samples.map(\.value) }
    private(set) var networkUploadSeries = MetricHistory()
    var networkUploadHistory: [Double] { networkUploadSeries.samples.map(\.value) }

    private(set) var sampledAt = Date()

    static let interval: TimeInterval = 2

    private let sampler = HostSampler()
    private let smc = SMCSampler()
    @ObservationIgnored private let isPremiumUnlocked: (PremiumFeature) -> Bool
    private let queue = DispatchQueue(label: "com.fleetconsole.app.system")
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    private var sampling = false

    init(isPremiumUnlocked: @escaping (PremiumFeature) -> Bool = { _ in true }) {
        self.isPremiumUnlocked = isPremiumUnlocked
        topology = sampler.topology
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        sample()
    }

    deinit {
        timer?.invalidate()
    }

    func sample() {
        guard !sampling else { return }
        sampling = true
        let sampler = self.sampler
        let smc = self.smc
        let readSensors = isPremiumUnlocked(.smcSensors)
        queue.async { [weak self] in
            let sampledAt = Date()
            let cpu = sampler.cpu()
            let gpu = sampler.gpu()
            let memory = sampler.memory()
            let storage = sampler.storage()
            let network = sampler.network()
            let power = sampler.power()
            let sensors = readSensors ? smc.sample() : SensorSample()
            Task { @MainActor in
                self?.publish(cpu: cpu, gpu: gpu, memory: memory, storage: storage,
                              network: network, power: power, sensors: sensors, sampledAt: sampledAt)
            }
        }
    }

    private func publish(cpu: CPUSample, gpu: GPUSample, memory: MemorySample,
                         storage: StorageSample, network: NetworkTrafficSample,
                         power: PowerSample, sensors: SensorSample, sampledAt: Date) {
        self.sampledAt = sampledAt
        if self.cpu != cpu { self.cpu = cpu }
        if self.gpu != gpu { self.gpu = gpu }
        if self.memory != memory { self.memory = memory }
        if self.storage != storage { self.storage = storage }
        if self.network != network { self.network = network }
        if self.power != power { self.power = power }
        if self.sensors != sensors { self.sensors = sensors }
        let thermal = ThermalSample(state: ProcessInfo.processInfo.thermalState)
        if self.thermal != thermal { self.thermal = thermal }

        if cpu.sampled { cpuSeries.append(cpu.usage, at: sampledAt) }
        if let utilization = gpu.utilization { gpuSeries.append(utilization, at: sampledAt) }
        if memory.totalBytes > 0 { memorySeries.append(memory.usedShare, at: sampledAt) }
        if let read = storage.readBytesPerSec, let write = storage.writeBytesPerSec {
            diskReadSeries.append(read, at: sampledAt)
            diskWriteSeries.append(write, at: sampledAt)
        }
        if let download = network.downloadBytesPerSec, let upload = network.uploadBytesPerSec {
            networkDownloadSeries.append(download, at: sampledAt)
            networkUploadSeries.append(upload, at: sampledAt)
        }
        sampling = false
    }


}

enum SystemThresholds {
    static func utilization(_ value: Double) -> StatusTone {
        switch value {
        case ..<0.75: return .good
        case ..<0.90: return .warn
        default: return .bad
        }
    }

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

enum SystemFmt {
    private static let byteFormatter = SharedByteFormatter(countStyle: .file)

    static func size(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 1024 { return "0 KB/s" }
        return byteFormatter.string(fromByteCount: Int64(value)) + "/s"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        return "\(Int(celsius.rounded()))°C"
    }

    static func rpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()).formatted()) rpm"
    }
}
