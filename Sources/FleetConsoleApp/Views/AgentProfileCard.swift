import SwiftUI
import FleetCore

/// One agent's profile.
///
/// The first version showed only "N services · said Xm ago", which is blank for
/// any agent that is not running something *right now* — which is most of them,
/// most of the time. An agent that launched fourteen services this morning and
/// left two of them running is not "0 services"; that is the single most
/// important thing to know about it. So the card always shows: what it is doing,
/// what it has done, where it works, and what it last said.
struct AgentProfileCard: View {
    let profile: AgentProfile
    @Bindable var model: AppModel
    @Binding var expanded: String?

    private var isExpanded: Bool { expanded == profile.id }

    /// `nil` when the feature is off or nothing has been sampled yet. A
    /// snapshot whose `amountUSD` is nil is a different thing entirely — the
    /// agent exists and could not be priced — and the detail says so.
    private var spend: AgentCostSnapshot? {
        guard model.settings.features.showAgentSpend else { return nil }
        return model.agentCost.snapshot(for: profile.id)
    }

    private var tone: StatusTone {
        switch profile.tone {
        case .waiting: return .warn
        case .attention: return .warn
        case .active: return .good
        case .idle: return .neutral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(FleetAnimation.disclosure) {
                    expanded = isExpanded ? nil : profile.id
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                detail
                    .padding(.leading, 12)
                    .padding(.trailing, FleetMetrics.gutter)
                    .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FleetColor.surfaceWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(profile.awaitingReply > 0
                              ? StatusTone.warn.edge : Color.clear,
                              lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: FleetMetrics.rowGap) {
                EntityIcon(symbol: "person.crop.square.fill", tone: tone,
                           size: FleetMetrics.iconRowLarge,
                           badge: profile.awaitingReply > 0 ? .warn : nil)
                VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                        Text(profile.id)
                            .font(FleetFont.mono(12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Tag(text: statusWord, tone: tone)
                        // Knowns only. An agent nobody can price says so in its
                        // detail rather than putting a caveat in the title row.
                        if let amount = spend?.amountUSD {
                            Text(Fmt.money(amount))
                                .font(FleetFont.mono(10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(profile.headline)
                        .font(FleetFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.relative(profile.lastActivityAt))
                        .font(FleetFont.mono(9.5))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(FleetFont.chevron)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 8)

            // The four numbers that actually characterise an agent, always shown.
            HStack(spacing: 4) {
                MiniStat(value: "\(profile.running)", label: "running",
                         tone: profile.running > 0 ? .good : .neutral)
                MiniStat(value: "\(profile.totalLaunched)", label: "launched", tone: .neutral)
                MiniStat(value: "\(profile.totalCrashed)", label: "crashed",
                         tone: profile.totalCrashed > 0 ? .bad : .neutral)
                MiniStat(value: "\(profile.totalLeaked)", label: "left running",
                         tone: profile.totalLeaked > 0 ? .warn : .neutral)
                MiniStat(value: "\(profile.awaitingReply)", label: "to answer",
                         tone: profile.awaitingReply > 0 ? .warn : .neutral)
            }
            .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
    }

    private var statusWord: String {
        switch profile.tone {
        case .waiting: return "Waiting on you"
        case .attention: return "Needs attention"
        case .active: return "Active"
        case .idle: return "Idle"
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if profile.running > 0 {
                group("Running now") {
                    KeyValue(key: "Services", value: "\(profile.running)\(profile.paused > 0 ? " (\(profile.paused) paused)" : "")")
                    KeyValue(key: "Ports", value: Fmt.ports(profile.ports), monospaced: true)
                    KeyValue(key: "Resources", value: "\(Fmt.cpu(profile.cpuPct)) CPU · \(Fmt.mem(profile.memMB))")
                    KeyValue(key: "Next lease", value: Fmt.relative(profile.nextLeaseExpiry))
                    if !profile.purposes.isEmpty {
                        KeyValue(key: "Doing", value: profile.purposes.joined(separator: "; "))
                    }
                }
            }

            if let spend {
                group("Cost today") {
                    // The unknown is spelled out rather than shown as a zero,
                    // and the source line is what makes it actionable: a tool
                    // that publishes nothing is not the same as one whose log
                    // would not open.
                    KeyValue(key: "Spend",
                             value: spend.amountUSD.map(Fmt.money) ?? "Unknown",
                             monospaced: spend.isKnown)
                    KeyValue(key: "Source", value: spend.source.explanation)
                }
            }

            group("Track record") {
                KeyValue(key: "Launched", value: "\(profile.totalLaunched) service(s)")
                KeyValue(key: "Cleanup", value: profile.cleanupRecord)
                if profile.totalLeaked > 0 {
                    KeyValue(key: "Left running",
                             value: "\(profile.totalLeaked) reaped by the controller after the lease expired")
                }
                if profile.totalCrashed > 0 {
                    KeyValue(key: "Crashed", value: "\(profile.totalCrashed)")
                }
                if profile.totalRestarts > 0 {
                    KeyValue(key: "Restarts", value: "\(profile.totalRestarts)")
                }
                if profile.healthFailures > 0 {
                    KeyValue(key: "Health fails", value: "\(profile.healthFailures)")
                }
                KeyValue(key: "Total runtime", value: Fmt.duration(profile.totalRuntime))
                KeyValue(key: "First seen", value: Fmt.relative(profile.firstSeen))
                KeyValue(key: "Last active", value: Fmt.relative(profile.lastActivityAt))
            }

            if !profile.projects.isEmpty {
                group("Works in") {
                    ForEach(profile.projects.prefix(4), id: \.self) { path in
                        Button {
                            model.revealInFinder(path)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                    .font(FleetFont.micro).foregroundStyle(.tertiary)
                                Text((path as NSString).lastPathComponent)
                                    .font(FleetFont.subtitle)
                                Text(path).font(FleetFont.mono(9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if profile.projects.count > 4 {
                        Text("+ \(profile.projects.count - 4) more")
                            .font(FleetFont.micro).foregroundStyle(.tertiary)
                    }
                }
            }

            if !profile.recentServices.isEmpty {
                group("Recent services") {
                    ForEach(profile.recentServices) { record in
                        HStack(spacing: 6) {
                            StatusDot(tone: record.state.tone, size: 6)
                            Text(record.friendlyName)
                                .font(FleetFont.subtitle)
                                .lineLimit(1)
                            Text(record.state.label)
                                .font(FleetFont.micro)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 4)
                            Text(Fmt.relative(record.startedAt))
                                .font(FleetFont.mono(9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            group("Messages") {
                if profile.messageCount == 0 {
                    Text("nothing said yet")
                        .font(FleetFont.subtitle).foregroundStyle(.tertiary)
                } else {
                    KeyValue(key: "Total", value: "\(profile.messageCount)"
                             + (profile.awaitingReply > 0 ? " · \(profile.awaitingReply) awaiting your answer" : ""))
                    if let last = profile.lastMessage {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: last.kind.symbol)
                                .font(FleetFont.micro)
                                .foregroundStyle(last.kind == .problem
                                                 ? StatusTone.bad.ink
                                                 : Color.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(last.body)
                                    .font(FleetFont.subtitle)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let reply = last.reply {
                                    Text("↳ \(reply)")
                                        .font(FleetFont.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(FleetFont.micro)
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            content()
        }
    }
}

/// Compact labelled number used across the agent profile header.
struct MiniStat: View {
    let value: String
    let label: String
    var tone: StatusTone = .neutral

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(FleetFont.body.weight(.semibold))
                .foregroundStyle(tone == .neutral ? FleetColor.numeral : tone.ink)
                .monospacedDigit()
            Text(label)
                .font(FleetFont.nano)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tone == .neutral ? FleetColor.surfaceWash : tone.chipFill)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
