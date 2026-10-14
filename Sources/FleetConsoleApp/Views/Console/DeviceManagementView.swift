import SwiftUI
import AppKit
import FleetCore

struct DeviceManagementView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var user = ""
    @State private var readServices = false
    @State private var busy = false
    @State private var error: String?
    @State private var pendingRemoval: FleetConfig.DeviceConfig?
    @State private var savedName: String?
    @State private var needsReload = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, address, user }

    private var linked: [FleetConfig.DeviceConfig] { model.settings.config.devices.filter { !$0.isSelf } }
    private var request: DeviceLinkRequest {
        DeviceLinkRequest(name: name, address: address, sshUser: user, readServices: readServices)
    }
    private var validationError: String? {
        do { _ = try request.device(existing: model.settings.config.devices); return nil }
        catch FleetError.rejected(let message) { return message }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Devices", systemImage: "desktopcomputer")
                    .font(ConsoleFont.moduleTitle)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    .disabled(busy)
            }
            .padding(ConsoleMetrics.gutter)
            Divider()
            Form {
                Section("Ouros Account") {
                    LabeledContent("Multi-device", value: "US$10/month")
                    Label(model.ourosBilling.active ? "Subscription active"
                          : model.ourosBilling.signedIn ? "Signed in · subscription required" : "Sign in to link your computers",
                          systemImage: model.ourosBilling.active ? "checkmark.circle" : "person.crop.circle")
                    Text("Local monitoring is free. Multi-device access is billed monthly through Ouros. AI credits are purchased separately.")
                        .font(ConsoleFont.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack { accountControls }
                        VStack(alignment: .leading, spacing: 8) { accountControls }
                    }
                    .disabled(model.ourosBilling.busy)
                    if let message = model.ourosBilling.message {
                        Label(message, systemImage: "info.circle")
                            .font(ConsoleFont.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Link a Device") {
                    LabeledContent("Name") {
                        TextField("Mac Studio", text: $name)
                            .labelsHidden().accessibilityLabel("Device name")
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .address }
                    }
                    LabeledContent("Address") {
                        TextField("Hostname or IP address", text: $address)
                            .labelsHidden().accessibilityLabel("Hostname or IP address")
                            .focused($focusedField, equals: .address)
                            .onSubmit { focusedField = .user }
                    }
                    LabeledContent("SSH user") {
                        TextField("Optional", text: $user)
                            .labelsHidden().accessibilityLabel("SSH username, optional")
                            .focused($focusedField, equals: .user)
                    }
                    Toggle("Read its FleetConsole service inventory", isOn: $readServices)
                        .toggleStyle(.checkbox)
                    Text("Checks reachability over the network. Optional service inventory uses your existing SSH configuration.")
                        .font(ConsoleFont.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(StatusTone.bad.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if needsReload {
                        Button("Retry Controller Reload") { reloadController() }
                            .disabled(busy)
                    }

                }
                .disabled(!model.ourosBilling.active || busy)
                if !linked.isEmpty {
                    Section("Linked Devices") {
                        ForEach(linked, id: \.id) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name)
                                    Text(device.localHost ?? device.tailscaleHost ?? "No address")
                                        .font(ConsoleFont.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button("Unlink", role: .destructive) { pendingRemoval = device }
                                    .disabled(busy)
                                    .accessibilityLabel("Unlink \(device.name)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 8) {
                if busy || model.ourosBilling.busy { ProgressView().controlSize(.small) }
                Text(busy ? "Updating devices…"
                     : !model.ourosBilling.signedIn ? "Sign in, subscribe, then link a device."
                     : !model.connected ? "Connect the local controller to link a device."
                     : !model.ourosBilling.active ? "Subscribe to link additional devices."
                     : savedName.map { "\($0) linked." } ?? (name.isEmpty && address.isEmpty
                         ? "Enter a name and address to get started."
                         : validationError ?? "Ready to link this device."))
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(primaryTitle) { primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryDisabled)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ConsoleMetrics.gutter)
        }
        .frame(width: 600, height: 650)
        .sketchSubstrate()
        .task { await model.ourosBilling.refresh(userInitiated: true) }
        .sheet(isPresented: Binding(
            get: { model.ourosBilling.userCode != nil },
            set: { if !$0 { model.ourosBilling.cancelConnection() } })) {
                OurosConnectionView(billing: model.ourosBilling)
            }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.ourosBilling.refresh(userInitiated: false) }
        }
        .alert("Unlink \(pendingRemoval?.name ?? "device")?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
                Button("Unlink", role: .destructive) {
                    guard let id = pendingRemoval?.id else { return }
                    pendingRemoval = nil
                    save { try DeviceLinkStore.unlink(id, at: FleetPaths.config) }
                }
            } message: {
                Text("Removes this computer from FleetConsole. Its processes and files are untouched.")
            }
    }

    @ViewBuilder private var accountControls: some View {
        if model.ourosBilling.active {
            Button("Manage Subscription…") { Task { await model.ourosBilling.manage() } }
        }
        Button("AI Credits…") {
            NSWorkspace.shared.open(URL(string: "https://ouros.md/dashboard#/billing")!)
        }
        Button("Refresh") { Task { await model.ourosBilling.refresh(userInitiated: true) } }
        if model.ourosBilling.signedIn {
            Button("Sign Out") { Task { await model.ourosBilling.disconnect() } }
        }
    }

    private var primaryTitle: String {
        if !model.ourosBilling.signedIn { return "Sign In to Ouros…" }
        if !model.ourosBilling.active { return "Subscribe for $10/month…" }
        return busy ? "Linking…" : "Link Device"
    }

    private var primaryDisabled: Bool {
        if busy || model.ourosBilling.busy { return true }
        if !model.ourosBilling.signedIn { return false }
        if !model.ourosBilling.active { return !model.ourosBilling.available }
        return !model.connected || validationError != nil || !DaemonClient.shared.requestPolicy.allows(.reloadConfig)
    }

    private func primaryAction() {
        guard !primaryDisabled else { return }
        if !model.ourosBilling.signedIn { model.ourosBilling.connect() }
        else if !model.ourosBilling.active { Task { await model.ourosBilling.subscribe() } }
        else { link() }
    }

    private func link() {
        let linkedName = name
        save {
            _ = try DeviceLinkStore.link(request, at: FleetPaths.config)
        } completion: {
            savedName = linkedName
            name = ""; address = ""; user = ""; readServices = false
        }
    }

    private func save(_ write: () throws -> Void, completion: @escaping () -> Void = {}) {
        error = nil; savedName = nil
        do { try write(); model.settings.reload() }
        catch { self.error = error.localizedDescription; return }
        reloadController(completion: completion)
    }

    private func reloadController(completion: @escaping () -> Void = {}) {
        busy = true
        DaemonClient.shared.send(RPCRequest(op: .reloadConfig)) { result in
            busy = false
            switch result {
            case .success(let response) where response.ok:
                needsReload = false
                error = nil
                model.refreshDevices()
                completion()
            case .success(let response):
                needsReload = true
                error = "Saved, but the controller could not reload: \(response.error ?? "unknown error"). Choose Retry Controller Reload."
            case .failure(let failure):
                needsReload = true
                error = "Saved, but the controller could not reload: \(failure.localizedDescription). Choose Retry Controller Reload."
            }
        }
    }
}

private struct OurosConnectionView: View {
    @Bindable var billing: OurosBilling
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect your Ouros account").font(ConsoleFont.moduleTitle)
            Text("Approve the matching code in your browser. Keep FleetConsole open while you connect.")
                .fixedSize(horizontal: false, vertical: true)
            Text(billing.userCode ?? "").font(.title2.monospaced())
                .textSelection(.enabled).accessibilityLabel("Connection code")
            ProgressView("Waiting for your approval…")
                .controlSize(.small)
            HStack {
                Button("Cancel") { billing.cancelConnection() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue in Ouros…") {
                    if let url = billing.verificationURL { NSWorkspace.shared.open(url) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(ConsoleMetrics.gutter)
        .frame(width: 420)
        .sketchSubstrate()
    }
}
