import Foundation
import FleetCore
import Testing

struct CurrentMessageTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func seenNoticesAgeOutAtTheInboxBoundary() {
        let seen = AgentMessage(agent: "demo", body: "Finished", createdAt: now.addingTimeInterval(-3600), seenAt: now)
        #expect(seen.isCurrent(at: now))
        #expect(!seen.isCurrent(at: now.addingTimeInterval(24 * 3600)))
        #expect(seen.isCurrent(at: now, recentWindow: 3600))
        #expect(!seen.isCurrent(at: now, recentWindow: 3599))
    }

    @Test func unreadNoticesAndUnansweredQuestionsDoNotExpire() {
        let old = now.addingTimeInterval(-90 * 24 * 3600)
        let unread = AgentMessage(agent: "demo", body: "Unread", createdAt: old)
        let pending = AgentMessage(agent: "demo", kind: .question, body: "Still needs an answer", createdAt: old,
                                   needsReply: true, seenAt: old)
        #expect(unread.isCurrent(at: now))
        #expect(pending.isCurrent(at: now))
    }

    @Test func resolutionRemovesEvenAFreshUnseenQuestion() {
        let resolved = AgentMessage(agent: "demo", kind: .question, body: "Resolved", createdAt: now,
                                    needsReply: true, reply: "Done", repliedAt: now)
        #expect(!resolved.isCurrent(at: now))
        var timestampOnly = resolved
        timestampOnly.reply = nil
        #expect(!timestampOnly.isCurrent(at: now))
    }
}
