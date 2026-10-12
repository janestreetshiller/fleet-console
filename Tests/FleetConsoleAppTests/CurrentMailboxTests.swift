import Foundation
import FleetCore
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct CurrentMailboxTests {
    @MainActor @Test("Old seen status and resolved questions are history, not current messages")
    func oldSeenAndResolvedMessagesLeaveCurrentInbox() {
        let model = AppModel()
        let old = Date().addingTimeInterval(-90 * 24 * 3600)
        let messages = [
            AgentMessage(id: 1, agent: "demo", body: "Old indexed documents", createdAt: old, seenAt: old),
            AgentMessage(id: 2, agent: "demo", kind: .problem, body: "Old database problem", createdAt: old, seenAt: old),
            AgentMessage(id: 3, agent: "demo", kind: .question, body: "Old resolved migration", createdAt: old,
                         needsReply: true, reply: "Resolved", repliedAt: old, seenAt: old)
        ]
        model.connected = true
        model.apply(Snapshot(daemon: DaemonInfo(version: "test", pid: 0, startedAt: Date()), messages: messages))
        #expect(model.recentMessages.isEmpty)
        #expect(model.awaitingReplyCount == 0)
        #expect(model.agentProfiles.allSatisfy { $0.messageCount == 0 && $0.lastMessage == nil })
        #expect(model.messageHistory == messages)
    }

    @MainActor @Test("Seen unanswered questions survive aging, replies and connection changes update the inbox")
    func mailboxTracksResolutionAndConnectionWithoutLosingHistory() {
        let model = AppModel()
        let old = Date().addingTimeInterval(-90 * 24 * 3600)
        var pending = AgentMessage(id: 42, agent: "demo", kind: .question, body: "Still waiting", createdAt: old,
                                   needsReply: true, seenAt: old)
        let daemon = DaemonInfo(version: "test", pid: 0, startedAt: Date())
        model.connected = true
        model.apply(Snapshot(daemon: daemon, messages: [pending]))
        #expect(model.awaitingReplies.map(\.id) == [42])
        #expect(model.agentProfiles.first?.lastMessage?.id == 42)
        model.connected = false
        #expect(model.recentMessages.isEmpty)
        #expect(model.messageHistory == [pending])
        model.connected = true
        #expect(model.awaitingReplies.map(\.id) == [42])
        pending.reply = "Answered"
        pending.repliedAt = Date()
        model.apply(Snapshot(daemon: daemon, messages: [pending]))
        #expect(model.recentMessages.isEmpty)
        #expect(model.awaitingReplies.isEmpty)
        #expect(model.messageHistory == [pending])
        #expect(model.agentProfiles.allSatisfy { $0.lastMessage == nil })
    }
}
