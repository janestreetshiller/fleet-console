import SwiftUI
import AppKit
import FleetCore

@Observable
@MainActor
final class TaskComposerModel {
    var taskName = ""
    var ownerAgent = "operator"
    var purpose = ""
    var command = ""
    var cwd = FileManager.default.homeDirectoryForCurrentUser.path
    var leaseMinutes = 120
    var port: String = ""
    var healthURL = ""

    var status: String?
    var statusIsError = false
    var isSubmitting = false

    var agentOptions: [String] {
        let names = Set(agentProfiles.map(\.id) + registration.registeredIDs)
        return ["operator"] + names.filter { $0 != "operator" }.sorted()
    }

    init(agentProfiles: [AgentProfile] = [], registration: AgentRegistrationModel = .shared) {
        self.agentProfiles = agentProfiles
        self.registration = registration
    }

    private var agentProfiles: [AgentProfile]
    private let registration: AgentRegistrationModel

    func reconcileOwnerAgent() {
        if !agentOptions.contains(ownerAgent) { ownerAgent = "operator" }
    }

    func validated() -> LaunchRequest? {
        let name = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            status = "Give the task a name."; statusIsError = true; return nil
        }
        let parts = command.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard !parts.isEmpty else {
            status = "Give the task a command to run."; statusIsError = true; return nil
        }
        let ports = port.trimmingCharacters(in: .whitespaces).isEmpty
            ? [] : [Int(port.trimmingCharacters(in: .whitespaces)) ?? 0]
        if ports.contains(0) {
            status = "Port must be a number."; statusIsError = true; return nil
        }
        var health = HealthSpec()
        if !healthURL.isEmpty {
            health = HealthSpec(kind: .http, target: healthURL,
                                intervalSec: 15, timeoutSec: 4, expectStatus: 200, failureThreshold: 3)
        }
        return LaunchRequest(
            friendlyName: name,
            ownerAgent: ownerAgent.trimmingCharacters(in: .whitespaces).isEmpty ? "operator" : ownerAgent,
            purpose: purpose.trimmingCharacters(in: .whitespaces).isEmpty ? "user task" : purpose,
            command: parts,
            cwd: cwd.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : cwd,
            env: [:],
            declaredPorts: ports,
            leaseTTLSec: Double(leaseMinutes * 60),
            budget: ResourceBudget(),
            health: health)
    }

    func submit() {
        guard let request = validated() else { return }
        isSubmitting = true
        status = nil
        DaemonClient.shared.launch(request) { [weak self] result in
            guard let self else { return }
            self.isSubmitting = false
            switch result {
            case .success(let response):
                if let service = response.service {
                    self.status = "Launched “\(service.friendlyName)” — pid \(service.pid.map(String.init) ?? "…")"
                    self.statusIsError = false
                } else {
                    self.status = response.error ?? "Launch returned no service."
                    self.statusIsError = true
                }
            case .failure(let error):
                self.status = error.localizedDescription
                self.statusIsError = true
            }
        }
    }
}

struct TaskComposerView: View {
    @Bindable var model: TaskComposerModel
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: ConsoleMetrics.panelInset) {
                    taskSection
                    assignmentSection
                    runSection
                }
                .padding(ConsoleMetrics.panelInset)
            }
            Hairline()
            footer
        }
        .frame(width: 480, height: 560)
        .sketchSubstrate(seed: 0.37, grainSeed: 37)
        .onChange(of: model.agentOptions) { _, _ in model.reconcileOwnerAgent() }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(FleetFont.rowTitle).foregroundStyle(.primary)
            Text("New Task")
                .font(ConsoleFont.cardTitle)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.link).font(FleetFont.subtitle)
        }
        .padding(.horizontal, ConsoleMetrics.gutter)
        .padding(.vertical, ConsoleMetrics.panelInset)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Task")
            TextField("A short name — e.g. “embed index”", text: $model.taskName)
                .textFieldStyle(.roundedBorder).font(FleetFont.body)
            fieldLabel("Category / purpose")
            TextField("e.g. “local api”, “build”", text: $model.purpose)
                .textFieldStyle(.roundedBorder).font(FleetFont.body)
        }
        .plate("TASK")
    }

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Assign to agent")
            Picker("Agent", selection: $model.ownerAgent) {
                ForEach(model.agentOptions, id: \.self) { agent in
                    Text(agent).tag(agent)
                }
            }
            .pickerStyle(.menu).font(FleetFont.body).frame(maxWidth: .infinity, alignment: .leading)
        }
        .plate("ASSIGN")
    }

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Command")
            TextField("e.g. python3 -m http.server", text: $model.command)
                .textFieldStyle(.roundedBorder).font(FleetFont.body)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Working directory")
                    TextField("Working directory", text: $model.cwd)
                        .textFieldStyle(.roundedBorder).font(FleetFont.body)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Lease (min)")
                    Stepper("\(model.leaseMinutes) min", value: $model.leaseMinutes, in: 5...1440)
                        .font(FleetFont.body).fixedSize()
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Port (optional)")
                    TextField("", text: $model.port)
                        .textFieldStyle(.roundedBorder).font(FleetFont.body)
                        .frame(width: 90)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Health check URL (optional)")
                    TextField("http://127.0.0.1:PORT/healthz", text: $model.healthURL)
                        .textFieldStyle(.roundedBorder).font(FleetFont.body)
                }
            }
        }
        .plate("RUN")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let status = model.status {
                Text(status)
                    .font(FleetFont.caption)
                    .foregroundStyle(model.statusIsError ? StatusTone.bad.ink : Color.primary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Launch Task") {
                model.submit()
                if model.status != nil, !model.statusIsError {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
                }
            }
            .fleetPrimaryAction()
            .controlSize(.regular)
            .disabled(model.isSubmitting || model.taskName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, ConsoleMetrics.gutter)
        .padding(.vertical, ConsoleMetrics.panelInset)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(FleetFont.subtitle)
            .foregroundStyle(.secondary)
    }
}

@MainActor
final class TaskComposerWindowController: NSObject, NSWindowDelegate {
    private let model: TaskComposerModel
    private var window: NSWindow?

    init(agentProfiles: [AgentProfile]) {
        self.model = TaskComposerModel(agentProfiles: agentProfiles)
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = TaskComposerView(model: model) { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 480, height: 560)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "New Task"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = hosting
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
