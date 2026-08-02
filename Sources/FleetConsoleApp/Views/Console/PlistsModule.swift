import SwiftUI
import Foundation

// Module: Launch Services — launchd agents, daemons, and their plists.
//
// Three scopes, each from a well-known directory that launchd reads at login
// or boot:
//
//   ~/Library/LaunchAgents        — current user, user-session scope
//   /Library/LaunchAgents         — all users, user-session scope
//   /Library/LaunchDaemons        — system scope (root) — loaded at boot
//
// This module is read-only throughout. It never loads, unloads, or modifies
// a plist — visibility with no escalation. The design principle is the same
// one the services module follows: a process launched by someone else gets
// "Reveal in Finder" and nothing else. The same applies to launchd jobs.
//
// What it surfaces:
//   - Label, run-at-load flag, program (or program arguments), keepalive
//     flag, and whether the job appears loaded per `launchctl list`.
//   - The raw plist keys, all of them, shown in the inspector so nothing is
//     hidden by a field mapping that hasn't been written yet.
//   - The state from launchctl: loaded / not loaded / error reading.

// MARK: - Model

/// A single plist key/value pair, used in the inspector.
struct PlistKeyValue: Identifiable, Hashable, Equatable, Sendable {
    var id: String { key }
    var key: String
    var value: String
}

struct LaunchEntry: Identifiable, Hashable, Equatable, Sendable {
    enum Scope: String, Hashable, Sendable {
        case userAgent = "~/Library/LaunchAgents"
        case globalAgent = "/Library/LaunchAgents"
        case systemDaemon = "/Library/LaunchDaemons"

        var directory: String {
            switch self {
            case .userAgent: return (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/LaunchAgents")
            case .globalAgent: return "/Library/LaunchAgents"
            case .systemDaemon: return "/Library/LaunchDaemons"
            }
        }

        var title: String {
            switch self {
            case .userAgent: return "User Agents"
            case .globalAgent: return "Global Agents"
            case .systemDaemon: return "System Daemons"
            }
        }

        var symbol: String {
            switch self {
            case .userAgent: return "person.circle"
            case .globalAgent: return "person.2.circle"
            case .systemDaemon: return "gearshape.fill"
            }
        }
    }

    enum LoadState: Hashable, Sendable {
        case loaded(pid: Int?)
        case notLoaded
        case unknown
        case error(String)

        var label: String {
            switch self {
            case .loaded(let pid):
                if let pid { return "loaded · pid \(pid)" }
                return "loaded"
            case .notLoaded: return "not loaded"
            case .unknown: return "unknown"
            case .error(let msg): return "error: \(msg)"
            }
        }

        var tone: StatusTone {
            switch self {
            case .loaded: return .good
            case .notLoaded: return .neutral
            case .unknown: return .neutral
            case .error: return .bad
            }
        }
    }

    var id: String { plistPath }
    var label: String
    var plistPath: String
    var scope: Scope
    var runAtLoad: Bool
    var keepAlive: Bool
    var disabled: Bool
    var program: String?
    var programArguments: [String]
    var workingDirectory: String?
    var standardOutPath: String?
    var standardErrorPath: String?
    var allKeys: [PlistKeyValue]     // All plist keys, sorted, values as strings
    var loadState: LoadState = .unknown

    var commandLabel: String {
        if let program { return program }
        return programArguments.first ?? label
    }
}

// MARK: - Scanner

@MainActor
@Observable
final class PlistScanner {
    var entries: [LaunchEntry] = []
    var scanError: String?
    var isScanning = false
    private(set) var scannedAt: Date?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil
        Task {
            var loaded: [LaunchEntry] = []
            for scope in LaunchEntry.Scope.allCases {
                let found = readPlists(scope: scope)
                loaded.append(contentsOf: found)
            }
            // Enrich with launchctl state.
            loaded = await withLoadStates(loaded)
            entries = loaded.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            isScanning = false
            scannedAt = Date()
        }
    }

    private func readPlists(scope: LaunchEntry.Scope) -> [LaunchEntry] {
        let dir = scope.directory
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return contents
            .filter { $0.hasSuffix(".plist") }
            .compactMap { filename -> LaunchEntry? in
                let path = (dir as NSString).appendingPathComponent(filename)
                return parseEntry(path: path, scope: scope)
            }
    }

    private func parseEntry(path: String, scope: LaunchEntry.Scope) -> LaunchEntry? {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let label = dict["Label"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        let keepAlive: Bool
        if let ka = dict["KeepAlive"] {
            if let b = ka as? Bool { keepAlive = b }
            else if let d = ka as? [String: Any] { keepAlive = !d.isEmpty }
            else { keepAlive = false }
        } else {
            keepAlive = false
        }
        let disabled = dict["Disabled"] as? Bool ?? false
        let program = dict["Program"] as? String
        let programArguments = dict["ProgramArguments"] as? [String] ?? []
        let cwd = dict["WorkingDirectory"] as? String
        let stdout = dict["StandardOutPath"] as? String
        let stderr = dict["StandardErrorPath"] as? String

        // Flatten all keys to string pairs for the inspector.
        let allKeys = dict.sorted { $0.key < $1.key }.map { (key, value) -> PlistKeyValue in
            PlistKeyValue(key: key, value: flattenValue(value))
        }

        return LaunchEntry(
            label: label,
            plistPath: path,
            scope: scope,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            disabled: disabled,
            program: program,
            programArguments: programArguments,
            workingDirectory: cwd,
            standardOutPath: stdout,
            standardErrorPath: stderr,
            allKeys: allKeys
        )
    }

    private func flattenValue(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let a as [Any]: return "[" + a.prefix(8).map { flattenValue($0) }.joined(separator: ", ") + "]"
        case let d as [String: Any]:
            let pairs = d.sorted { $0.key < $1.key }.prefix(6).map { "\($0.key): \(flattenValue($0.value))" }
            return "{" + pairs.joined(separator: ", ") + "}"
        default: return "\(value)"
        }
    }

    private func withLoadStates(_ entries: [LaunchEntry]) async -> [LaunchEntry] {
        // `launchctl list` returns every loaded job with its PID and status.
        // The output format: PID | Status | Label, tab-separated, where `-`
        // means no PID (not running but loaded).
        let listResult = await runLaunchctl(["list"])
        guard listResult.exit == 0 else { return entries }

        // Parse into a dictionary: label → (pid, status)
        var loaded: [String: Int?] = [:]
        for line in listResult.stdout.split(separator: "\n").dropFirst() {  // skip header
            let fields = line.split(separator: "\t", maxSplits: 2)
            guard fields.count == 3 else { continue }
            let pidStr = String(fields[0])
            let label = String(fields[2]).trimmingCharacters(in: .whitespaces)
            loaded[label] = pidStr == "-" ? .some(.none) : Int(pidStr).map { .some($0) } ?? .some(.none)
        }

        return entries.map { entry in
            var updated = entry
            if let pid = loaded[entry.label] {
                updated.loadState = .loaded(pid: pid)
            } else {
                updated.loadState = .notLoaded
            }
            return updated
        }
    }

    private struct CommandResult {
        var stdout: String
        var stderr: String
        var exit: Int32
    }

    private func runLaunchctl(_ args: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = args
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: CommandResult(stdout: "", stderr: error.localizedDescription, exit: -1))
                    return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CommandResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exit: process.terminationStatus))
            }
        }
    }
}

extension LaunchEntry.Scope: CaseIterable {}

// MARK: - Module view

struct PlistsModule: View {
    @Bindable var console: ConsoleModel

    @State private var scanner = PlistScanner()
    @State private var selectedEntry: LaunchEntry?

    private var query: String { console.search.trimmingCharacters(in: .whitespaces) }

    private func entries(for scope: LaunchEntry.Scope) -> [LaunchEntry] {
        let all = scanner.entries.filter { $0.scope == scope }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || ($0.program?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.programArguments.joined(separator: " ").localizedCaseInsensitiveContains(query)
                || $0.plistPath.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(selection: $selectedEntry) {
            ForEach(LaunchEntry.Scope.allCases, id: \.self) { scope in
                let rows = entries(for: scope)
                Section {
                    if rows.isEmpty {
                        Text(query.isEmpty ? "No plists in \(scope.directory)" : "No match in \(scope.rawValue)")
                            .font(ConsoleFont.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(rows) { entry in
                            LaunchEntryRow(entry: entry)
                                .tag(entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.selectFile(entry.plistPath, inFileViewerRootedAtPath: "")
                                    }
                                    Button("Copy Label") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.label, forType: .string)
                                    }
                                    Button("Copy Plist Path") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.plistPath, forType: .string)
                                    }
                                }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: scope.symbol)
                            .font(ConsoleFont.caption.weight(.semibold))
                        Text(scope.title)
                            .font(ConsoleFont.subtitle.weight(.semibold))
                        Spacer()
                        ConsoleBadge(text: "\(rows.count)")
                    }
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top) {
            ModuleHeader(
                title: "Launch Services",
                subtitle: headerSubtitle,
                symbol: ConsoleModule.plists.symbol
            ) {
                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: { scanner.scan() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                            .font(ConsoleFont.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, ConsoleMetrics.gutter)
            .padding(.vertical, 10)
            .background(.bar)
            .hairline()
        }
        .onAppear {
            if scanner.entries.isEmpty && !scanner.isScanning {
                scanner.scan()
            }
        }
    }

    private var headerSubtitle: String {
        if scanner.isScanning { return "reading launch directories…" }
        let total = scanner.entries.count
        let loaded = scanner.entries.filter {
            if case .loaded = $0.loadState { return true }
            return false
        }.count
        if let at = scanner.scannedAt {
            return "\(total) entries · \(loaded) loaded · \(ConsoleFmt.timestamp(at))"
        }
        return "\(total) entries · \(loaded) loaded"
    }
}

// MARK: - Row

private struct LaunchEntryRow: View {
    let entry: LaunchEntry

    var body: some View {
        HStack(spacing: 10) {
            EntityIcon(symbol: entrySymbol, tone: entry.loadState.tone, size: FleetMetrics.iconRowLarge)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(ConsoleFont.rowTitle.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.disabled {
                        ConsoleBadge(text: "disabled", tone: .neutral)
                    }
                }
                Text(entry.commandLabel)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.loadState.label)
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(entry.loadState.tone.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if entry.runAtLoad {
                        Text("run-at-load")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if entry.keepAlive {
                        Text("keepalive")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.label), \(entry.loadState.label)")
    }

    private var entrySymbol: String {
        switch entry.scope {
        case .userAgent: return "person.circle"
        case .globalAgent: return "person.2.circle"
        case .systemDaemon: return "gearshape.fill"
        }
    }
}
