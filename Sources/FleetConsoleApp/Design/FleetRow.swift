import SwiftUI
import FleetCore

// The two primitives every list row in FleetConsole is built from.
//
// Before this, the hover state, highlight background, chevron rotation, expansion
// animation and padding were reimplemented in four different row views, which is
// why they had drifted apart by a point here and a pixel there. There is now one
// implementation; a row supplies content, not chrome.

/// Icon + title + subtitle + optional trailing text and accessory.
protocol FleetAccessibleLabel: View {
    var accessibilityText: String { get }
}

struct FleetRowLabel<Accessory: View>: FleetAccessibleLabel {
    let icon: String
    var tone: StatusTone = .neutral
    var badge: StatusTone?
    let title: String
    var subtitle: String?
    var trailingText: String?
    var trailingMono = false
    var iconSize: CGFloat = FleetMetrics.iconRowLarge
    var titleFont: Font = FleetFont.rowTitle
    /// Subtitle sits under the title (regular rows) or beside it (compact rows).
    var inlineSubtitle = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: FleetMetrics.rowGap) {
            EntityIcon(symbol: icon, tone: tone, size: iconSize, badge: badge)

            if inlineSubtitle {
                Text(title)
                    .font(titleFont)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let subtitle {
                    Text(subtitle)
                        .font(FleetFont.subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(titleFont)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(FleetFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                            .lineLimit(1)
                            // Tail, not middle. A row subtitle is composed prose
                            // read left to right — "pid 54610 · first seen 13h
                            // 17m ago", "claude · local API for triage" — where
                            // the leading tokens identify and the trailing ones
                            // qualify. Middle truncation ate the qualifier and
                            // kept a meaningless tail, turning summaries into
                            // "pid…p 8h 10m". Middle stays where both ends are
                            // load-bearing: paths, socket pairs, reverse-DNS
                            // labels. Those are identifiers, not sentences.
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)
            }

            Spacer(minLength: 4)
            accessory
            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(trailingMono ? FleetFont.mono(12) : FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                    // `fixedSize` for the same reason `Tag` has it, and it was
                    // missing here while `Tag` was guarded by its own audit
                    // check. A trailing text is a timestamp, a port or a
                    // duration — a short, complete, already-abbreviated value —
                    // competing for width against a title holding
                    // `layoutPriority(1)`. Without this it loses and truncates,
                    // and the surface sheet showed all three Needs-attention
                    // rows doing it at once: "12…", "2m a…", and one clipped to
                    // the single character "1". A timestamp that truncates is
                    // not a shorter timestamp, it is no timestamp — "12…" is
                    // twelve minutes or twelve hours or twelve days.
                    //
                    // The title is the right loser: it is one line already, and
                    // its full text is in the subtitle and the row's tooltip.
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        [title, subtitle, trailingText].compactMap { $0 }.joined(separator: ", ")
    }
}

extension FleetRowLabel where Accessory == EmptyView {
    init(icon: String, tone: StatusTone = .neutral, badge: StatusTone? = nil,
         title: String, subtitle: String? = nil, trailingText: String? = nil,
         trailingMono: Bool = false, iconSize: CGFloat = FleetMetrics.iconRowLarge,
         titleFont: Font = FleetFont.rowTitle, inlineSubtitle: Bool = false) {
        self.init(icon: icon, tone: tone, badge: badge, title: title, subtitle: subtitle,
                  trailingText: trailingText, trailingMono: trailingMono, iconSize: iconSize,
                  titleFont: titleFont, inlineSubtitle: inlineSubtitle, accessory: { EmptyView() })
    }
}

/// A row that expands in place. Owns every piece of interaction chrome so that
/// individual rows cannot drift apart from one another again.
struct DisclosureRow<Label: FleetAccessibleLabel, Detail: View>: View {
    let id: String
    @Binding var expanded: String?
    var detailInset: CGFloat = FleetMetrics.detailInset
    var help: String?
    @ViewBuilder var label: Label
    @ViewBuilder var detail: Detail

    @State private var hovering = false

    private var isExpanded: Bool { expanded == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: FleetMetrics.rowGap) {
                    label
                    Image(systemName: "chevron.right")
                        .font(FleetFont.chevron)
                        .foregroundStyle(SurfaceInk.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, FleetMetrics.rowInset)
                .padding(.vertical, FleetMetrics.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .rowBackground(hovering: hovering, selected: isExpanded)
            .padding(.horizontal, FleetMetrics.rowHighlightMargin)
            .modifier(OptionalHelp(text: help))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel([label.accessibilityText, help].compactMap { $0 }.joined(separator: ". "))
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAction { toggle() }
            .accessibilityHint(isExpanded ? "Collapse for less detail" : "Expand for detail")

            if isExpanded {
                detail
                    .padding(.leading, detailInset + FleetMetrics.rowInset)
                    .padding(.trailing, FleetMetrics.gutter)
                    .padding(.vertical, 6)
            }
        }
    }

    private func toggle() {
        withAnimation(FleetAnimation.disclosure) {
            expanded = isExpanded ? nil : id
        }
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// Small actions strip shown inside an expanded row.
struct RowActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .buttonStyle(.link)
        .font(FleetFont.subtitle)
        .padding(.top, 3)
    }
}

/// The connection pip used in footers: the one place a bare dot is still the
/// right primitive, because there is no entity to identify — only a state.
struct ConnectionPip: View {
    let connected: Bool
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? StatusTone.good.color : StatusTone.bad.color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(FleetFont.subtitle)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connected ? "Controller connected. \(label)" : "Controller not running")
    }
}
