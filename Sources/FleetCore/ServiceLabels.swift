import Foundation

/// A personal tag, not a health/status vocabulary.
public enum ServiceTagColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case blue, purple, teal, orange, pink, gray

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// Client-only presentation metadata. The controller's name and evidence stay intact.
public struct ServiceLabel: Codable, Sendable, Equatable {
    public let name: String?
    public let color: ServiceTagColor?

    public init(name: String? = nil, color: ServiceTagColor? = nil) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed?.isEmpty == false ? trimmed : nil
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try values.decodeIfPresent(String.self, forKey: .name),
                  color: try values.decodeIfPresent(ServiceTagColor.self, forKey: .color))
    }

    public func displayName(fallback: String) -> String {
        name ?? fallback
    }
}
