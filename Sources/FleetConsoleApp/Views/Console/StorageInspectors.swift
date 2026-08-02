import SwiftUI
import FleetCore

// Inspector: one volume, or one breakdown segment.
//
// A volume gets capacity arithmetic, purgeable accounting, file-system facts
// and its local APFS snapshots. A segment gets its byte count and — more
// important — its *basis*: measured where, or arithmetic of what. The honesty
// rules apply to colours too: "System & Other" is the one segment that is
// openly a subtraction, and it says so in its own inspector.

struct VolumeInspector: View {
    @Bindable var model: AppModel
    let volumeID: String

    private var volume: VolumeInfo? {
        model.breakdown.volumes.first { $0.id == volumeID }
    }

    /// A segment id that is not a mount path means the user tapped a bar
    /// segment or legend chip — route to the segment inspector instead.
    private var segment: BreakdownSegment? {
        model.breakdown.breakdown.segments.first { $0.id == volumeID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let volume {
                    volumeContent(volume)
                } else if let segment {
                    segmentContent(segment)
                } else {
                    ContentUnavailableView("Not found", systemImage: "internaldrive")
                }
            }
            .padding(14)
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if volume != nil, let volume {
                model.breakdown.loadSnapshots(for: volume)
            }
        }
        .onChange(of: volumeID) {
            if let volume { model.breakdown.loadSnapshots(for: volume) }
        }
    }

    // MARK: Volume

    @ViewBuilder
    private func volumeContent(_ volume: VolumeInfo) -> some View {
        InspectorHeader(symbol: volume.isRoot ? "internaldrive.fill" : "externaldrive.fill",
                        tone: SystemThresholds.freeSpace(share: volume.usedShare),
                        title: volume.name,
                        subtitle: volume.mountPath,
                        subtitleKind: .identifier)

        InspectorCard(title: "Capacity") {
            CapacityMeter(share: volume.usedShare,
                          tone: SystemThresholds.freeSpace(share: volume.usedShare))
            InspectorLine(key: "Total", value: ConsoleFmt.bytes(volume.totalBytes), mono: true)
            InspectorLine(key: "Used", value: ConsoleFmt.bytes(volume.usedBytes)
                          + " (\(ConsoleFmt.utilPercent(volume.usedShare)))", mono: true)
            InspectorLine(key: "Available", value: ConsoleFmt.bytes(volume.availableBytes), mono: true)
            InspectorLine(key: "Purgeable", value: ConsoleFmt.bytes(volume.purgeableBytes), mono: true)
            Text("Purgeable is the APFS gap between available and important-usage capacity — "
                 + "snapshots and caches the system reclaims under pressure, not a scan result.")
                .font(ConsoleFont.caption)
                .foregroundStyle(.tertiary)
        }

        InspectorCard(title: "Volume") {
            InspectorLine(key: "File system", value: volume.fileSystemType, mono: true)
            InspectorLine(key: "Location", value: volume.isInternal ? "internal" : "external")
            InspectorLine(key: "Role", value: volume.isRoot ? "boot volume"
                          : (volume.isEjectable ? "removable" : "data volume"))
        }

        if volume.fileSystemType == "apfs" {
            InspectorCard(title: "Local Snapshots") {
                if !model.breakdown.snapshots.isEmpty {
                    ForEach(model.breakdown.snapshots.suffix(6), id: \.self) { name in
                        Text(name)
                            .font(ConsoleFont.mono(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    if model.breakdown.snapshots.count > 6 {
                        Text("… \(model.breakdown.snapshots.count - 6) older")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(model.breakdown.snapshotsNote ?? "Reading…")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        InspectorCard(title: "Throughput") {
            InspectorLine(key: "Read", value: ConsoleFmt.byteRate(model.system.storage.readBytesPerSec),
                          mono: true)
            InspectorLine(key: "Write", value: ConsoleFmt.byteRate(model.system.storage.writeBytesPerSec),
                          mono: true)
            ThroughputChart(read: model.system.diskReadHistory,
                            write: model.system.diskWriteHistory,
                            height: 56)
        }
    }

    // MARK: Segment

    @ViewBuilder
    private func segmentContent(_ segment: BreakdownSegment) -> some View {
        InspectorHeader(symbol: segment.category.symbol, tone: .neutral,
                        title: segment.category.rawValue,
                        subtitle: ConsoleFmt.bytes(segment.bytes),
                        subtitleKind: .quantity)

        InspectorCard(title: "Where this number comes from") {
            Text(segment.basis)
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let root = model.breakdown.volumes.first(where: \.isRoot), root.totalBytes > 0 {
            InspectorCard(title: "Share of volume") {
                CapacityMeter(share: Double(segment.bytes) / Double(root.totalBytes),
                              tone: .neutral)
                InspectorLine(key: "Share", value: ConsoleFmt.utilPercent(
                    Double(segment.bytes) / Double(root.totalBytes)), mono: true)
            }
        }
    }
}
