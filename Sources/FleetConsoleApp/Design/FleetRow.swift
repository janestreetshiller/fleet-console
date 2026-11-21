import SwiftUI
import FleetCore

protocol FleetAccessibleLabel: View {
    var accessibilityText: String { get }
}

struct FleetRowLabel<Accessory: View>: FleetAccessibleLabel {
    let icon: String
    var tone: StatusTone = .neutral
    var badge: StatusTone?
    let title: String
    var titleDetail: String?
    var subtitle: String?
    var trailingText: String?
    var trailingMono = false
    var iconSize: CGFloat = FleetMetrics.iconRowLarge
    var titleFont: Font = FleetFont.rowTitle
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .font(titleFont)
                            .lineLimit(2)
                        if let titleDetail {
                            Text(titleDetail)
                                .font(FleetFont.caption)
                                .foregroundStyle(tone == .bad || tone == .warn ? tone.ink : SurfaceInk.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(FleetFont.caption)
                            .foregroundStyle(SurfaceInk.secondary)
                            .lineLimit(1)
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
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        [title, titleDetail, subtitle, trailingText].compactMap { $0 }.joined(separator: ", ")
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
