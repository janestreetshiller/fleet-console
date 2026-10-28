import Foundation
import FleetCore

// The seam a real VLAN source plugs into.
//
// This machine knows two VLAN facts about itself and no more: whether it has an
// 802.1Q interface, and what tag and parent that interface carries. Both are read
// off `ifconfig` by `RoutingProbe` and both are real. Everything else a VLAN
// admin console shows — what a segment is called, what it is for, which subnet it
// owns, which gateway serves it, what else is on it — lives in a switch, a
// controller, or a router API. A Mac cannot derive it.
//
// So this file does not implement a VLAN source. It defines what one is, and it
// is the *only* thing the UI depends on, so adding a real one later is a
// registration and not a rewrite:
//
//     VLANRegistry.shared.register(UniFiVLANSource(controller: url, token: token))
//
// Until something is registered, `VLANRegistry.shared.isAvailable` is false and
// every VLAN segment surface is absent from the UI. Not disabled, not a
// "coming soon" row, not an empty state — absent. An empty state is a claim that
// there are no segments; the truth is that nobody asked.

// MARK: - The protocol

/// Anything that can name the segments this fleet is divided into.
///
/// Deliberately small. A source has to answer one question — "what segments are
/// there, and which of this host's interfaces sits on each" — and the app will
/// not ask it anything else, so a first implementation against a router API is a
/// day's work rather than a port of the whole model.
///
/// `Sendable` and async because every plausible implementation is a network call
/// to a controller. Nothing about the UI blocks on it: `VLANRegistry` caches the
/// last answer and refreshes off the main actor, and a source that times out
/// leaves the previous snapshot in place rather than blanking the section.
protocol VLANSource: Sendable {
    /// Shown in the support bundle and in the section's provenance line, so a
    /// segment on screen can always be traced to who claimed it.
    var sourceName: String { get }

    /// Every segment this source knows about.
    func segments() async throws -> [NetworkSegment]

    /// Which segment a given host interface belongs to, if the source can say.
    /// The default implementation matches on the 802.1Q tag the host already
    /// reads for itself, which is enough for any source that reports tags.
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

// MARK: - The declared source

/// Segments as the operator declares them in `config.json`.
///
/// This is the first real `VLANSource`, and it exists because of the gap a host
/// on an access port cannot close. A Mac on a **trunk** port reads its own
/// 802.1Q tag off `ifconfig`. A Mac on an **access** port — which is almost
/// every Mac, and every Mac behind a firewall doing the segmentation — never
/// sees a tag at all: the switch strips it before the frame reaches the NIC. All
/// the host gets is an address, a subnet and a gateway.
///
/// The app will not close that gap by inference. `10.10.40.0/24` looks like
/// VLAN 40, and an implementation that reads the third octet is right on one
/// network and confidently wrong on the next. But an operator writing
/// `{"tag": 40, "cidr": "10.10.40.0/24", "name": "Guest"}` is not a heuristic —
/// it is an assertion with an author, which is exactly what `sourceName`
/// carries into the UI so a segment on screen can be traced to whoever claimed
/// it.
///
/// It is also the honest floor for the whole seam: a controller-backed source
/// can replace it, but a fleet with no controller API still gets true labels
/// instead of no labels.
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

    /// Tag first, then subnet.
    ///
    /// The tag is the stronger claim and is used whenever the host actually has
    /// one. Falling back to the subnet is what makes this work on an access
    /// port, and it is containment rather than string equality: an interface at
    /// `10.10.40.12/24` belongs to a segment declared as `10.10.40.0/24`, and
    /// also to one declared as `10.10.0.0/16`, because both are true. The most
    /// specific match wins, for the same reason a routing table prefers the
    /// longest prefix.
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

    /// IPv4 containment. Both sides are masked to the declared prefix and
    /// compared — the same arithmetic `RoutingProbe` uses to derive a subnet
    /// from a netmask, so a segment and an interface cannot disagree about what
    /// network they are on.
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

// MARK: - The registry

/// The one place a source is installed, and the one place the UI asks whether
/// there is one.
///
/// This is the capability flag from the design rules, as an object rather than a
/// boolean: `isAvailable` is false whenever no source is registered *or* the
/// registered source has not yet produced a segment, and every VLAN view is
/// gated on it. There is no path that renders a segment row from nothing.
@Observable
@MainActor
final class VLANRegistry {
    static let shared = VLANRegistry()

    private(set) var source: VLANSource?
    private(set) var segments: [NetworkSegment] = []
    private(set) var lastError: String?
    private(set) var refreshedAt: Date?

    /// The capability flag. False with no source, and false with a source that
    /// has told us about nothing — in both cases there is no segment to draw and
    /// therefore no section.
    var isAvailable: Bool { source != nil && !segments.isEmpty }

    var sourceName: String? { source?.sourceName }

    private var refreshing = false

    private init() {}

    /// Install a source. One call — this is the whole integration surface.
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

    /// Installs (or removes) the declared source to match `config.json`.
    ///
    /// Called on launch and again whenever the file changes, so declaring a
    /// segment and coming back to a UI that already shows it is the behaviour
    /// you would expect. Deleting the last declaration unregisters — which puts
    /// `isAvailable` back to false and takes every segment surface off screen
    /// rather than leaving the last-known set behind. That asymmetry with the
    /// *failure* path above is deliberate: a controller that times out has not
    /// deleted your VLANs, but you deleting the lines has.
    ///
    /// A registered non-config source is left alone. A real controller outranks
    /// a hand-written list, and a config reload must not silently evict one.
    func adopt(_ declared: [FleetConfig.SegmentConfig]) {
        if let source, source.sourceName != ConfiguredVLANSource(declared).sourceName { return }
        if declared.isEmpty {
            if source != nil { unregister() }
            return
        }
        register(ConfiguredVLANSource(declared))
    }

    /// Re-asks the source. Never throws into the UI and never leaves the section
    /// half-drawn: a failure records the message and keeps the previous
    /// segments, because a controller that is briefly unreachable has not
    /// deleted your VLANs.
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

    /// Decorates the host's interfaces with the segment each one sits on.
    /// A no-op when no source is registered, which is what keeps `segment` nil
    /// and every VLAN affordance out of the tree.
    func annotate(_ interfaces: [NetworkInterface]) -> [NetworkInterface] {
        guard let source, !segments.isEmpty else { return interfaces }
        return interfaces.map { interface in
            var copy = interface
            copy.segment = source.segment(forInterface: interface, in: segments)
            return copy
        }
    }
}
