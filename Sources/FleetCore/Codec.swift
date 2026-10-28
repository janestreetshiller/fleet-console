import Foundation

/// One encoder/decoder pair shared by the daemon, the CLI and the app so wire
/// formats can never drift (dates are always epoch seconds).
public enum Codec {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    public static func jsonString<T: Encodable>(_ value: T, pretty: Bool = false) -> String {
        let enc = pretty ? prettyEncoder : encoder
        guard let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}

public enum FleetError: LocalizedError {
    case daemonUnavailable(String)
    case rejected(String)
    case notFound(String)
    case storage(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .daemonUnavailable(let m): return "controller unavailable: \(m)"
        case .rejected(let m): return "rejected: \(m)"
        case .notFound(let m): return "not found: \(m)"
        case .storage(let m): return "registry error: \(m)"
        case .io(let m): return "io error: \(m)"
        }
    }
}
