import SwiftUI
import AppKit
import FleetCore

/// Ownership IDs are a local address book. Detected sessions and the mailbox
/// remain evidence from their existing sources, never fabricated by registration.
struct AgentsContent: View {
    @Bindable var model: AppModel
    // Kept for existing callers; agent overflow never routes to the dashboard.
    var openDashboard: () -> Void
    var registration: AgentRegistrationModel = .shared
    @State private var sheet: AgentSheet?

    var body: some View {
        AgentGlanceContent(profiles: model.agentProfiles, sessions: model.sessions,
                           registration: registration,
                           pendingReplyCount: model.awaitingReplies.count,
                           messageCount: Set(model.awaitingReplies.map(\.id) + model.recentMessages.map(\.id)).count,
                           register: { sheet = .register }, mailbox: { sheet = .mailbox },
                           manage: { sheet = .manage })
            .sheet(item: $sheet) { destination in
                if destination == .mailbox {
                    AgentsMailboxSheet(model: model)
                } else {
                    AgentsManagerSheet(model: model, registration: registration,
                                       startRegistration: destination == .register)
                }
            }
            .onAppear { registration.reload() }
    }

    private enum AgentSheet: String, Identifiable {
        case register, manage, mailbox
        var id: String { rawValue }
    }
}

/// No scroll view, expanding detail, or inline editor belongs in the menu glance.
/// Five 36pt rows plus the controls and explicit overflow fit the 300pt viewport.
struct AgentGlanceContent: View {
    var profiles: [AgentProfile]
    var sessions: [AgentSession]
    var registration: AgentRegistrationModel
    var pendingReplyCount: Int
    var messageCount: Int
    var register: () -> Void
    var mailbox: () -> Void
    var manage: () -> Void

    private var roster: AgentGlanceRoster {
        AgentGlanceRoster(registeredIDs: registration.registeredIDs, profiles: profiles, sessions: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: register) { Label("Register Agent ID", systemImage: "plus") }
                    .controlSize(.small)
                    .help(registration.statusIsError ? (registration.status ?? "Open the agent manager")
                          : "Save an exact ownership ID locally; this does not start a session.")
                Spacer(minLength: 4)
                Button(pendingReplyCount > 0 ? "\(pendingReplyCount) waiting" : "Messages (\(messageCount))", action: mailbox)
                    .controlSize(.small)
                    .foregroundStyle(pendingReplyCount > 0 ? StatusTone.warn.ink : Color.primary)
                    .help("\(pendingReplyCount) pending replies; \(messageCount) messages. Open the full mailbox.")
            }
            .padding(.horizontal, FleetMetrics.gutter)
            .frame(height: 36)

            Text(registration.statusIsError
                 ? "Saved IDs unavailable · \(roster.detectedCount) detected sessions"
                 : "\(roster.ownerCount) agent IDs · \(roster.detectedCount) detected sessions")
                .font(FleetFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, FleetMetrics.gutter)
                .frame(height: 20, alignment: .leading)

            if roster.entries.isEmpty {
                EmptyLine(text: "No registered IDs or detected sessions.")
            } else {
                ForEach(roster.visibleEntries) { entry in
                    Button(action: manage) {
                        switch entry {
                        case .owner(let owner):
                            CompactRow(icon: "person.crop.square", tone: .neutral, title: owner.id,
                                       subtitle: owner.profile?.headline ?? "Idle",
                                       trailing: owner.isRegistered ? "Registered" : "Managed")
                                .help("Agent ID: \(owner.id)")
                        case .session(let session):
                            CompactRow(icon: session.symbol, tone: .good, title: session.tool,
                                       subtitle: session.sessionName ?? (session.project == nil ? "Local session" : session.projectName),
                                       trailing: session.sessionUID.map { String($0.prefix(8)) } ?? "Detected",
                                       agentTool: session.tool)
                                .help("Detected session: \(session.sessionUID ?? session.id)")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(roster.overflowCount > 0
                   ? "Show all \(roster.totalCount) (\(roster.overflowCount) more)" : "Manage agents…", action: manage)
                .buttonStyle(.link)
                .font(FleetFont.caption)
                .padding(.horizontal, FleetMetrics.gutter)
                .frame(height: 32, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(height: 300, alignment: .top)
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

/// Current inbox is distinct from persisted history, which stays reachable.
struct AgentsMailboxSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var replyingTo: AgentMessage?
    @State private var replyText = ""
    @State private var showHistory = false
    @FocusState private var replyFocused: Bool

    private var pendingIDs: Set<Int64> { Set(model.awaitingReplies.map(\.id)) }
    private var answered: [AgentMessage] {
        (showHistory ? model.messageHistory : model.recentMessages).filter { !pendingIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(showHistory ? "Message history" : "Inbox") (\(pendingIDs.count + answered.count))").font(FleetFont.title)
                Spacer()
                Toggle("History", isOn: $showHistory)
                    .toggleStyle(.button)
                    .accessibilityIdentifier("mailbox.history")
                    .help("Include old seen notices and resolved questions. Nothing is deleted.")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(FleetMetrics.gutter)
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !model.connected {
                        EmptyLine(text: showHistory
                                  ? "Controller unavailable — showing last received history."
                                  : "Controller unavailable — message state is unknown.")
                            .accessibilityIdentifier("mailbox.unavailable")
                    }
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
                        if model.connected || showHistory {
                            EmptyLine(text: showHistory ? "No message history." : "No current messages.")
                                .accessibilityIdentifier("mailbox.empty")
                        }
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
