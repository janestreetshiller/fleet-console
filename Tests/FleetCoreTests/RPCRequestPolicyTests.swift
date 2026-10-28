import XCTest
@testable import FleetCore

final class RPCRequestPolicyTests: XCTestCase {
    func testRendererLiveVerificationSelectsOverrideSocket() {
        let arguments = ["FleetConsoleApp", "--verify-live", "captures", "10",
                         "--verify-daemon-socket", "/missing/fleetd.sock"]
        XCTAssertEqual(RPCRequestPolicy.daemonSocketPath(forArguments: arguments,
                                                        surfaceRenderer: true,
                                                        defaultPath: "/normal/fleetd.sock"),
                       "/missing/fleetd.sock")
    }

    func testSocketOverrideRequiresRendererAndExactLiveVerification() {
        let override = ["--verify-daemon-socket", "/missing/fleetd.sock"]
        let cases: [(arguments: [String], renderer: Bool)] = [
            (["FleetConsoleApp", "--verify-live", "captures"] + override, false),
            (["FleetConsoleApp"] + override, true),
            (["FleetConsoleApp", "--verify-live-preview", "captures"] + override, true),
            (["FleetConsoleApp", "--verify-live=captures"] + override, true),
            (["FleetConsoleApp", "--verify-live", "captures"], true),
            (["FleetConsoleApp"], false),
        ]
        for (arguments, renderer) in cases {
            XCTAssertEqual(RPCRequestPolicy.daemonSocketPath(forArguments: arguments,
                                                            surfaceRenderer: renderer,
                                                            defaultPath: "/normal/fleetd.sock"),
                           "/normal/fleetd.sock", "arguments: \(arguments), renderer: \(renderer)")
        }
    }

    func testLiveVerificationSelectsObservationalPolicy() {
        XCTAssertEqual(RPCRequestPolicy.forArguments(["FleetConsoleApp", "--verify-live", "captures"]),
                       .observational)
        XCTAssertEqual(RPCRequestPolicy.forArguments(["FleetConsoleApp"]), .interactive)
        XCTAssertEqual(RPCRequestPolicy.forArguments(["FleetConsoleApp", "--verify-live-preview"]),
                       .interactive)
    }

    func testObservationalPolicyAllowsOnlyReadOperations() {
        for operation: RPCOp in [.ping, .snapshot, .subscribe, .events, .logs, .messages] {
            XCTAssertTrue(RPCRequestPolicy.observational.allows(operation), operation.rawValue)
        }
    }

    func testObservationalSendRejectsDeviceRefreshBeforeConnecting() {
        // An empty socket path never targets the installed daemon. The policy
        // must reject the request before attempting any connection.
        XCTAssertThrowsError(try UnixSocketClient.send(
            RPCRequest(op: .refreshDevices), path: "", policy: .observational
        )) { error in
            guard case FleetError.rejected(let reason) = error else {
                return XCTFail("Expected policy rejection, got \(error)")
            }
            XCTAssertTrue(reason.contains("observational"))
            XCTAssertTrue(reason.contains(RPCOp.refreshDevices.rawValue))
        }
    }

    func testObservationalPolicyRejectsEveryMutatingOperation() {
        let operations: [RPCOp] = [
            .launch, .renew, .stop, .restart, .claim, .reconcile, .refreshDevices,
            .reloadConfig, .ignoreCommand, .prune, .pause, .resume, .kill,
            .postMessage, .reply, .markSeen
        ]
        for operation in operations {
            XCTAssertFalse(RPCRequestPolicy.observational.allows(operation), operation.rawValue)
            XCTAssertTrue(RPCRequestPolicy.interactive.allows(operation), operation.rawValue)
            XCTAssertThrowsError(try UnixSocketClient.send(
                RPCRequest(op: operation), path: "", policy: .observational
            )) { error in
                guard case FleetError.rejected = error else {
                    return XCTFail("Expected policy rejection for \(operation), got \(error)")
                }
            }
        }
    }
}
