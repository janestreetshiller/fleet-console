import SwiftUI
import AppKit
import FleetCore

/// Ownership IDs are a local address book. Detected sessions and the mailbox
/// remain evidence from their existing sources, never fabricated by registration.
struct AgentsContent: View {
    @Bindable var model: AppModel
    var openDashboard: () -> Void
    var registration: AgentRegistrationModel = .shared
    var fixer: FixAgentSettings = .shared
    @State private var sheet: AgentSheet?
    @State private var fixerProblem: String?

    var body: some View {
        AgentGlanceContent(profiles: model.agentProfiles, sessions: model.sessions,
                           registration: registration,
                           pendingReplyCount: model.awaitingReplies.count,
                           messageCount: Set(model.awaitingReplies.map(\.id) + model.recentMessages.map(\.id)).count,
                           messages: latestMessages,
                           problemCount: model.attention.count,
                           fixer: fixer, billing: model.ourosBilling,
                           register: { sheet = .register }, mailbox: { sheet = .mailbox },
                           manage: { sheet = .manage },
                           dismiss: { model.dismissMessages($0) },
                           sendToFixer: { fixerProblem = model.sendToFixer(model.attention, openDashboard: openDashboard) })
            .sheet(item: $sheet) { destination in
                if destination == .mailbox {
                    AgentsMailboxSheet(model: model)
                } else {
                    AgentsManagerSheet(model: model, registration: registration,
                                       startRegistration: destination == .register)
                }
            }
            .alert("Can't hand this off", isPresented: Binding(get: { fixerProblem != nil },
                                                                 set: { if !$0 { fixerProblem = nil } })) {
                Button("OK", role: .cancel) { fixerProblem = nil }
            } message: { Text(fixerProblem ?? "") }
            .onAppear {
                registration.reload()
                fixer.reload()
                Task { await model.ourosBilling.refresh() }
            }
    }

    /// Waiting-for-you first, then the newest of everything else.
    private var latestMessages: [AgentMessage] {
        var seen = Set<Int64>()
        return (model.awaitingReplies + model.recentMessages.sorted { $0.createdAt > $1.createdAt })
            .filter { seen.insert($0.id).inserted }
    }

    private enum AgentSheet: String, Identifiable {
        case register, manage, mailbox
        var id: String { rawValue }
    }
}

/// The Agents tab: who fixes things, what the agents are saying, who they are,
/// and the hosted fixer. No scroll view, expanding detail or inline editor —
/// four bands that fit the 300pt body, with the full roster and the mailbox one
/// click away in their sheets.
struct AgentGlanceContent: View {
    var profiles: [AgentProfile]
    var sessions: [AgentSession]
    var registration: AgentRegistrationModel
    var pendingReplyCount: Int
    var messageCount: Int
    var messages: [AgentMessage] = []
    var problemCount: Int = 0
    var fixer: FixAgentSettings?
    var billing: OurosBilling?
    var register: () -> Void
    var mailbox: () -> Void
    var manage: () -> Void
    var dismiss: ([Int64]) -> Void = { _ in }
    var sendToFixer: () -> Void = {}

    static let visibleMessages = 3

    private var roster: AgentGlanceRoster {
        AgentGlanceRoster(registeredIDs: registration.registeredIDs, profiles: profiles, sessions: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fixer { FixerRow(settings: fixer, problemCount: problemCount, send: sendToFixer) }

            HStack(spacing: 8) {
                Text("Messages").font(FleetFont.sectionLabel)
                Spacer(minLength: 4)
                if !messages.isEmpty {
                    Button("Clear") { dismiss(messages.map(\.id)) }
                        .buttonStyle(.plain)
                        .font(FleetFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .help("Dismiss every message from this list. Agents keep their history in fleetctl inbox.")
                        .accessibilityIdentifier("agents.messages.clear")
                }
                Button(pendingReplyCount > 0 ? "\(pendingReplyCount) waiting" : "Mailbox (\(messageCount))",
                       action: mailbox)
                    .controlSize(.small)
                    .foregroundStyle(pendingReplyCount > 0 ? StatusTone.warn.ink : Color.primary)
                    .help("\(pendingReplyCount) pending replies; \(messageCount) messages. Open the full mailbox.")
            }
            VStack(alignment: .leading, spacing: 2) {
                if messages.isEmpty {
                    Text("No messages yet. Agents post here with fleetctl notify.")
                        .font(FleetFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .frame(height: 28, alignment: .leading)
                } else {
                    ForEach(messages.prefix(Self.visibleMessages)) { message in
                        HStack(spacing: 2) {
                            Button(action: mailbox) { AgentMessageLine(message: message) }
                                .buttonStyle(.plain)
                            IconButton(symbol: "xmark", help: "Dismiss this message") { dismiss([message.id]) }
                                .accessibilityIdentifier("agents.message.dismiss.\(message.id)")
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Text(registration.statusIsError
                     ? "Saved IDs unavailable · \(roster.detectedCount) detected sessions"
                     : "\(roster.ownerCount) agent IDs · \(roster.detectedCount) detected sessions")
                    .font(FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: register) { Label("Register Agent ID", systemImage: "plus") }
                    .controlSize(.small)
                    .help(registration.statusIsError ? (registration.status ?? "Open the agent manager")
                          : "Save an exact ownership ID locally; this does not start a session.")
                Button(roster.totalCount > 0 ? "Show all \(roster.totalCount)" : "Manage…", action: manage)
                    .controlSize(.small)
            }

            Spacer(minLength: 0)
            if let billing { CloudAgentCard(billing: billing) }
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.vertical, 10)
        .frame(height: 300, alignment: .top)
    }
}

/// The designated fixer and the one action it exists for.
struct FixerRow: View {
    @Bindable var settings: FixAgentSettings
    var problemCount: Int
    var send: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(SurfaceInk.secondary)
            Text("Fixer").font(FleetFont.sectionLabel)
            if settings.installed.isEmpty {
                Text("None installed")
                    .font(FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .help("Install Claude Code, Codex or fleet-agent to hand problems to it.")
            } else {
                Picker("Fixer", selection: $settings.designated) {
                    Text("None").tag(Optional<FixAgentKind>.none)
                    ForEach(settings.installed) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .accessibilityLabel("Designated fixer")
            }
            Spacer(minLength: 4)
            Button(action: send) {
                Text(problemCount == 0 ? "Nothing to fix"
                     : "Send \(problemCount) problem\(problemCount == 1 ? "" : "s")")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(problemCount == 0 || settings.designated == nil)
            .help(settings.designated == .fleetAgent
                  ? "Ask Fleet Agent for a read-only proposal in the dashboard terminal."
                  : "Write a report of what needs attention and start the fixer on it in the dashboard terminal.")
            .accessibilityIdentifier("agents.fixer.send")
        }
        .frame(height: 28)
    }
}

/// One mailbox entry on one line: who, what kind when it matters, what, when.
struct AgentMessageLine: View {
    let message: AgentMessage

    private var tone: StatusTone? {
        if message.isAwaitingReply { return .warn }
        return message.kind == .problem ? .bad : nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(message.agent)
                .font(FleetFont.rowTitleCompact.weight(.medium))
                .lineLimit(1)
                .fixedSize()
            if message.kind != .status {
                Text(message.kind.label)
                    .font(FleetFont.micro)
                    .foregroundStyle(tone?.ink ?? SurfaceInk.secondary)
                    .fixedSize()
            }
            Text(message.body)
                .font(FleetFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(Fmt.relative(message.createdAt))
                .font(FleetFont.caption)
                .monospacedDigit()
                .foregroundStyle(SurfaceInk.secondary)
                .fixedSize()
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .help("\(message.agent): \(message.body)")
        .accessibilityElement(children: .combine)
    }
}

/// The hosted fixer, priced by the Ouros catalog. Each state says the one next
/// step: connect, start, or that this account is not offered it yet.
struct CloudAgentCard: View {
    @Bindable var billing: OurosBilling

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(FleetFont.title)
                .foregroundStyle(SurfaceInk.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cloud Agent").font(FleetFont.rowTitleCompact.weight(.semibold))
                Text("Fix reports go to an Ouros-hosted agent, so fixes keep going when this Mac sleeps.")
                    .font(FleetFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            action
        }
        .padding(10)
        .background(FleetColor.surfaceWash,
                    in: RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FleetMetrics.tileCorner, style: .continuous)
                .strokeBorder(ConsoleColor.hairline, lineWidth: 1)
        }
        .help(billing.message ?? "Billed through your Ouros account.")
    }

    @ViewBuilder private var action: some View {
        if billing.busy {
            ProgressView().controlSize(.small)
        } else if !billing.signedIn {
            Button("Connect Ouros…") { billing.connect() }
                .controlSize(.small)
        } else if let offer = billing.cloudAgentOffer {
            Button("Start · \(offer.priceLabel)") {
                Task { await billing.subscribe(offerID: offer.id) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Text("Not offered on\nyour account yet")
                .font(FleetFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize()
        }
    }
}

/// The complete roster and detected sessions live outside the fixed menu budget.
struct AgentsManagerSheet: View {
    @Bindable var model: AppModel
    var registration: AgentRegistrationModel
    var startRegistration = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents").font(FleetFont.title)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(FleetMetrics.gutter)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AgentRosterSection(profiles: model.agentProfiles, registration: registration,
                                       startRegistration: startRegistration)
                    if !model.sessions.isEmpty {
                        CompactHeader(title: "Detected sessions", trailing: "\(model.sessions.count)")
                        ForEach(model.sessions) { session in
                            HStack(spacing: FleetMetrics.rowGap) {
                                EntityIcon(symbol: session.symbol, tone: .good, size: FleetMetrics.iconCompact)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.tool).font(FleetFont.rowTitleCompact)
                                    Text(session.sessionUID ?? session.id)
                                        .font(FleetFont.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                IconButton(symbol: "doc.on.doc", help: "Copy session ID") {
                                    registration.copyID(session.sessionUID ?? session.id)
                                }
                            }
                            .padding(.horizontal, FleetMetrics.gutter)
                            .padding(.vertical, FleetMetrics.rowVerticalPadding)
                        }
                    } else {
                        EmptyLine(text: "No sessions detected.")
                    }
                }
            }
        }
        .frame(width: 560, height: 520)
    }
}

/// All provided messages remain reachable, with pending replies first. Reuse the
/// existing reply loop rather than routing into a nonexistent dashboard module.
struct AgentsMailboxSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var replyingTo: AgentMessage?
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    private var pendingIDs: Set<Int64> { Set(model.awaitingReplies.map(\.id)) }
    private var answered: [AgentMessage] { model.recentMessages.filter { !pendingIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mailbox (\(pendingIDs.count + answered.count))").font(FleetFont.title)
                Spacer()
                if !model.recentMessages.isEmpty {
                    Button("Clear All") { model.dismissMessages(model.recentMessages.map(\.id)) }
                        .help("Dismiss every message here. Agents keep their history in fleetctl inbox.")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(FleetMetrics.gutter)
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !model.awaitingReplies.isEmpty {
                        CompactHeader(title: "Waiting on you", trailing: "\(model.awaitingReplies.count)")
                        ForEach(model.awaitingReplies) { message in
                            MessageRow(message: message, model: model, replyingTo: $replyingTo,
                                       replyText: $replyText, replyFocused: $replyFocused)
                        }
                    }
                    ForEach(answered) { message in
                        MessageRow(message: message, model: model, replyingTo: $replyingTo,
                                   replyText: $replyText, replyFocused: $replyFocused)
                    }
                    if model.awaitingReplies.isEmpty && answered.isEmpty {
                        EmptyLine(text: "No messages yet.")
                    }
                }
                .padding(.vertical, FleetMetrics.rowVerticalPadding)
            }
        }
        .frame(width: 560, height: 520)
    }
}

/// The registration workflow is usable even when the controller is offline and
/// the roster is empty. The same observable roster feeds the task composer.
struct AgentRosterSection: View {
    var profiles: [AgentProfile]
    @Bindable var registration: AgentRegistrationModel

    @State private var showingRegistration = false
    @FocusState private var agentIDFocused: Bool

    init(profiles: [AgentProfile], registration: AgentRegistrationModel, startRegistration: Bool = false) {
        self.profiles = profiles
        self.registration = registration
        _showingRegistration = State(initialValue: startRegistration)
    }

    private var entries: [AgentRosterEntry] {
        AgentRosterEntry.merge(registeredIDs: registration.registeredIDs, profiles: profiles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    showingRegistration.toggle()
                    agentIDFocused = showingRegistration
                } label: {
                    Label("Register Agent ID", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("agents.register.open")
                .help("Save an exact agent ID locally for task ownership. Registration does not start or detect a session.")
                Spacer(minLength: 4)
                if !registration.registeredIDs.isEmpty {
                    Text("\(registration.registeredIDs.count) registered")
                        .font(FleetFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showingRegistration {
                HStack(spacing: 8) {
                    TextField("e.g. codex-worker", text: $registration.agentID)
                        .textFieldStyle(.roundedBorder)
                        .font(FleetFont.body)
                        .focused($agentIDFocused)
                        .accessibilityLabel("Agent ID")
                        .accessibilityIdentifier("agents.register.input")
                        .help("Use 1–128 letters, numbers, dots, hyphens or underscores, starting with a letter or number. IDs are case-sensitive; use the same ID as your task owner.")
                        .onSubmit(register)
                    Button("Register", action: register)
                        .controlSize(.small)
                        .disabled(registration.agentID.isEmpty)
                        .accessibilityIdentifier("agents.register.submit")
                    Button("Cancel", action: cancel)
                        .controlSize(.small)
                        .accessibilityIdentifier("agents.register.cancel")
                }
                .onExitCommand(perform: cancel)
            }


            if let status = registration.status {
                Text(status)
                    .font(FleetFont.caption)
                    .foregroundStyle(registration.statusIsError ? StatusTone.bad.ink : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("agents.register.status")
            }
        }
        .padding(.horizontal, FleetMetrics.gutter)
        .padding(.vertical, FleetMetrics.rowVerticalPadding)

        ForEach(entries) { entry in
            HStack(spacing: FleetMetrics.rowGap) {
                EntityIcon(symbol: "person.crop.square", tone: .neutral, size: FleetMetrics.iconCompact)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.id)
                            .font(FleetFont.rowTitleCompact)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(entry.id)
                            .accessibilityIdentifier("agents.id.\(entry.id)")
                        Tag(text: entry.isRegistered ? "Registered" : "Managed", tone: .neutral)
                    }
                    Text(entry.profile?.headline ?? "Idle · no managed work recorded")
                        .font(FleetFont.subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    IconButton(symbol: "doc.on.doc", help: "Copy agent ID \(entry.id)") {
                        registration.copyID(entry.id)
                    }
                    .accessibilityIdentifier("agents.copy.\(entry.id)")
                    if entry.isRegistered {
                        IconButton(symbol: "minus.circle", help: "Remove registered ID \(entry.id)") {
                            registration.remove(entry.id)
                        }
                        .accessibilityIdentifier("agents.remove.\(entry.id)")
                    } else {
                        Color.clear.frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: FleetMetrics.actionSlot)
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .padding(.vertical, FleetMetrics.rowVerticalPadding)
        }
    }

    private func register() {
        if registration.register() {
            showingRegistration = false
            agentIDFocused = false
        }
    }

    private func cancel() {
        showingRegistration = false
        agentIDFocused = false
        registration.agentID = ""
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
                        Text(message.kind.label).font(FleetFont.micro).foregroundStyle(SurfaceInk.secondary)
                        if let name = message.serviceName {
                            Text("· \(name)").font(FleetFont.micro).foregroundStyle(SurfaceInk.secondary)
                        }
                        Spacer()
                        Text(Fmt.relative(message.createdAt))
                            .font(FleetFont.micro).foregroundStyle(SurfaceInk.secondary)
                        IconButton(symbol: "xmark", help: "Dismiss this message") {
                            model.dismissMessages([message.id])
                        }
                    }
                    Text(message.body)
                        .font(FleetFont.subtitle)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let reply = message.reply {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(FleetFont.marker).foregroundStyle(SurfaceInk.secondary)
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
