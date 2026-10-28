import Foundation

// Daily agent spend.
//
// What an agent cost you today, where the figure came from, and — the part that
// matters most — the difference between "nothing" and "nobody knows". Ported
// from Masterwork Bar's `src/spend.rs`, which is the only capability that app
// had and this one did not. See the vault's Apple Menu merge recommendation.
//
// Everything in this file is pure: no filesystem, no clock, no database. The
// day being priced arrives as a `DateInterval` and the transcript arrives as a
// `String`, so the whole pricing path is fixture-testable and none of it can
// drift with the machine's timezone at test time. `AgentCostScanner` owns the
// IO and nothing else does.

// MARK: - Where a number came from

/// Provenance for one agent's figure, so an unknown can say *why* it is unknown
/// rather than presenting itself as zero spend.
///
/// The four cases are four genuinely different situations, and collapsing any
/// two of them loses something the operator needs: a tool that publishes no
/// usage record is a permanent gap you cannot close, while a directory that
/// would not open is a fault you can go and fix.
public enum AgentCostSource: Codable, Sendable, Hashable {
    /// Session transcripts this app priced itself, from published list prices.
    case sessionLogs(path: String, files: Int)
    /// A cost the tool had already computed, read back out of its own store.
    /// Nothing here is priced — the number is the tool's, and is authoritative.
    case toolDatabase(path: String, rows: Int)
    /// The tool records no usage this app can price. Not a fault, and not
    /// fixable: there is nothing on disk to read.
    case unpublished(tool: String)
    /// The tool is not on this machine. Distinct from `unpublished` because it
    /// is not permanent — installing the tool closes it — and distinct from
    /// `unreadable` because nothing is broken.
    case notInstalled(tool: String)
    /// A record that should have been readable and was not.
    case unreadable(path: String, reason: String)

    /// One short line for the row, in the operator's terms rather than ours.
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

    /// Whether the gap is worth a warning tone. An unpublished record is a
    /// permanent, blameless absence; an unreadable one is a fault.
    public var isFault: Bool {
        if case .unreadable = self { return true }
        return false
    }
}

// MARK: - The contract

/// What one agent cost today.
///
/// `amountUSD` is optional and that is the whole point of the type. Masterwork
/// Bar carried the same distinction as a parallel `bool`, which is a shape that
/// lets a caller read the number without reading the flag; here the compiler
/// makes you handle the gap. **An unknown is never rendered as `$0.00`** — a
/// zero is a claim that the agent ran for free, and for `gemini` and `aider` we
/// have no grounds for that claim at all.
public struct AgentCostSnapshot: Codable, Sendable, Hashable, Identifiable {
    /// Joins to `AgentProfile.id`, so the Agents section can render cost on the
    /// row it already draws rather than opening a second list of agents.
    public var id: String
    /// `nil` means unknown. See the type's note.
    public var amountUSD: Double?
    /// The most recent priced activity, which answers "is this figure stale?"
    /// without a second query.
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

/// Every agent's figure plus the rollup, which has to be honest about its own
/// coverage: a total that silently omits two unpriceable agents reads as the
/// whole day's spend and is not.
public struct AgentCostTotals: Codable, Sendable, Hashable {
    public var snapshots: [AgentCostSnapshot]
    public var sampledAt: Date

    public init(snapshots: [AgentCostSnapshot], sampledAt: Date) {
        self.snapshots = snapshots
        self.sampledAt = sampledAt
    }

    /// The sum of what could be priced. Unknowns are excluded rather than
    /// added as zero, and `unknownCount` is what stops that being a lie.
    public var knownTotalUSD: Double {
        snapshots.compactMap(\.amountUSD).reduce(0, +)
    }

    /// How many agents could not be priced at all.
    public var unknownCount: Int {
        snapshots.filter { !$0.isKnown }.count
    }

    /// Agents that are unknown because something broke, as opposed to agents
    /// that were never priceable. Only this kind is worth surfacing as a fault.
    public var faults: [AgentCostSnapshot] {
        snapshots.filter { !$0.isKnown && $0.source.isFault }
    }

    public func snapshot(for agentID: String) -> AgentCostSnapshot? {
        snapshots.first { $0.id == agentID }
    }
}

// MARK: - Prices

/// Published list price per million tokens, in USD.
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

/// Token counts for one priced turn, already normalised so that `input` never
/// double-counts what `cacheRead` covers.
///
/// The normalisation is load-bearing, because the two providers disagree about
/// it: Claude reports cache reads in their own field alongside a separate
/// `input_tokens`, while Codex reports a single `input_tokens` that *includes*
/// `cached_input_tokens`. Subtracting at the parse boundary means one cost
/// function serves both and neither provider's convention leaks past it.
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

/// The rate tables, written down rather than fetched.
///
/// A menu-bar app that phoned a pricing endpoint to draw a row would be trading
/// its "no network listener, no telemetry" posture for two decimal places. The
/// cost of writing them down is that they go stale — which is visible the first
/// time the figure disagrees with a provider's own bill, and is the reason
/// `AgentCostSource` records that *we* did the pricing.
public enum AgentPricing {
    public static let claudeOpus = TokenRate(input: 15.0, output: 75.0,
                                             cacheRead: 1.5, cacheWrite: 18.75)
    public static let claudeSonnet = TokenRate(input: 3.0, output: 15.0,
                                               cacheRead: 0.30, cacheWrite: 3.75)
    public static let claudeHaiku = TokenRate(input: 0.80, output: 4.0,
                                              cacheRead: 0.08, cacheWrite: 1.0)
    /// Codex bills a cached input token at a tenth of a fresh one and writes
    /// nothing, so `cacheWrite` is genuinely zero rather than unknown.
    public static let codexGPT5 = TokenRate(input: 1.25, output: 10.0,
                                            cacheRead: 0.125, cacheWrite: 0)

    /// Sonnet is the fallback for an unrecognised model, deliberately. A future
    /// Claude model priced as Sonnet is wrong by a factor of five at worst; one
    /// priced at zero is wrong by the whole amount and looks like a free day.
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

// MARK: - Parsing

/// One priced turn out of a transcript.
public struct AgentCostSample: Sendable, Hashable {
    public var costUSD: Double
    public var at: Date

    public init(costUSD: Double, at: Date) {
        self.costUSD = costUSD
        self.at = at
    }
}

/// Transcript line → priced turn. Pure, and the only place a provider's on-disk
/// shape is known.
public enum AgentCostParser {

    /// A cheap substring test before `JSONSerialization` touches the line.
    ///
    /// This is not premature: a working day of Claude transcripts is hundreds of
    /// megabytes across thousands of lines, the overwhelming majority of which
    /// carry no usage at all, and parsing each one to discover that is the
    /// difference between a menu-bar refresh and a visible stall.
    static func mightCarryUsage(_ line: String, marker: String) -> Bool {
        line.contains(marker) && line.contains("\"timestamp\"")
    }

    /// One line of a Claude Code transcript.
    ///
    /// Returns `nil` for a line with no usage, a line stamped outside `day`, and
    /// a **synthetic** model — those turns are replayed locally and were never
    /// billed, so pricing them would invent spend that no invoice will show.
    public static func claudeLine(_ line: String, in day: DateInterval) -> AgentCostSample? {
        guard mightCarryUsage(line, marker: "\"usage\""),
              let object = json(line),
              let at = timestamp(object["timestamp"], in: day)
        else { return nil }

        // Two transcript generations: the usage and model either sit under
        // `message` or at the top level. Both are still on disk on this machine.
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

    /// One line of a Codex session log.
    ///
    /// `input_tokens` here is inclusive of `cached_input_tokens`, so the cached
    /// share is subtracted before pricing — see `TokenUsage`. The subtraction is
    /// floored at zero: a malformed line reporting more cached than total input
    /// would otherwise produce a negative cost and quietly reduce the day's bill.
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

    /// One `message.data` blob out of opencode's own database. Nothing is priced
    /// here: opencode records the cost it was charged, so that figure is better
    /// than any table we could keep. A row with no creation time dates to
    /// `distantPast`, which loses to every real timestamp in the `max` the
    /// scanner runs — the same outcome as skipping it, without a second shape.
    public static func opencodeRow(_ data: String) -> AgentCostSample? {
        guard let object = json(data), let cost = object["cost"] as? Double else { return nil }
        let time = object["time"] as? [String: Any]
        let created = (time?["created"] as? Double).map { $0 / 1000 }
        return AgentCostSample(costUSD: cost,
                               at: created.map(Date.init(timeIntervalSince1970:)) ?? .distantPast)
    }

    // MARK: Primitives

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// Two formatters, built once.
    ///
    /// A day of transcripts reaches this path a few thousand times and each
    /// `ISO8601DateFormatter()` builds an internal `CFDateFormatter`, so
    /// allocating per line is pure waste. `nonisolated(unsafe)` is the honest
    /// declaration: the instances are configured at init and never mutated
    /// again, and `date(from:)` on an unmutated formatter is a read.
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

    /// RFC 3339 with or without fractional seconds, and only if it lands inside
    /// `day`. Both spellings appear in the same directory.
    ///
    /// Half-open on purpose: `DateInterval.contains` includes its end, which
    /// would price a turn stamped exactly at midnight into both days.
    private static func timestamp(_ value: Any?, in day: DateInterval) -> Date? {
        guard let text = value as? String,
              let date = fractional.date(from: text) ?? whole.date(from: text),
              date >= day.start, date < day.end
        else { return nil }
        return date
    }

    /// A token count that may arrive as either JSON number type, or be absent.
    private static func number(_ value: Any?) -> Double {
        (value as? Double) ?? (value as? NSNumber)?.doubleValue ?? 0
    }
}
