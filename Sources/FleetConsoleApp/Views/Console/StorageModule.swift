import SwiftUI
import FleetCore

struct StorageModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    @State private var pendingReclaim: ReclaimCandidate?

    private var breakdown: StorageBreakdown { model.breakdown }
    private var scanner: StorageScanner { model.storage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuantizedCardGrid(minimumCellWidth: 440, maximumColumns: 2) {
                    breakdownCard
                    if !breakdown.breakdown.diskMap.isEmpty { diskMapCard }
                }

                QuantizedCardGrid(minimumCellWidth: 440, maximumColumns: 2) {
                    if !breakdown.volumes.isEmpty { volumesSection }
                    reclaimSection
                }
            }
            .padding(ConsoleMetrics.gutter)
        }
        .scrollContentBackground(.hidden)
        .alert(item: $pendingReclaim) { candidate in
            Alert(title: Text("Reclaim \(ConsoleFmt.bytes(candidate.sizeBytes)) from “\(candidate.title)”?"),
                  message: Text(confirmationBody(candidate)),
                  primaryButton: .destructive(Text(candidate.movesToTrash ? "Move to Trash" : "Delete")) {
                      scanner.reclaim(candidate) { _ in }
                  },
                  secondaryButton: .cancel())
        }
        .onAppear {
            if breakdown.breakdown.scannedAt == nil && !breakdown.breakdown.scanning {
                breakdown.scan()
            } else {
                breakdown.refreshVolumes()
            }
            if scanner.scan.scannedAt == nil && !scanner.scan.scanning {
                scanner.rescan()
            }
        }
    }

    private func scanAll() {
        breakdown.scan()
        scanner.rescan()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Boot Volume Breakdown")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                if let scanned = breakdown.breakdown.scannedAt {
                    Text("scanned \(Fmt.relative(scanned))")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                }
                if breakdown.breakdown.scanning || scanner.scan.scanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Scan Now") { scanAll() }
                        .controlSize(.small)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                }
            }

            if breakdown.breakdown.scanning && breakdown.breakdown.segments.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring top-level directories — this walks real disk and takes a moment.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 56)
            } else if breakdown.breakdown.segments.isEmpty {
                EmptyPanelView(symbol: "internaldrive",
                               title: "Not measured yet",
                               detail: "Run a scan to break the volume down by category.")
                    .frame(height: 144)
            } else {
                SegmentedStorageBar(segments: breakdown.breakdown.segments,
                                    total: barTotal,
                                    selection: Binding(get: { console.selectedSegmentID },
                                                       set: { console.selectSegment($0) }))

                if !breakdown.breakdown.capacityKnown {
                    Label("The boot volume's capacity could not be read, so free, purgeable and "
                          + "“System & Other” are missing — this is the measured buckets only.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(StatusTone.warn.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                QuantizedCardGrid(usesLargestIntrinsicWidth: true,
                                  horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(breakdown.breakdown.segments) { segment in
                        Button {
                            withAnimation(ConsoleAnimation.selection) {
                                console.selectSegment(segment.id)
                            }
                        } label: {
                            SegmentChip(segment: segment,
                                        selected: console.selectedSegmentID == segment.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .elevatedCard()
    }

    private var barTotal: Int64 {
        let result = breakdown.breakdown
        return result.capacityKnown
            ? result.volumeTotalBytes
            : result.segments.reduce(Int64(0)) { $0 + $1.bytes }
    }

    private var diskMapCard: some View {
        let root = breakdown.volumes.first(where: \.isRoot)
        let used = root?.usedBytes ?? model.system.storage.usedBytes
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Disk Map")
                    .font(ConsoleFont.cardTitle)
                Spacer()
                Text("area = allocated bytes · colour = category · tap to reveal")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            HeatmapView(items: breakdown.breakdown.diskMap.map(diskMapItem),
                        summary: "Measured directories cover \(ConsoleFmt.bytes(breakdown.breakdown.measuredBytes)) of "
                               + "\(ConsoleFmt.bytes(used)) used — the remainder is system data and "
                               + "unsurveyed folders (the “System & Other” segment above).")
                .frame(height: ConsoleMetrics.mapHeight)
        }
        .elevatedCard()
    }

    private func diskMapItem(_ entry: DiskMapEntry) -> HeatmapItem {
        HeatmapItem(
            id: entry.id,
            name: entry.name,
            detail: entry.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
            bytes: entry.bytes,
            color: entry.category.color,
            labelColor: entry.category.tileLabelColor,
            isRemainder: entry.isRemainder,
            action: .reveal(entry.path))
    }

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volumes")
                .font(ConsoleFont.cardTitle)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(breakdown.volumes.enumerated()), id: \.element.id) { index, volume in
                    if index > 0 { Hairline().padding(.leading, 52) }
                    VolumeRow(volume: volume,
                              selected: console.selectedVolumeID == volume.id) {
                        withAnimation(ConsoleAnimation.selection) {
                            console.selectVolume(volume.id)
                        }
                    }
                }
            }
            .elevatedCard(padding: 0)
        }
    }

    private var reclaimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reclaimable Space")
                    .font(ConsoleFont.cardTitle)
                if let scanned = scanner.scan.scannedAt {
                    Text("scanned \(Fmt.relative(scanned))")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                }
                Spacer()
                Text("\(ConsoleFmt.bytes(scanner.scan.reclaimableBytes)) reclaimable")
                    .font(ConsoleFont.mono(.caption))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let reclaimable = scanner.scan.candidates.filter(\.risk.reclaimable)
                if scanner.scan.scanning && reclaimable.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Measuring known caches…")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(ConsoleMetrics.cardPadding)
                } else if reclaimable.isEmpty {
                    Text(scanner.scan.scannedAt == nil
                         ? "Not scanned yet."
                         : "Nothing worth reclaiming — known caches are empty or absent.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(ConsoleMetrics.cardPadding)
                } else {
                    QuantizedCardGrid(minimumCellWidth: ConsoleMetrics.reclaimRowMinWidth,
                                      horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(reclaimable) { candidate in
                            ReclaimRow(candidate: candidate) {
                                pendingReclaim = candidate
                            } onReveal: {
                                if let first = candidate.paths.first { scanner.revealInFinder(first) }
                            }
                        }
                    }
                }

                let keepers = scanner.scan.candidates.filter { !$0.risk.reclaimable }
                if !keepers.isEmpty {
                    Hairline()
                    Text("Large, but it is your data — reported, never offered for deletion.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .padding(.horizontal, ConsoleMetrics.cardPadding)
                        .padding(.top, 10)
                    QuantizedCardGrid(minimumCellWidth: ConsoleMetrics.reclaimRowMinWidth,
                                      horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(keepers) { candidate in
                            ReclaimRow(candidate: candidate, onReclaim: nil) {
                                if let first = candidate.paths.first { scanner.revealInFinder(first) }
                            }
                        }
                    }
                }

                if let error = scanner.lastError {
                    Hairline()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(StatusTone.bad.ink)
                        .padding(ConsoleMetrics.cardPadding)
                } else if let done = scanner.lastReclaimed {
                    Hairline()
                    Label(done, systemImage: "checkmark.circle.fill")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(StatusTone.good.ink)
                        .padding(ConsoleMetrics.cardPadding)
                }
            }
            .elevatedCard(padding: 0)
        }
    }

    private func confirmationBody(_ candidate: ReclaimCandidate) -> String {
        var lines: [String] = [candidate.consequence, candidate.paths.joined(separator: "\n")]
        lines.append(candidate.movesToTrash
                     ? "This moves to the Trash — recoverable, but the space returns only when the Trash is emptied."
                     : "This deletes the contents immediately. The space is returned now.")
        return lines.joined(separator: "\n\n")
    }
}

struct SegmentedStorageBar: View {
    let segments: [BreakdownSegment]
    let total: Int64
    @Binding var selection: String?

    private struct Stripe: Identifiable {
        let segment: BreakdownSegment
        var widthBytes: Int64
        var rolledUp: Int64 = 0
        var id: String { segment.id }
    }

    private var stripes: [Stripe] {
        guard total > 0 else { return [] }
        var drawn: [Stripe] = []
        var slivers: [BreakdownSegment] = []
        for segment in segments where segment.bytes > 0 {
            let share = Double(segment.bytes) / Double(total)
            if share < 0.015, segment.category != .free, segment.category != .other {
                slivers.append(segment)
            } else {
                drawn.append(Stripe(segment: segment, widthBytes: segment.bytes))
            }
        }
        let rolledUp = slivers.reduce(Int64(0)) { $0 + $1.bytes }
        if rolledUp > 0 {
            if let index = drawn.firstIndex(where: { $0.segment.category == .other }) {
                drawn[index].widthBytes += rolledUp
                drawn[index].rolledUp = rolledUp
            } else {
                drawn.append(contentsOf: slivers.map { Stripe(segment: $0, widthBytes: $0.bytes) })
            }
        }
        return drawn.sorted { $0.segment.category.sortRank < $1.segment.category.sortRank }
    }

    var body: some View {
        let stripes = self.stripes
        let denominator = Double(max(total, stripes.reduce(Int64(0)) { $0 + $1.widthBytes }))
        return GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(stripes) { stripe in
                    let share = stripe.widthBytes > 0 ? Double(stripe.widthBytes) / denominator : 0
                    RoundedRectangle(cornerRadius: ConsoleMetrics.barCorner, style: .continuous)
                        .fill(stripe.segment.category.color)
                        .frame(width: max(3, geometry.size.width * share - 2))
                        .overlay {
                            if selection == stripe.id {
                                RoundedRectangle(cornerRadius: ConsoleMetrics.barCorner, style: .continuous)
                                    .strokeBorder(ConsoleColor.outlineStrong, lineWidth: 1.5)
                            }
                        }
                        .help(tooltip(stripe))
                        .onTapGesture { toggle(stripe.id) }
                        .focusable()
                        .onKeyPress(keys: [.return, .space], phases: .down) { _ in
                            toggle(stripe.id)
                            return .handled
                        }
                        .accessibilityElement()
                        .accessibilityLabel(label(stripe))
                        .accessibilityAddTraits(selection == stripe.id ? [.isButton, .isSelected]
                                                                      : [.isButton])
                        .accessibilityAction { toggle(stripe.id) }
                }
            }
        }
        .frame(height: 22)
        .animation(ConsoleAnimation.barGrowth, value: segments)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage breakdown")
    }

    private func toggle(_ id: String) {
        withAnimation(ConsoleAnimation.selection) {
            selection = selection == id ? nil : id
        }
    }

    private func label(_ stripe: Stripe) -> String {
        "\(stripe.segment.category.rawValue), \(ConsoleFmt.bytes(stripe.segment.bytes))"
    }

    private func tooltip(_ stripe: Stripe) -> String {
        let base = "\(stripe.segment.category.rawValue) — \(ConsoleFmt.bytes(stripe.segment.bytes))"
        guard stripe.rolledUp > 0 else { return base }
        return base + "\nDrawn with \(ConsoleFmt.bytes(stripe.rolledUp)) of segments too small "
             + "to show — see the legend for their own figures."
    }
}

struct SegmentChip: View {
    let segment: BreakdownSegment
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Swatch(color: segment.category.color)
            Text(segment.category.rawValue)
                .font(ConsoleFont.caption)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
            Text(ConsoleFmt.bytes(segment.bytes))
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Capsule().fill(selected ? ConsoleColor.selectedWash : ConsoleColor.surfaceWash)
        )
        .overlay(
            Capsule().strokeBorder(selected ? ConsoleColor.outline : Color.clear, lineWidth: 1)
        )
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EntityIcon(symbol: volume.isRoot ? "internaldrive.fill" : "externaldrive.fill",
                           tone: SystemThresholds.freeSpace(share: volume.usedShare), size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(ConsoleFont.rowTitle.weight(.medium))
                        if volume.isRoot {
                            ConsoleBadge(text: "boot", tone: .neutral)
                        }
                        Text(volume.fileSystemType)
                            .font(ConsoleFont.mono(.caption2))
                            .foregroundStyle(SurfaceInk.secondary)
                    }
                    CapacityMeter(share: volume.usedShare,
                                  tone: SystemThresholds.freeSpace(share: volume.usedShare))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ConsoleFmt.bytes(volume.availableBytes)) available")
                        .font(ConsoleFont.mono(.caption))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if volume.purgeableBytes > 100_000_000 {
                        Text("\(ConsoleFmt.bytes(volume.purgeableBytes)) purgeable")
                            .font(ConsoleFont.mono(.caption2))
                            .monospacedDigit()
                            .foregroundStyle(SurfaceInk.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(ConsoleFont.badge)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, ConsoleMetrics.cardPadding)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(selected ? ConsoleColor.selectionFill : Color.clear)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 0)
    }
}

struct CapacityMeter: View {
    let share: Double
    let tone: StatusTone

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tone.color)
                    .frame(width: geometry.size.width * min(1, max(0, share)))
            }
        }
        .frame(height: 4)
        .animation(ConsoleAnimation.telemetry, value: share)
    }
}

private struct ReclaimRow: View {
    let candidate: ReclaimCandidate
    var onReclaim: (() -> Void)?
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EntityIcon(symbol: candidate.icon, tone: candidate.risk.tone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(ConsoleFont.rowTitle)
                    .lineLimit(1)
                Text(candidate.risk.label)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Spacer()
            Text(ConsoleFmt.bytes(candidate.sizeBytes))
                .font(ConsoleFont.mono(.callout))
                .monospacedDigit()
                .foregroundStyle(ConsoleColor.numeral)
            Menu {
                if let onReclaim {
                    Button(candidate.movesToTrash ? "Move to Trash…" : "Delete…",
                           action: onReclaim)
                }
                Button("Reveal in Finder", action: onReveal)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(ConsoleFont.rowTitle)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help(candidate.consequence)
            .accessibilityLabel("Actions for \(candidate.title)")
            .accessibilityHint(candidate.consequence)
        }
        .padding(.horizontal, ConsoleMetrics.cardPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .hoverHighlight(cornerRadius: 0)
    }
}

extension StorageCategory {
    var sortRank: Int {
        switch self {
        case .apps: return 0
        case .developer: return 1
        case .caches: return 2
        case .documents: return 3
        case .downloads: return 4
        case .media: return 5
        case .other: return 6
        case .purgeable: return 7
        case .free: return 8
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var point = CGPoint.zero
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > width, point.x > 0 {
                point.x = 0
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            point.x += size.width + spacing
            height = max(height, point.y + rowHeight)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + spacing
        }
    }
}
