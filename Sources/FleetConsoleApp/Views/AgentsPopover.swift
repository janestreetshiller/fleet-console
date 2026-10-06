import SwiftUI
import AppKit
import FleetCore

/// Item 3 — Agents. Who is running what, what they have said, and a place to
/// answer them.
///
/// The reply loop is the point: an agent posts a question with
/// `fleetctl notify --ask`, it appears here (and as a notification), you answer,
/// and the agent reads the answer back with `fleetctl inbox --agent <name>`.
/// Nothing here talks to a model — it is a local mailbox between you and whatever
/// process is running.
/// The Agents half of the Fleet item: one profile card per agent, plus anything
/// waiting on an answer from you.
struct AgentsContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void

    @State private var expandedAgent: String?

    /// The roster count, plus today's spend when the feature is on.
    ///
    /// The `+` marks a total that is short by an agent you can see: it is
    /// counted over the *rendered* profiles only, because `gemini` and `aider`
    /// publish nothing and would otherwise pin a permanent, meaningless `+` to
    /// the header. An agent with a row and no figure explains itself when you
    /// open it.
    private var profilesTrailing: String? {
        guard !model.agentProfiles.isEmpty else { return nil }
        let count = "\(model.agentProfiles.count)"
        guard model.settings.features.showAgentSpend,
              let totals = model.agentCost.totals
        else { return count }
        let shown = Set(model.agentProfiles.map(\.id))
        let unpriced = totals.snapshots.filter { shown.contains($0.id) && !$0.isKnown }.count
        return "\(count) · \(Fmt.money(totals.knownTotalUSD))\(unpriced > 0 ? "+" : "")"
    }
    @State private var replyingTo: AgentMessage?
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Profiles first. This tab is a roster: one card per agent that
                // has a config, each carrying its own state. It used to open on
                // four `StatTile`s — Working, Agents, Running, To answer — of
                // which two were the same numbers the Services tab was already
                // showing, and all four summed the agents into totals that say
                // nothing about *which* agent is in trouble. The roster answers
                // that directly, and the per-card state is the same fact the
                // tiles were aggregating away.
                CompactHeader(title: "Profiles", trailing: profilesTrailing)
                if model.agentProfiles.isEmpty {
                    EmptyLine(text: model.connected
                              ? "no agent has launched anything or said anything yet"
                              : "controller unavailable")
                } else {
                    ForEach(model.agentProfiles) { profile in
                        AgentProfileCard(profile: profile, model: model, expanded: $expandedAgent)
                    }
                }

                if !model.awaitingReplies.isEmpty {
                    CompactHeader(title: "Waiting on you", trailing: "\(model.awaitingReplies.count)")
                    ForEach(model.awaitingReplies) { message in
                        MessageRow(message: message, model: model,
                                   replyingTo: $replyingTo, replyText: $replyText,
                                   replyFocused: $replyFocused)
                    }
                }

                if !model.sessions.isEmpty {
                    CompactHeader(title: "Working now", trailing: "\(model.sessions.count)")
                    ForEach(model.sessions) { session in
                        // `agentTool` and not `pid`: a CLI agent is not a GUI
                        // process, so `NSRunningApplication` has nothing for its
                        // pid. The icon — when there is one — comes from the
                        // desktop app declared for this tool and installed on
                        // this machine, and from nowhere else.
                        CompactRow(icon: session.symbol,
                                   tone: .good,
                                   title: session.tool,
                                   subtitle: session.summary,
                                   trailing: String(format: "%.0f%% · %.0f MB", session.cpuPct, session.memMB),
                                   agentTool: session.tool)
                    }
                }

                let recent = model.recentMessages.filter { !$0.isAwaitingReply }
                if !recent.isEmpty {
                    CompactHeader(title: "Recent messages")
                    ForEach(recent.prefix(6)) { message in
                        MessageRow(message: message, model: model,
                                   replyingTo: $replyingTo, replyText: $replyText,
                                   replyFocused: $replyFocused)
                    }
                    OverflowLine(count: max(0, recent.count - 6), action: openDashboard)
                }

                Spacer(minLength: 6)
            }
        }
        .frame(maxHeight: FleetMetrics.sectionMaxHeight)
        // The scan needs no controller, so it must not wait for one: without
        // this, spend never appears while the daemon is down, because the only
        // other caller rides the snapshot tick.
        .onAppear {
            if model.settings.features.showAgentSpend { model.agentCost.refresh() }
        }
    }

}

struct MessageRow: View {
    let message: AgentMessage
    @Bindable var model: AppModel
    @Binding var replyingTo: AgentMessage?
    @Binding var replyText: String
    @FocusState.Binding var replyFocused: Bool

    private var isReplying: Bool { replyingTo?.id == message.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: FleetMetrics.rowGap) {
                EntityIcon(symbol: message.kind.symbol,
                           tone: message.kind == .problem ? .bad
                                : (message.isAwaitingReply ? .warn : .neutral),
                           size: FleetMetrics.iconRow)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(message.agent).font(FleetFont.rowTitleCompact)
                        Text(message.kind.label).font(FleetFont.micro).foregroundStyle(.tertiary)
                        if let name = message.serviceName {
                            Text("· \(name)").font(FleetFont.micro).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Fmt.relative(message.createdAt))
                            .font(FleetFont.micro).foregroundStyle(.tertiary)
                    }
                    Text(message.body)
                        .font(FleetFont.subtitle)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let reply = message.reply {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(FleetFont.marker).foregroundStyle(.tertiary)
                            Text(reply)
                                .font(FleetFont.subtitle)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 1)
                    } else if message.needsReply {
                        if isReplying {
                            HStack(spacing: 6) {
                                TextField("Your answer…", text: $replyText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .font(FleetFont.subtitle)
                                    .lineLimit(1...4)
                                    .focused($replyFocused)
                                    .onSubmit(send)
                                Button("Send", action: send)
                                    .controlSize(.small)
                                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                                Button("Cancel") { replyingTo = nil; replyText = "" }
                                    .controlSize(.small)
                            }
                            .padding(.top, 2)
                        } else {
                            Button("Reply…") {
                                replyingTo = message
                                replyText = ""
                                replyFocused = true
                            }
                            .buttonStyle(.link)
                            .font(FleetFont.subtitle)
                        }
                    }
                }
            }
            .padding(.horizontal, FleetMetrics.rowInset)
            .padding(.vertical, 5)
        }
        .background(
            RoundedRectangle(cornerRadius: FleetMetrics.corner)
                .fill(message.isAwaitingReply
                      ? StatusTone.warn.wash : Color.clear)
        )
        .padding(.horizontal, FleetMetrics.rowHighlightMargin)
    }

    private func send() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.reply(to: message, with: text)
        replyingTo = nil
        replyText = ""
    }
}
