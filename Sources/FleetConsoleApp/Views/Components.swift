import SwiftUI
import FleetCore

struct StatusDot: View {
    let tone: StatusTone
    var size: CGFloat = 8

    var body: some View {
        Image(systemName: tone.symbol)
            .font(.system(size: size))
            .foregroundStyle(tone.ink)
            .accessibilityHidden(true)
    }
}

struct Swatch: View {
    let color: Color
    var size: CGFloat = ConsoleMetrics.legendDot

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct EvidenceChips: View {
    let evidence: Evidence
    let health: HealthSpec
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            chip(title: "process",
                 state: evidence.processExists,
                 detail: evidence.processExists == true ? "pid alive, start time matches" : "no matching process")
            chip(title: "port",
                 state: evidence.portScanRan ? !evidence.listeningPorts.isEmpty : nil,
                 detail: evidence.portScanRan
                    ? (evidence.listeningPorts.isEmpty ? "no listening port" : "listening on \(Fmt.ports(evidence.listeningPorts))")
                    : "not scanned yet")
            chip(title: "health",
                 state: health.kind == .none ? nil : (evidence.healthCheckRan ? evidence.healthPassed : nil),
                 detail: health.kind == .none
                    ? "no health check configured — cannot be verified"
                    : (evidence.healthDetail ?? "not checked yet"))
            if stale {
                Text("stale")
                    .font(FleetFont.micro)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(FleetColor.countPill, in: Capsule())
                    .foregroundStyle(.secondary)
                    .help("Evidence is older than three supervisor ticks; treat it as unknown.")
            }
        }
    }

    @ViewBuilder
    private func chip(title: String, state: Bool?, detail: String) -> some View {
        let tone: StatusTone = state == nil ? .unknown : (state! ? .good : .bad)
        HStack(spacing: 3) {
            Image(systemName: tone.verdict)
                .font(FleetFont.micro.weight(.bold))
                .foregroundStyle(tone.ink)
            Text(title).font(FleetFont.micro)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(tone.wash, in: Capsule())
        .foregroundStyle(state == nil ? Color.secondary : FleetColor.numeral)
        .help(detail)
    }
}

struct EntityIcon: View {
    let symbol: String
    var tone: StatusTone = .neutral
    var size: CGFloat = 28
    var badge: StatusTone?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * FleetMetrics.iconCornerRatio, style: .continuous)
                .fill(tone == .neutral ? AnyShapeStyle(.quaternary)
                                       : AnyShapeStyle(tone.chipFill))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: size * FleetMetrics.iconGlyphRatio, weight: .regular))
                        .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary)
                                                          : AnyShapeStyle(tone.ink))
                )
            if let badge {
                StatusBadge(tone: badge, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let tone: StatusTone
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size * FleetMetrics.iconBadgeRatio,
                   height: size * FleetMetrics.iconBadgeRatio)
            .overlay(
                Image(systemName: tone.verdict)
                    .font(.system(size: size * FleetMetrics.iconBadgeRatio * 0.58,
                                  weight: .bold))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle().strokeBorder(Color(nsColor: .controlBackgroundColor),
                                      lineWidth: FleetMetrics.iconBadgeRing)
            )
    }
}

enum Iconography {
    static func runtime(command: String, commandLine: String, hasPorts: Bool) -> String {
        let haystack = (command + " " + commandLine).lowercased()
        if haystack.contains("docker") || haystack.contains("orbstack") { return "shippingbox" }
        if haystack.contains("postgres") || haystack.contains("mysql")
            || haystack.contains("redis") || haystack.contains("sqlite") { return "cylinder.split.1x2" }
        if haystack.contains("python") || haystack.contains("uvicorn") || haystack.contains("gunicorn")
            || haystack.contains("flask") || haystack.contains("fastapi") { return "curlybraces" }
        if haystack.contains("node") || haystack.contains("npm") || haystack.contains("vite")
            || haystack.contains("next") || haystack.contains("bun") || haystack.contains("deno")
            || haystack.contains("yarn") || haystack.contains("pnpm") { return "hexagon" }
        if haystack.contains("ruby") || haystack.contains("rails") || haystack.contains("puma") { return "diamond" }
        return hasPorts ? "server.rack" : "gearshape.2"
    }

    static func service(_ record: ServiceRecord) -> String {
        runtime(command: record.command.first ?? "",
                commandLine: record.commandLine,
                hasPorts: !record.effectivePorts.isEmpty)
    }

    static func unmanaged(_ process: UnmanagedProcess) -> String {
        runtime(command: process.command, commandLine: process.commandLine,
                hasPorts: !process.ports.isEmpty)
    }

    static func attention(_ item: AttentionItem) -> String {
        item.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }

    enum Metric {
        static let cpu = "cpu"
        static let gpu = "circle.hexagongrid.fill"
        static let memory = "memorychip"
        static let storage = "internaldrive"
        static let thermal = "thermometer.medium"
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(FleetFont.subtitle.weight(.semibold))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(FleetFont.subtitle)
                    .foregroundStyle(SurfaceInk.secondary)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FleetFont.body.weight(.medium))
                .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    var monospaced = false
    var selectable = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(FleetFont.subtitle)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(monospaced ? FleetFont.mono(10.5) : FleetFont.subtitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Tag: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        Text(text)
            .font(FleetFont.sectionLabel)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(tone.chipFill,
                        in: RoundedRectangle(cornerRadius: FleetMetrics.tagCorner, style: .continuous))
            .foregroundStyle(tone.ink)
    }
}

struct RowBackground: ViewModifier {
    let hovering: Bool
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: FleetMetrics.corner, style: .continuous)
                    .fill(selected ? AnyShapeStyle(ConsoleColor.selectionFill)
                          : (hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear)))
            )
    }
}

extension View {
    func rowBackground(hovering: Bool, selected: Bool = false) -> some View {
        modifier(RowBackground(hovering: hovering, selected: selected))
    }
}

struct Sparkline: View {
    let values: [Double]
    var tone: StatusTone = .good
    let label: String
    let current: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(FleetFont.micro)
                .foregroundStyle(SurfaceInk.secondary)
            GeometryReader { geometry in
                let maximum = max(values.max() ?? 1, 0.001)
                let step = values.count > 1 ? geometry.size.width / CGFloat(values.count - 1) : 0
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * step
                        let y = geometry.size.height * (1 - CGFloat(value / maximum))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(tone.stroke, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            }
            .frame(width: 56, height: 14)
            Text(current)
                .font(FleetFont.mono(9.5))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(current), \(values.count) samples")
    }
}

struct Meter: View {
    let value: Double?
    var tone: StatusTone = .good
    var caption: String?
    var width: CGFloat = FleetMetrics.meterWidth

    private var clamped: Double { min(1, max(0, value ?? 0)) }

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: width, height: FleetMetrics.meterHeight)
                if value != nil {
                    Capsule()
                        .fill(tone.color)
                        .frame(width: max(2, width * clamped), height: FleetMetrics.meterHeight)
                }
            }
            .animation(FleetAnimation.disclosure, value: clamped)
            if let caption {
                Text(caption)
                    .font(FleetFont.mono(10.5))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Color.secondary : FleetColor.numeral)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value == nil ? "not sampled yet" : (caption ?? "\(Int(clamped * 100)) percent"))
    }
}

struct CoreGrid: View {
    let values: [Double]
    let topology: CPUTopology

    var body: some View {
        ViewThatFits(in: .horizontal) {
            clusters(wrapping: false)
            clusters(wrapping: true)
        }
    }

    private func clusters(wrapping: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            if topology.hasClusters,
               let efficiency = topology.efficiencyRange,
               let performance = topology.performanceRange,
               performance.upperBound <= values.count {
                cluster(label: "E", indices: Array(efficiency), wrapping: wrapping)
                cluster(label: "P", indices: Array(performance), wrapping: wrapping)
            } else {
                cluster(label: "Cores", indices: Array(values.indices), wrapping: wrapping)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func cluster(label: String, indices: [Int], wrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if wrapping {
                QuantizedCardGrid(usesLargestIntrinsicWidth: true,
                                  horizontalSpacing: 3, verticalSpacing: 3, quantum: 1) {
                    ForEach(indices, id: \.self) { index in
                        bar(value: values[index], core: index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(indices, id: \.self) { index in bar(value: values[index], core: index) }
                }
                .fixedSize()
            }
            Text(label)
                .font(FleetFont.micro)
                .foregroundStyle(SurfaceInk.secondary)
        }
        .frame(maxWidth: wrapping ? .infinity : nil, alignment: .leading)
    }

    private func bar(value: Double, core: Int) -> some View {
        let tone = SystemThresholds.utilization(value)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: FleetMetrics.barCorner, style: .continuous)
                .fill(.quaternary)
                .frame(width: FleetMetrics.coreCellWidth, height: FleetMetrics.coreCellHeight)
            RoundedRectangle(cornerRadius: FleetMetrics.barCorner, style: .continuous)
                .fill(tone.color)
                .frame(width: FleetMetrics.coreCellWidth,
                       height: max(2, FleetMetrics.coreCellHeight * min(1, max(0, value))))
        }
        .animation(FleetAnimation.disclosure, value: value)
        .help("Core \(core) — \(SystemFmt.percent(value))")
        .accessibilityLabel("Core \(core), \(SystemFmt.percent(value))")
    }
}

struct DestructiveAction: Identifiable {
    enum Kind: String { case stop = "Stop", restart = "Restart", kill = "Kill" }
    var id: String { kind.rawValue + service.id }
    let kind: Kind
    let service: ServiceRecord

    var title: String { "\(kind.rawValue) “\(service.friendlyName)”?" }

    var message: String {
        var lines: [String] = []
        lines.append("PID \(service.pid.map(String.init) ?? "unknown") (process group \(service.pgid.map(String.init) ?? "unknown"))"
                     + (service.evidence.listeningPorts.isEmpty ? "" : ", listening on \(Fmt.ports(service.evidence.listeningPorts))") + ".")
        lines.append("Started \(Fmt.relative(service.startedAt)) by agent “\(service.ownerAgent)” — purpose: \(service.purpose).")
        lines.append("Command: \(service.commandLine)")
        switch kind {
        case .stop:
            lines.append("SIGTERM will be sent to the process group, then SIGKILL after the grace period.")
        case .restart:
            lines.append("The process group will be stopped and the recorded command re-run.")
            if !service.declaredPorts.isEmpty {
                lines.append("Ports \(Fmt.ports(service.declaredPorts)) will be released and re-bound.")
            }
        case .kill:
            lines.append("SIGKILL will be sent to the process group immediately, with no grace period. "
                         + "The process gets no chance to flush, close connections or clean up temporary files.")
        }
        return lines.joined(separator: "\n\n")
    }
}
