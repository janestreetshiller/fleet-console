/// Separates observational verifier options from its optional duration.
/// Kept independent of AppKit so tests exercise the shipping argument parser.
enum LiveVerificationArguments {
    static func duration(_ arguments: [String]) -> Double? {
        if arguments.contains("--review-ui") && !arguments.contains("--verify-quick-view") { return nil }
        guard let index = arguments.firstIndex(of: "--verify-live"),
              index + 1 < arguments.count,
              !arguments[index + 1].isEmpty,
              !arguments[index + 1].hasPrefix("--") else { return nil }
        var seconds: Double?
        var cursor = index + 2
        while cursor < arguments.count {
            switch arguments[cursor] {
            case "--verify-quick-view", "--review-ui":
                cursor += 1
            case "--verify-daemon-socket":
                guard cursor + 1 < arguments.count,
                      !arguments[cursor + 1].isEmpty,
                      !arguments[cursor + 1].hasPrefix("--") else { return nil }
                cursor += 2
            default:
                guard seconds == nil, let value = Double(arguments[cursor]),
                      value.isFinite, (10...3_600).contains(value) else { return nil }
                seconds = value
                cursor += 1
            }
        }
        return seconds ?? 20
    }
}
