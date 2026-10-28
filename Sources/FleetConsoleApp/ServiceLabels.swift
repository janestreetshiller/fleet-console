import Foundation
import Observation
import SwiftUI
import AppKit
import FleetCore

/// Local presentation preferences shared by popover and dashboard, never sent over RPC.
@MainActor
@Observable
final class ServiceLabelsStore {
    static let shared = ServiceLabelsStore()

    @ObservationIgnored let path: URL
    private var labels: [String: ServiceLabel] = [:]
    private(set) var loadError: String?

    init(path: URL = FleetPaths.support.appendingPathComponent("service-labels.json")) {
        self.path = path
        do {
            let data = try Data(contentsOf: path)
            labels = try JSONDecoder().decode([String: ServiceLabel].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First use: do not create anything until a label is actually saved.
        } catch {
            loadError = "Could not read service labels: \(error.localizedDescription)"
        }
    }

    func label(for serviceID: String) -> ServiceLabel {
        labels[serviceID] ?? ServiceLabel()
    }

    func displayName(for record: ServiceRecord) -> String {
        label(for: record.id).displayName(fallback: record.friendlyName)
    }

    func matches(_ query: String, record: ServiceRecord) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields = [displayName(for: record), record.friendlyName, record.ownerAgent,
                      record.purpose, record.commandLine, label(for: record.id).color?.label ?? ""]
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
            || record.effectivePorts.contains { String($0).contains(query) }
            || (record.pid.map { String($0).contains(query) } ?? false)
    }

    func set(_ label: ServiceLabel, for serviceID: String) throws {
        if let loadError { throw ServiceLabelsError.unreadableFile(loadError) }
        var updated = labels
        updated[serviceID] = label.name == nil && label.color == nil ? nil : label
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        labels = updated
    }
}

/// The editor owns a draft. Dismissal never writes, and failed saves keep the draft open.
@MainActor
@Observable
final class ServiceLabelEditorModel {
    var name: String
    var color: ServiceTagColor?
    var errorMessage: String?
    let recordedName: String
    let shortID: String
    @ObservationIgnored private let serviceID: String
    @ObservationIgnored private let labels: ServiceLabelsStore

    init(service: ServiceRecord, labels: ServiceLabelsStore) {
        self.serviceID = service.id
        self.recordedName = service.friendlyName
        self.shortID = service.shortID
        self.labels = labels
        let label = labels.label(for: service.id)
        name = label.name ?? ""
        color = label.color
        errorMessage = labels.loadError
    }

    var hasChanges: Bool {
        ServiceLabel(name: name, color: color) != labels.label(for: serviceID)
    }

    func save() -> Bool {
        do {
            try labels.set(ServiceLabel(name: name, color: color), for: serviceID)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct ServiceLabelEditButton: View {
    let service: ServiceRecord
    var labels: ServiceLabelsStore = .shared
    var compact = false
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            if compact {
                Image(systemName: "pencil")
                    .frame(width: FleetMetrics.iconButtonSize, height: FleetMetrics.iconButtonSize)
            } else {
                Label("Name & tag…", systemImage: "pencil")
            }
        }
        .buttonStyle(.borderless)
        .help("Edit name and color tag")
        .accessibilityLabel("Edit name and tag for \(labels.displayName(for: service))")
        .accessibilityIdentifier("service.labels.edit.\(service.id)")
        .popover(isPresented: $editing) {
            ServiceLabelEditor(service: service, labels: labels)
        }
    }
}

struct ServiceLabelEditor: View {
    @State private var editor: ServiceLabelEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    init(service: ServiceRecord, labels: ServiceLabelsStore = .shared) {
        _editor = State(initialValue: ServiceLabelEditorModel(service: service, labels: labels))
    }

    var body: some View {
        @Bindable var editor = editor
        VStack(alignment: .leading, spacing: ConsoleMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name & tag")
                    .font(ConsoleFont.cardTitle)
                Text("\(editor.recordedName) · \(editor.shortID)")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Friendly name")
                    .font(ConsoleFont.subtitle)
                TextField(editor.recordedName, text: $editor.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Friendly name")
                    .accessibilityIdentifier("service.labels.name")
                    .focused($nameFocused)
                    .onSubmit { save() }
            }

            Picker("Color tag", selection: $editor.color) {
                Text("None").tag(Optional<ServiceTagColor>.none)
                ForEach(ServiceTagColor.allCases) { color in
                    Label {
                        Text(color.label)
                    } icon: {
                        Image(systemName: "tag.fill").foregroundStyle(color.swatch)
                    }
                    .tag(Optional(color))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Color tag")
            .accessibilityIdentifier("service.labels.color")

            Text("Labels stay on this Mac. Status, evidence and the controller's name are unchanged.")
                .font(ConsoleFont.caption)
                .foregroundStyle(SurfaceInk.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = editor.errorMessage {
                Text(error)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(StatusTone.bad.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Could not save label. \(error)")
            }

            HStack {
                Button("Reset") {
                    editor.name = ""
                    editor.color = nil
                }
                .help("Restore the recorded name and remove the tag when you save")
                .disabled(editor.name.isEmpty && editor.color == nil)
                .accessibilityIdentifier("service.labels.reset")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("service.labels.cancel")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!editor.hasChanges)
                    .accessibilityIdentifier("service.labels.save")
            }
        }
        .padding(ConsoleMetrics.gutter)
        .frame(width: FleetMetrics.popoverWidth - FleetMetrics.gutter * 2)
        .onAppear { nameFocused = true }
    }

    private func save() {
        guard editor.hasChanges else { return }
        if editor.save() { dismiss() }
    }
}

/// Tags use their own glyph and neutral text. They never recolor a service's status icon.
struct ServiceColorTag: View {
    let color: ServiceTagColor
    var compact = false

    var accessibilityText: String { "\(color.label) tag" }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .foregroundStyle(color.swatch)
            if !compact {
                Text(color.label)
                    .foregroundStyle(.primary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(SurfaceInk.surfaceWash,
                    in: RoundedRectangle(cornerRadius: FleetMetrics.tagCorner))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help("\(accessibilityText) — personal label, not health")
    }
}

extension ServiceTagColor {
    var swatch: Color {
        let color: NSColor
        switch self {
        case .blue: color = .systemBlue
        case .purple: color = .systemPurple
        case .teal: color = .systemTeal
        case .orange: color = .systemOrange
        case .pink: color = .systemPink
        case .gray: color = .systemGray
        }
        return Color(nsColor: color)
    }
}

private enum ServiceLabelsError: LocalizedError {
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let message):
            return message + " Repair the file and reopen FleetConsole before saving."
        }
    }
}
