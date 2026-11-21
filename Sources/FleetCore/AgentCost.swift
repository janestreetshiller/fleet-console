import Foundation

public enum AgentCostSource: Codable, Sendable, Hashable {
    case sessionLogs(path: String, files: Int)
    case toolDatabase(path: String, rows: Int)
    case unpublished(tool: String)
    case notInstalled(tool: String)
    case unreadable(path: String, reason: String)

    public var explanation: String {
        switch self {
        case .sessionLogs(_, let files):
            return files == 1 ? "1 session today" : "\(files) sessions today"
        case .toolDatabase(_, let rows):
            return rows == 1 ? "1 message today" : "\(rows) messages today"
        case .unpublished(let tool):
            return "\(tool) publishes no usage record"
        case .notInstalled(let tool):
            return "\(tool) is not installed"
        case .unreadable(_, let reason):
            return "Could not read: \(reason)"
        }
    }

    public var isFault: Bool {
        if case .unreadable = self { return true }
        return false
    }
}

public struct AgentCostSnapshot: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var amountUSD: Double?
    public var lastActivityAt: Date?
    public var source: AgentCostSource
    public var sampledAt: Date

    public init(id: String, amountUSD: Double?, lastActivityAt: Date? = nil,
                source: AgentCostSource, sampledAt: Date) {
        self.id = id
        self.amountUSD = amountUSD
        self.lastActivityAt = lastActivityAt
        self.source = source
        self.sampledAt = sampledAt
    }

    public var isKnown: Bool { amountUSD != nil }
}

public struct AgentCostTotals: Codable, Sendable, Hashable {
    public var snapshots: [AgentCostSnapshot]
    public var sampledAt: Date

    public init(snapshots: [AgentCostSnapshot], sampledAt: Date) {
        self.snapshots = snapshots
        self.sampledAt = sampledAt
    }

    public var knownTotalUSD: Double {
        snapshots.compactMap(\.amountUSD).reduce(0, +)
    }

    public var unknownCount: Int {
        snapshots.filter { !$0.isKnown }.count
    }

    public var faults: [AgentCostSnapshot] {
        snapshots.filter { !$0.isKnown && $0.source.isFault }
    }

    public func snapshot(for agentID: String) -> AgentCostSnapshot? {
        snapshots.first { $0.id == agentID }
    }
}

public struct TokenRate: Sendable, Hashable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double = 0, cacheWrite: Double = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

public struct TokenUsage: Sendable, Hashable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double

    public init(input: Double = 0, output: Double = 0,
                cacheRead: Double = 0, cacheWrite: Double = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

public enum AgentPricing {
    public static let claudeOpus = TokenRate(input: 15.0, output: 75.0,
                                             cacheRead: 1.5, cacheWrite: 18.75)
    public static let claudeSonnet = TokenRate(input: 3.0, output: 15.0,
                                               cacheRead: 0.30, cacheWrite: 3.75)
    public static let claudeHaiku = TokenRate(input: 0.80, output: 4.0,
                                              cacheRead: 0.08, cacheWrite: 1.0)
    public static let codexGPT5 = TokenRate(input: 1.25, output: 10.0,
                                            cacheRead: 0.125, cacheWrite: 0)

    public static func claude(model: String) -> TokenRate {
        let m = model.lowercased()
        if m.contains("opus") { return claudeOpus }
        if m.contains("haiku") { return claudeHaiku }
        return claudeSonnet
    }

    public static func cost(of usage: TokenUsage, at rate: TokenRate) -> Double {
        (usage.input * rate.input
            + usage.output * rate.output
            + usage.cacheRead * rate.cacheRead
            + usage.cacheWrite * rate.cacheWrite) / 1_000_000
    }
}

public struct AgentCostSample: Sendable, Hashable {
    public var costUSD: Double
    public var at: Date

    public init(costUSD: Double, at: Date) {
        self.costUSD = costUSD
        self.at = at
    }
}

public enum AgentCostParser {

    static func mightCarryUsage(_ line: String, marker: String) -> Bool {
        line.contains(marker) && line.contains("\"timestamp\"")
    }

    public static func claudeLine(_ line: String, in day: DateInterval) -> AgentCostSample? {
        guard mightCarryUsage(line, marker: "\"usage\""),
              let object = json(line),
              let at = timestamp(object["timestamp"], in: day)
        else { return nil }

        let message = object["message"] as? [String: Any]
        guard let usage = (message?["usage"] as? [String: Any])
                ?? (object["usage"] as? [String: Any])
        else { return nil }

        let model = (message?["model"] as? String) ?? (object["model"] as? String) ?? ""
        guard !model.contains("synthetic") else { return nil }

        let counts = TokenUsage(
            input: number(usage["input_tokens"]),
            output: number(usage["output_tokens"]),
            cacheRead: number(usage["cache_read_input_tokens"]),
            cacheWrite: number(usage["cache_creation_input_tokens"]))
        return AgentCostSample(costUSD: AgentPricing.cost(of: counts,
                                                          at: AgentPricing.claude(model: model)),
                               at: at)
    }

    public static func codexLine(_ line: String, in day: DateInterval) -> AgentCostSample? {
        guard mightCarryUsage(line, marker: "\"token_count\""),
              let object = json(line),
              let at = timestamp(object["timestamp"], in: day)
        else { return nil }

        let payload = object["payload"] as? [String: Any]
        let info = payload?["info"] as? [String: Any]
        guard let usage = info?["last_token_usage"] as? [String: Any] else { return nil }

        let total = number(usage["input_tokens"])
        let cached = number(usage["cached_input_tokens"])
        let counts = TokenUsage(
            input: max(0, total - cached),
            output: number(usage["output_tokens"]),
            cacheRead: cached)
        return AgentCostSample(costUSD: AgentPricing.cost(of: counts, at: AgentPricing.codexGPT5),
                               at: at)
    }

    public static func opencodeRow(_ data: String) -> AgentCostSample? {
        guard let object = json(data), let cost = object["cost"] as? Double else { return nil }
        let time = object["time"] as? [String: Any]
        let created = (time?["created"] as? Double).map { $0 / 1000 }
        return AgentCostSample(costUSD: cost,
                               at: created.map(Date.init(timeIntervalSince1970:)) ?? .distantPast)
    }

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func timestamp(_ value: Any?, in day: DateInterval) -> Date? {
        guard let text = value as? String,
              let date = fractional.date(from: text) ?? whole.date(from: text),
              date >= day.start, date < day.end
        else { return nil }
        return date
    }

    private static func number(_ value: Any?) -> Double {
        (value as? Double) ?? (value as? NSNumber)?.doubleValue ?? 0
    }
}
