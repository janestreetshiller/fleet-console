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
                Section("Link a Device") {
                    TextField("Device name", text: $name)
                    TextField("Hostname or IP address", text: $address)
                    TextField("SSH username (optional)", text: $user)
                    Toggle("Read its FleetConsole service inventory", isOn: $readServices)
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
                Section("Linked Devices") {
                    if linked.isEmpty {
                        Text("No additional devices linked.").foregroundStyle(.secondary)
                    }
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
                Section("Ouros") {
                    HStack {
                        Text("Multi-device")
                        Spacer()
                        Text("$10/month").foregroundStyle(.secondary)
                    }
                    Text(model.ourosBilling.active ? "Multi-device is active on your Ouros account." : "Local monitoring is free.")
                        .font(ConsoleFont.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if !model.ourosBilling.signedIn {
                            Button("Connect Ouros Account…") { model.ourosBilling.connect() }
                        } else if model.ourosBilling.active {
                            Button("Manage Subscription…") { Task { await model.ourosBilling.manage() } }
                        } else {
                            Button("Subscribe — $10/month…") { Task { await model.ourosBilling.subscribe() } }
                                .disabled(!model.ourosBilling.available)
                        }
                        Button("Refresh") { Task { await model.ourosBilling.refresh() } }
                        if model.ourosBilling.signedIn {
                            Button("Disconnect") { Task { await model.ourosBilling.disconnect() } }
                        }
                    }
                    .disabled(model.ourosBilling.busy)
                    if let message = model.ourosBilling.message {
                        Text(message).font(ConsoleFont.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Manage AI Credits…") {
                        NSWorkspace.shared.open(URL(string: "https://ouros.md/dashboard#/billing")!)
                    }
                    .help("Open your Ouros billing and AI credits account")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(busy ? "Updating devices…"
                     : !model.connected ? "Connect the local controller to link a device."
                     : !model.ourosBilling.active ? "Subscribe to link additional devices."
                     : savedName.map { "\($0) linked." } ?? (name.isEmpty && address.isEmpty
                         ? "Enter a name and address to get started."
                         : validationError ?? "Ready to link this device."))
                    .font(ConsoleFont.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(busy ? "Saving…" : "Link Device") { link() }
                    .disabled(busy || !model.connected || !model.ourosBilling.active || validationError != nil
                              || !DaemonClient.shared.requestPolicy.allows(.reloadConfig))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ConsoleMetrics.gutter)
        }
        .frame(width: 560, height: 650)
        .task { await model.ourosBilling.refresh() }
        .sheet(isPresented: Binding(
            get: { model.ourosBilling.userCode != nil },
            set: { if !$0 { model.ourosBilling.cancelConnection() } })) {
                OurosConnectionView(billing: model.ourosBilling)
            }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.ourosBilling.refresh() }
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
            HStack {
                Button("Cancel") { billing.cancelConnection() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue in Ouros…") {
                    if let url = billing.verificationURL { NSWorkspace.shared.open(url) }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(ConsoleMetrics.gutter)
        .frame(width: 420)
    }
}
