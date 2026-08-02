import Foundation
import FleetCore

// What is actually installed, and which presets that entitles the panel to offer.
//
// The rule here is the same one the evidence chips follow: a preset is offered
// only when the model behind it was seen on disk. `orcs models` is the authority,
// asked at panel-open time — not a constant in this file, and not an assumption
// that the machine still looks like it did when this was written.

// MARK: - The binary

enum Orcs {
    /// Where the operator keeps it. Tried before `PATH` on purpose: an app
    /// launched from Finder inherits launchd's minimal `PATH`, which does not
    /// include `~/.local/bin`, so PATH-only discovery would report "not
    /// installed" on a machine where it plainly is.
    static var expectedPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/orcs")
    }

    /// Qwen3's switch for suppressing its reasoning pass.
    ///
    /// Needed rather than merely tidy. Thinking is on by default, and this build
    /// emits the reasoning as plain prose — no `<think>` wrapper to strip — so
    /// there is no reliable way to separate it from the answer after the fact.
    /// Displayed, it puts the model's own false starts ("Wait, but the lease
    /// is…") on screen with the same weight as its conclusion, in a panel whose
    /// entire premise is that what it shows is evidence. Heuristically guessing
    /// where the thinking ends would be the same mistake one layer up.
    static let thinkingOff = "\n/no_think"

    static func locate() -> String? {
        Shell.which("orcs", candidates: [expectedPath])
    }

    /// `orcs models` is a directory listing, not an inference call.
    static let inventoryTimeout: TimeInterval = 10

    /// A cold start loads a 2.32 GB GGUF before the first token — measured at
    /// ~12 s for a one-word answer — and a real diagnosis prompt adds generation
    /// on top. Generous enough that a slow answer is not mistaken for a hang,
    /// bounded so a wedged child cannot become a permanent one.
    static let requestTimeout: TimeInterval = 180
}

// MARK: - Inventory

/// One GGUF as `orcs models` reports it.
struct OrcsModel: Identifiable, Hashable, Sendable {
    var name: String
    var size: String?
    var path: String?

    var id: String { name }

    var summary: String {
        size.map { "\(name) · \($0)" } ?? name
    }
}

enum OrcsInventory {
    /// Lines look like `gemma-3-4b-it-Q4_K_M   2.32 GB   /Users/…/model.gguf`:
    /// name, size, absolute path, whitespace-aligned. Parsed defensively —
    /// a column that moves should cost the size label, not the model.
    static func parse(_ text: String) -> [OrcsModel] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let path = fields.last.flatMap { $0.hasPrefix("/") ? $0 : nil }
            var size: String?
            for (index, field) in fields.enumerated() where index > 0 {
                if ["GB", "MB", "KB", "B"].contains(field), index > 1 {
                    size = "\(fields[index - 1]) \(field)"
                    break
                }
            }
            return OrcsModel(name: name, size: size, path: path)
        }
    }

    static func probe(executable: String) async -> Result<[OrcsModel], OrcsProbingError> {
        let run = await OrcsProcess.run(executable: executable,
                                        arguments: ["models"],
                                        timeout: Orcs.inventoryTimeout)
        guard run.succeeded else {
            let reason = OrcsDiagnostics.failureLine(run) ?? "`orcs models` failed"
            return .failure(OrcsProbingError(message: reason))
        }
        return .success(parse(run.stdout))
    }
}

/// A simple wrapper so `Result`'s error slot satisfies `Error` conformance.
struct OrcsProbingError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Presets

/// The model family a verb needs. `orcs --help` states it per verb, and the
/// wrapper is the one that knows how to satisfy it — this only has to decide
/// whether asking is honest.
struct OrcsModelRequirement: Hashable, Sendable {
    let label: String
    /// Every token must appear in a lowercased model name. Two loose tokens
    /// rather than an exact filename, because a re-quantised `gemma-3-4b` is
    /// still the model the verb wants.
    let tokens: [String]

    /// The evidence presets' model.
    ///
    /// Measured against `gemma-3-4b-it-Q4_K_M` on this panel's own prompts, with
    /// the failing-service case as the hard one: 0.60 GB against 2.32, and 1.7s
    /// against 13.6s, reaching the same conclusion — process alive, port not
    /// held, therefore the listener never bound. It describes where the 4B
    /// concludes, but it does not invent, which is the bar that matters on a
    /// surface whose whole claim is that nothing is asserted without evidence.
    ///
    /// Its reasoning has to be suppressed, not displayed: Qwen3 thinks by
    /// default and this build emits that reasoning as undelimited prose with no
    /// `<think>` tags to strip. Left on, the panel would show "Wait, but the
    /// lease is…" as though it were a finding. `Orcs.thinkingOff` is appended to
    /// every prompt for that reason, and the presets carry a method rather than
    /// a bare question to make up the depth that suppressing it costs.
    static let qwen3_06B = OrcsModelRequirement(label: "Qwen3 0.6B", tokens: ["qwen3", "0.6b"])
    static let gemma3_4B = OrcsModelRequirement(label: "Gemma 3 4B", tokens: ["gemma-3", "4b"])
    static let gemma4_12B = OrcsModelRequirement(label: "Gemma 4 12B", tokens: ["gemma-4", "12b"])

    func match(in models: [OrcsModel]) -> OrcsModel? {
        models.first { model in
            let name = model.name.lowercased()
            return tokens.allSatisfy(name.contains)
        }
    }
}

/// A button. Presets differ by the *question*, not only by the verb: two of them
/// run `orcs debug` because evidence-first diagnosis is the right model behaviour
/// for both "what is wrong" and "what would tell us", and pretending otherwise
/// would mean choosing a worse verb to justify a tidier table.
struct InterpreterPreset: Identifiable, Hashable, Sendable {
    /// What the assembled prompt leads with.
    enum Focus: Hashable, Sendable {
        /// The selected service, its evidence and its timeline.
        case evidence
        /// The working directory and whatever is running out of it.
        case project
    }

    let id: String
    let title: String
    let symbol: String
    let verb: String
    let focus: Focus
    let requirement: OrcsModelRequirement
    /// The task line handed to the model, verbatim.
    let instruction: String
    /// Tooltip. Says what the preset is for and what it will not do.
    let blurb: String

    /// Whether this preset names its own model instead of taking whichever one
    /// the `orcs` verb is bound to.
    ///
    /// The verbs are aliases with a model baked in — `orcs --help` says
    /// "orcs debug — Gemma 3 4B" — so calling one hands the choice to the
    /// wrapper. `orcs run -model …` puts it back here, which is the only way the
    /// evidence presets can be on a 0.6B while the escalations stay on the big
    /// model.
    var pinsModel: Bool { requirement == .qwen3_06B }

    var commandLabel: String {
        pinsModel ? "orcs run · \(requirement.label)" : "orcs \(verb)"
    }

    /// The argv for one run. `model` is the name `orcs models` reported, so the
    /// panel never invents a model that is not on disk.
    func arguments(model: String, prompt: String) -> [String] {
        guard pinsModel else { return [verb, "--prompt", prompt] }
        return ["run", "-model", model, "-profile", "fast",
                "-prompt", prompt + Orcs.thinkingOff]
    }

    static let all: [InterpreterPreset] = [
        InterpreterPreset(
            id: "diagnose",
            title: "Diagnose",
            symbol: "stethoscope",
            verb: "debug",
            focus: .evidence,
            requirement: .qwen3_06B,
            instruction: "Diagnose the state of the subject below using ONLY the evidence given.\n"
                + "Method — follow it exactly:\n"
                + "1. State the single most likely explanation in one sentence. It must account "
                + "for ALL FOUR facts together, not just the loudest one.\n"
                + "2. Then list which facts you relied on, quoting each.\n"
                + "3. If two facts appear to disagree, say which combination they imply.\n"
                + "4. Never call a service healthy unless the health check RAN and PASSED. "
                + "\"Reachable\" and \"process exists\" are not health.",
            blurb: "Evidence-first diagnosis of the current selection. "
                + "Reads the controller's facts; changes nothing."),
        InterpreterPreset(
            id: "next-check",
            title: "Next check",
            symbol: "arrow.triangle.branch",
            verb: "debug",
            focus: .evidence,
            requirement: .qwen3_06B,
            instruction: "More than one cause usually fits evidence this thin. Using ONLY the "
                + "evidence below:\n"
                + "1. List the competing explanations, each with the fact that supports it.\n"
                + "2. Name the single cheapest read-only check that would tell them apart.\n"
                + "3. Say which of the four facts that check would establish, and what each "
                + "outcome would rule out.\n"
                + "Do not propose a check that changes anything.",
            blurb: "What to check next, and which of the four facts it would settle."),
        InterpreterPreset(
            id: "decipher",
            title: "Decipher project",
            symbol: "curlybraces",
            verb: "code",
            focus: .project,
            requirement: .qwen3_06B,
            instruction: "Describe what the project below is and what its processes are doing, "
                + "using ONLY the evidence given.\n"
                + "1. Say what the project is, citing the files or processes that show it.\n"
                + "2. Say what each running process appears to be doing, and on what evidence.\n"
                + "3. Where the evidence cannot answer something, write \"not established by the "
                + "evidence\" and move on. Do not guess, and do not fill gaps from what projects "
                + "of this shape usually contain.",
            blurb: "Reads the working directory and the processes running out of it."),
        InterpreterPreset(
            id: "review",
            title: "Second opinion",
            symbol: "text.magnifyingglass",
            verb: "review",
            focus: .evidence,
            requirement: .gemma4_12B,
            instruction: "Review the diagnosis implied by the evidence below and say where it is "
                + "weakest.",
            blurb: "Deliberate escalation to the review model."),
        InterpreterPreset(
            id: "plan",
            title: "Plan a fix",
            symbol: "list.bullet.rectangle",
            verb: "plan",
            focus: .evidence,
            requirement: .gemma4_12B,
            instruction: "Draft an ordered plan to resolve the situation described below, with the "
                + "check that would confirm each step.",
            blurb: "Deliberate escalation to the planning model.")
    ]

    static var `default`: InterpreterPreset { all[0] }
}

/// Whether a preset can honestly be pressed, and why not.
enum PresetAvailability: Equatable {
    case available(OrcsModel)
    case missingModel(requirement: String, installed: [String])
    /// The inventory has not been read yet — grey, per the fourth design rule,
    /// rather than optimistically enabled.
    case unknown

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Shown under the preset's title, so the button carries its own reason.
    var caption: String {
        switch self {
        case .available(let model): return model.name
        case .missingModel(let requirement, let installed):
            return installed.isEmpty
                ? "needs \(requirement) — no models installed"
                : "needs \(requirement) — not installed"
        case .unknown: return "checking what is installed…"
        }
    }

    var detail: String {
        switch self {
        case .available(let model):
            return "Runs against \(model.summary), which `orcs models` reports on disk."
        case .missingModel(let requirement, let installed):
            let list = installed.isEmpty ? "nothing" : installed.joined(separator: ", ")
            return "This verb needs \(requirement). `orcs models` reports: \(list). "
                + "Offering the button anyway would mean claiming a capability this machine "
                + "cannot back up."
        case .unknown:
            return "`orcs models` has not answered yet."
        }
    }
}

// MARK: - Reading the wrapper's own output

enum OrcsDiagnostics {
    /// `orcs` narrates the load on stderr — one banner line naming the model,
    /// profile and context window, then a dot per progress step. The banner is
    /// the only trustworthy answer to "which model actually replied", so it is
    /// kept and shown; the dots are noise.
    static func banner(_ stderr: String) -> String? {
        for line in stderr.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("Loading ") else { continue }
            return String(text.dropFirst("Loading ".count))
        }
        return nil
    }

    /// The context window the banner admits to, when it states one. The assembled
    /// prompt has to fit inside it *with* the answer, which is the whole reason
    /// the prompt is budgeted at all.
    static func contextTokens(_ stderr: String) -> Int? {
        guard let banner = banner(stderr) else { return nil }
        let fields = banner.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = fields.firstIndex(of: "ctx"), index + 1 < fields.count else { return nil }
        return Int(fields[index + 1])
    }

    /// The most useful line to show when a run failed. Dot-progress and the
    /// banner are dropped: neither says what went wrong.
    static func failureLine(_ run: OrcsRun) -> String? {
        switch run.outcome {
        case .spawnFailed(let reason):
            return reason
        case .timedOut:
            return "timed out after \(Int(Orcs.requestTimeout))s with no answer"
        case .cancelled:
            return nil
        case .exited(let status):
            let lines = run.stderr
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    !line.isEmpty
                        && !line.hasPrefix("Loading ")
                        && line.contains(where: { $0 != "." })
                }
            return lines.last ?? "exited \(status) without saying why"
        }
    }
}
