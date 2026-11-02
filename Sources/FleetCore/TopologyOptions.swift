import Foundation

/// Strict read-only command options; a boolean flag never consumes an operand.
public struct TopologyOptions: Sendable, Equatable {
    public var owner: String?
    public var snapshotPath: String?
    public var json = false

    public init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--json":
                guard !json else { throw FleetError.rejected("--json may appear once") }
                json = true
            case "--owner", "--snapshot":
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"),
                      !arguments[index + 1].isEmpty else { throw FleetError.rejected("\(flag) needs a value") }
                index += 1
                if flag == "--owner" {
                    guard owner == nil else { throw FleetError.rejected("--owner may appear once") }
                    owner = arguments[index]
                } else {
                    guard snapshotPath == nil else { throw FleetError.rejected("--snapshot may appear once") }
                    snapshotPath = arguments[index]
                }
            default:
                throw FleetError.rejected("usage: fleetctl topology [--owner <exact-id>] [--snapshot <path>] [--json]")
            }
            index += 1
        }
    }
}
