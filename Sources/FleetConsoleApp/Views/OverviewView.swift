import SwiftUI
import FleetCore

// Compact primitives shared by both menu-bar surfaces. The fixed row height is
// what lets either popover promise not to scroll.

/// Fixed-height single-line row.
struct CompactRow: View {
    let icon: String
    let tone: StatusTone
    let title: String
    let subtitle: String
    var trailing: String = ""
    var badge: StatusTone?
    /// When this row stands for a running process, the pid and its start
    /// signature — which is what lets the row draw the application's own icon
    /// instead of `icon`. Both nil is the ordinary case and changes nothing.
    var pid: Int32?
    var startSignature: String?
    /// A tool name from `AppIcon.declaredBundleIdentifiers`, for a CLI agent
    /// that has a desktop app installed to borrow an icon from.
    var agentTool: String?

    var body: some View {
        HStack(spacing: 8) {
            AppGlyph(symbol: icon, tone: tone, size: FleetMetrics.iconCompact, badge: badge,
                     pid: pid, startSignature: startSignature, agentTool: agentTool)
            Text(title)
                .font(FleetFont.rowTitleCompact)
                .lineLimit(1)
                .layoutPriority(1)
            Text(subtitle)
                .font(FleetFont.subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(FleetFont.mono(9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .frame(height: FleetMetrics.compactRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle) \(trailing)")
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let tone: StatusTone

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(FleetFont.stat)
                .foregroundStyle(tone == .neutral ? FleetColor.numeral : tone.ink)
                .monospacedDigit()
            Text(label)
                .font(FleetFont.nano)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous)
                .fill(tone == .neutral ? AnyShapeStyle(.quaternary)
                                       : AnyShapeStyle(tone.chipFill))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Uppercased header used inside the compact surfaces.
struct CompactHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(FleetFont.sectionLabel)
                .foregroundStyle(.secondary)
            if let trailing {
                Text(trailing).font(FleetFont.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(height: 28)
    }
}

/// "+ N more…" — overflow is stated, never hidden behind a scroll edge.
struct OverflowLine: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: action) {
                Text("+ \(count) more…")
                    .font(FleetFont.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, FleetMetrics.gutter)
                    .frame(height: 20, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FleetFont.subtitle)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, FleetMetrics.gutter)
            .frame(height: 32, alignment: .leading)
    }
}

/// Shared popover chrome: the header strip and the footer.
struct PopoverHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(FleetFont.rowTitle)
                .foregroundStyle(.tint)
            Text(title)
                .font(FleetFont.title)
            Spacer()
            trailing
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.vertical, 8)
    }
}

struct PopoverFooter: View {
    @Bindable var model: AppModel
    var trailingLabel: String = "Open Dashboard"
    var openDashboard: () -> Void


    var body: some View {
        HStack(spacing: 6) {
            if model.connected, let daemon = model.daemon {
                ConnectionPip(connected: true, label: "controller up \(Fmt.duration(daemon.uptime))")
            } else {
                ConnectionPip(connected: false, label: "controller not running")
            }
            Spacer()
            Text("MIT")
                .font(FleetFont.micro)
                .foregroundStyle(.secondary)
                .help("Free and open source. Every feature is permanently available.")
            Button(trailingLabel) { openDashboard() }
                .buttonStyle(.link)
                .font(FleetFont.subtitle)
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.vertical, 7)

    }
}
