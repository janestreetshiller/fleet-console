import Foundation
import Testing
import FleetCore

struct DeviceLinkingTests {
    @Test("First run lists only the computer the user is actually on")
    func firstRunDoesNotInventPeers() {
        let config = FleetConfig.makeDefault(selfHostName: "Office Mac", selfTailscaleName: nil)
        #expect(config.devices.count == 1)
        #expect(config.devices.allSatisfy { $0.isSelf })
        #expect(config.devices.first?.name == "Office Mac")
    }

    @Test("Linking validates input and never enables remote inventory implicitly")
    func validation() throws {
        let request = DeviceLinkRequest(name: "Office", address: "office.local", sshUser: "operator")
        let device = try request.device(existing: [])
        #expect(device.sshHost == "operator@office.local")
        #expect(!device.remoteQuery)
        #expect(!device.isSelf)
        #expect(try DeviceLinkRequest(name: "IPv6", address: "::1").device(existing: []).localHost == "::1")
        for address in ["-oProxyCommand=command", "host name", "https://host", "host;command", ""] {
            #expect(throws: (any Error).self) {
                try DeviceLinkRequest(name: "Office", address: address).device(existing: [])
            }
        }
        #expect(throws: (any Error).self) { try request.device(existing: [device]) }
    }

    @Test("Link and unlink preserve unknown config and device fields on disk")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let original = """
        {"future":{"keep":true},"ui":{"features":{"allowProcessTermination":true}},
         "devices":[{"id":"self","name":"Local","isSelf":true,"futureDeviceField":"keep"}]}
        """
        try Data(original.utf8).write(to: url)
        let id = try DeviceLinkStore.link(DeviceLinkRequest(name: "Office", address: "office.local"), at: url)
        let linked = try Codec.decode(FleetConfig.self, from: Data(contentsOf: url))
        #expect(linked.devices.count == 2)
        #expect(linked.ui.features.allowProcessTermination)
        #expect(throws: (any Error).self) { try DeviceLinkStore.unlink("self", at: url) }
        try DeviceLinkStore.unlink(id, at: url)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        #expect((root["future"] as? [String: Bool])?["keep"] == true)
        #expect((root["devices"] as? [[String: Any]])?.first?["futureDeviceField"] as? String == "keep")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("Malformed config is preserved when linking fails")
    func malformedConfiguration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("{broken".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) {
            try DeviceLinkStore.link(DeviceLinkRequest(name: "Office", address: "office.local"), at: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
