import Testing
@testable import FleetConsoleApp

struct LiveVerificationArgumentsTests {
    @Test func quickViewFlagUsesDefaultDuration() {
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "--verify-quick-view"]) == 20)
    }

    @Test func durationAndOptionsCanBeOrderedIndependently() {
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-quick-view", "--verify-live", "/capture", "60"]) == 60)
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "--verify-quick-view", "60", "--verify-daemon-socket", "/example.sock"]) == 60)
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "--verify-daemon-socket", "/example.sock", "--verify-quick-view"]) == 20)
    }

    @Test func malformedAndOutOfRangeDurationsAreRejected() {
        for value in ["", "nan", "inf", "9", "3601", "garbage", "--unknown"] {
            #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", value]) == nil)
        }
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "20", "30"]) == nil)
    }

    @Test func incompleteOptionsAreRejected() {
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live"]) == nil)
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "--verify-daemon-socket"]) == nil)
        #expect(LiveVerificationArguments.duration(["FleetConsoleApp", "--verify-live", "/capture", "--verify-daemon-socket", "--verify-quick-view"]) == nil)
    }
}
