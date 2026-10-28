import Foundation
import Darwin

public struct DeviceLinkRequest: Sendable {
    public var name: String
    public var address: String
    public var sshUser: String
    public var readServices: Bool

    public init(name: String, address: String, sshUser: String = "", readServices: Bool = false) {
        self.name = name
        self.address = address
        self.sshUser = sshUser
        self.readServices = readServices
    }

    public func device(existing: [FleetConfig.DeviceConfig]) throws -> FleetConfig.DeviceConfig {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FleetError.rejected("Enter a device name of 1–80 characters.")
        }
        let hostPattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"
        var ipv6 = in6_addr()
        let isIPv6 = inet_pton(AF_INET6, address, &ipv6) == 1
        guard isIPv6 || address.range(of: hostPattern, options: .regularExpression) != nil else {
            throw FleetError.rejected("Enter a hostname or IP address without a URL, spaces or command options.")
        }
        guard user.isEmpty || user.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$",
                                        options: .regularExpression) != nil else {
            throw FleetError.rejected("Enter an SSH username without spaces or command options.")
        }
        guard !existing.contains(where: {
            $0.localHost?.caseInsensitiveCompare(address) == .orderedSame
                || $0.tailscaleHost?.caseInsensitiveCompare(address) == .orderedSame
        }) else {
            throw FleetError.rejected("This address is already linked.")
        }
        return FleetConfig.DeviceConfig(id: UUID().uuidString.lowercased(), name: name,
                                        localHost: address, probePort: 22,
                                        remoteQuery: readServices,
                                        sshHost: user.isEmpty ? address : "\(user)@\(address)")
    }
}

/// Change only the devices array. Preserve unrelated and future config keys.
/// The existing reloadConfig RPC activates the change on the controller.
public enum DeviceLinkStore {
    @discardableResult
    public static func link(_ request: DeviceLinkRequest, at url: URL) throws -> String {
        let (data, config, root) = try read(url)
        let device = try request.device(existing: config.devices)
        var devices = config.devices
        devices.append(device)
        try write(devices, root: root, original: data, at: url)
        return device.id
    }

    public static func unlink(_ id: String, at url: URL) throws {
        let (data, config, root) = try read(url)
        guard let device = config.devices.first(where: { $0.id == id }), !device.isSelf else {
            throw FleetError.rejected("Only an additional linked device can be removed.")
        }
        try write(config.devices.filter { $0.id != id }, root: root, original: data, at: url)
    }

    private static func read(_ url: URL) throws -> (Data, FleetConfig, [String: Any]) {
        let data = try Data(contentsOf: url)
        let config = try Codec.decode(FleetConfig.self, from: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FleetError.rejected("The configuration must be a JSON object.")
        }
        return (data, config, root)
    }

    private static func write(_ devices: [FleetConfig.DeviceConfig], root: [String: Any],
                              original: Data, at url: URL) throws {
        var root = root
        // Preserve unknown fields on existing device records too.
        let previous = root["devices"] as? [[String: Any]] ?? []
        root["devices"] = try devices.map { device -> [String: Any] in
            if let original = previous.first(where: { $0["id"] as? String == device.id }) { return original }
            guard let encoded = try JSONSerialization.jsonObject(with: Codec.encoder.encode(device)) as? [String: Any] else {
                throw FleetError.storage("Device could not be encoded.")
            }
            return encoded
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard try Data(contentsOf: url) == original else {
            throw FleetError.rejected("Configuration changed while linking. Try again.")
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
