import Foundation
import UserNotifications
import FleetCore

@MainActor
enum Notifier {
    private static var authorized = false
    private static var requested = false

    static func requestAuthorizationIfNeeded() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                Task { @MainActor in authorized = granted }
                if let error {
                    FleetLog.warn("notification authorization failed: \(error.localizedDescription)")
                } else {
                    FleetLog.info("notifications \(granted ? "authorized" : "declined")")
                }
            }
    }

    static func post(_ message: AgentMessage) {
        guard message.isAwaitingReply || message.kind == .problem else { return }
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = message.kind == .problem
            ? "\(message.agent): problem"
            : "\(message.agent) needs an answer"
        content.body = message.body
        if let service = message.serviceName {
            content.subtitle = service
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: "fleet.message.\(message.id)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                FleetLog.warn("could not post notification: \(error.localizedDescription)")
            }
        }
    }
}
