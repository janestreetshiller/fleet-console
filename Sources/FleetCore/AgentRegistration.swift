import Foundation

public enum AgentRegistrationError: LocalizedError, Equatable, Sendable {
    case invalidID
    case duplicateID(String)
    case missingID(String)
    case damagedRoster

    public var errorDescription: String? {
        switch self {
        case .invalidID:
            return "Use 1–128 letters, numbers, dots, hyphens or underscores; start with a letter or number. IDs are case-sensitive."
        case .duplicateID(let id):
            return "“\(id)” is already registered."
        case .missingID(let id):
            return "“\(id)” is no longer registered."
        case .damagedRoster:
            return "The saved agent roster is invalid. It has not been changed."
        }
    }
}

/// A client-local address book of agent ownership IDs, not a session registry.
/// Adding an ID neither launches a process nor changes the controller's records.
public struct AgentRegistrationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = FleetPaths.support.appendingPathComponent("registered-agents.json")) {
        self.fileURL = fileURL
    }

    public func load() throws -> [String] {
        do {
            let data = try Data(contentsOf: fileURL)
            let ids: [String]
            do {
                ids = try JSONDecoder().decode([String].self, from: data)
                for id in ids { try Self.validate(id) }
                guard Set(ids).count == ids.count else { throw AgentRegistrationError.damagedRoster }
            } catch {
                throw AgentRegistrationError.damagedRoster
            }
            return ids
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    @discardableResult
    public func register(_ id: String) throws -> [String] {
        try Self.validate(id)
        var ids = try load()
        guard !ids.contains(id) else { throw AgentRegistrationError.duplicateID(id) }
        ids.append(id)
        try save(ids)
        return ids
    }

    @discardableResult
    public func remove(_ id: String) throws -> [String] {
        var ids = try load()
        guard let index = ids.firstIndex(of: id) else { throw AgentRegistrationError.missingID(id) }
        ids.remove(at: index)
        try save(ids)
        return ids
    }

    private static func validate(_ id: String) throws {
        let bytes = Array(id.utf8)
        let alphanumeric: (UInt8) -> Bool = {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
        }
        guard (1...128).contains(bytes.count), let first = bytes.first, alphanumeric(first),
              bytes.allSatisfy({ alphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }) else {
            throw AgentRegistrationError.invalidID
        }
    }

    private func save(_ ids: [String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(ids).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

/// Registered IDs and controller-observed ownership stay distinct. A registered
/// ID without a matching profile has no invented service, session or activity.
public struct AgentRosterEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let isRegistered: Bool
    public let profile: AgentProfile?

    public static func merge(registeredIDs: [String], profiles: [AgentProfile]) -> [AgentRosterEntry] {
        var observed: [String: AgentProfile] = [:]
        for profile in profiles { observed[profile.id] = profile }
        var seen = Set<String>()
        let registered = registeredIDs.filter { seen.insert($0).inserted }.map {
            AgentRosterEntry(id: $0, isRegistered: true, profile: observed[$0])
        }
        let others = observed.keys.filter { !seen.contains($0) }.sorted().map {
            AgentRosterEntry(id: $0, isRegistered: false, profile: observed[$0])
        }
        return registered + others
    }
}

public enum AgentGlanceEntry: Identifiable, Hashable, Sendable {
    case owner(AgentRosterEntry)
    case session(AgentSession)

    public var id: String {
        switch self {
        case .owner(let entry): return "owner:\(entry.id)"
        case .session(let session): return "session:\(session.id)"
        }
    }
}

/// A bounded menu glance, not a shortened source of truth. The full entries and
/// explicit overflow count feed a separate manager; detected sessions lead.
public struct AgentGlanceRoster: Sendable {
    public static let maximumRows = 5
    public let entries: [AgentGlanceEntry]
    public let ownerCount: Int
    public let detectedCount: Int
    public var totalCount: Int { entries.count }
    public var visibleEntries: [AgentGlanceEntry] { Array(entries.prefix(Self.maximumRows)) }
    public var overflowCount: Int { max(0, totalCount - Self.maximumRows) }

    public init(registeredIDs: [String], profiles: [AgentProfile], sessions: [AgentSession]) {
        let owners = AgentRosterEntry.merge(registeredIDs: registeredIDs, profiles: profiles)
        var seen = Set<String>()
        let detected = sessions.filter { seen.insert($0.id).inserted }
        ownerCount = owners.count
        detectedCount = detected.count
        entries = detected.map(AgentGlanceEntry.session) + owners.map(AgentGlanceEntry.owner)
    }
}
