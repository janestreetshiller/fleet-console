import Foundation
import FleetCore

protocol VLANSource: Sendable {
    var sourceName: String { get }

    func segments() async throws -> [NetworkSegment]

    func segment(forInterface interface: NetworkInterface,
                 in segments: [NetworkSegment]) -> NetworkSegment?
}

extension VLANSource {
    func segment(forInterface interface: NetworkInterface,
                 in segments: [NetworkSegment]) -> NetworkSegment? {
        guard let tag = interface.vlanTag else { return nil }
        return segments.first { $0.vlanTag == tag }
    }
}

struct ConfiguredVLANSource: VLANSource {
    let sourceName = "config.json"
    let declared: [NetworkSegment]

    init(_ segments: [FleetConfig.SegmentConfig]) {
        declared = segments.map {
            NetworkSegment(id: $0.id, name: $0.name, vlanTag: $0.tag,
                           cidr: $0.cidr, gateway: $0.gateway, purpose: $0.purpose)
        }
    }

    func segments() async throws -> [NetworkSegment] { declared }

    func segment(forInterface interface: NetworkInterface,
                 in segments: [NetworkSegment]) -> NetworkSegment? {
        if let tag = interface.vlanTag,
           let tagged = segments.first(where: { $0.vlanTag == tag }) {
            return tagged
        }
        let candidates = segments.filter { segment in
            guard let cidr = segment.cidr else { return false }
            return interface.ipv4.contains { Self.address($0, isIn: cidr) }
        }
        return candidates.max { left, right in
            (Self.prefixLength(of: left.cidr) ?? 0) < (Self.prefixLength(of: right.cidr) ?? 0)
        }
    }

    static func address(_ address: String, isIn cidr: String) -> Bool {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix) else {
            return false
        }
        let network = RoutingProbe.networkAddress(of: String(parts[0]), prefix: prefix)
        return RoutingProbe.networkAddress(of: address, prefix: prefix) == network
    }

    static func prefixLength(of cidr: String?) -> Int? {
        cidr?.split(separator: "/", maxSplits: 1).last.flatMap { Int($0) }
    }
}

@Observable
@MainActor
final class VLANRegistry {
    static let shared = VLANRegistry()

    private(set) var source: VLANSource?
    private(set) var segments: [NetworkSegment] = []
    private(set) var lastError: String?
    private(set) var refreshedAt: Date?

    var isAvailable: Bool { source != nil && !segments.isEmpty }

    var sourceName: String? { source?.sourceName }

    private var refreshing = false

    private init() {}

    func register(_ source: VLANSource) {
        self.source = source
        self.segments = []
        self.lastError = nil
        Task { await refresh() }
    }

    func unregister() {
        source = nil
        segments = []
        lastError = nil
        refreshedAt = nil
    }

    func adopt(_ declared: [FleetConfig.SegmentConfig]) {
        if let source, source.sourceName != ConfiguredVLANSource(declared).sourceName { return }
        if declared.isEmpty {
            if source != nil { unregister() }
            return
        }
        register(ConfiguredVLANSource(declared))
    }

    func refresh() async {
        guard let source, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let fetched = try await source.segments()
            segments = fetched
            lastError = nil
            refreshedAt = Date()
        } catch {
            lastError = error.localizedDescription
            refreshedAt = Date()
        }
    }

    func annotate(_ interfaces: [NetworkInterface]) -> [NetworkInterface] {
        guard let source, !segments.isEmpty else { return interfaces }
        return interfaces.map { interface in
            var copy = interface
            copy.segment = source.segment(forInterface: interface, in: segments)
            return copy
        }
    }
}
