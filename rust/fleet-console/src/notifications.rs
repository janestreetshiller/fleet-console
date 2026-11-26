use crate::snapshot::Message;

#[cfg(target_os = "macos")]
pub(crate) use macos::Notifications;

#[derive(Default)]
struct Mailbox {
    seen_through: Option<i64>,
}

impl Mailbox {
    fn update(&mut self, messages: &[Message], mut deliver: impl FnMut(&Message)) {
        let previous = self.seen_through.unwrap_or_default();
        let mut newest = previous;
        for message in messages {
            if message.id <= previous {
                continue;
            }
            newest = newest.max(message.id);
            if self.seen_through.is_some()
                && message.seen_at.is_none()
                && (message.is_awaiting_reply() || message.kind == "problem")
            {
                deliver(message);
            }
        }
        self.seen_through = Some(newest);
    }
}

struct Notification<'a> {
    identifier: String,
    title: String,
    body: &'a str,
    subtitle: Option<&'a str>,
}

impl<'a> From<&'a Message> for Notification<'a> {
    fn from(message: &'a Message) -> Self {
        let suffix = if message.kind == "problem" {
            ": problem"
        } else {
            " needs an answer"
        };
        Self {
            identifier: format!("fleet.message.{}", message.id),
            title: format!("{}{suffix}", message.agent),
            body: &message.body,
            subtitle: message.service_name.as_deref(),
        }
    }
}

#[cfg(target_os = "macos")]
mod macos {
    use std::ffi::CStr;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Once;

    use block::ConcreteBlock;
    use cocoa::base::{id, nil, BOOL, YES};
    use cocoa::foundation::NSString;
    use objc::rc::{autoreleasepool, StrongPtr};
    use objc::runtime::Class;
    use objc::{class, msg_send, sel, sel_impl};

    use super::{Mailbox, Notification};
    use crate::snapshot::Snapshot;

    #[link(name = "UserNotifications", kind = "framework")]
    extern "C" {}

    const AUTHORIZATION_SOUND: usize = 1 << 1;
    const AUTHORIZATION_ALERT: usize = 1 << 2;
    static REQUEST_AUTHORIZATION: Once = Once::new();
    static AUTHORIZED: AtomicBool = AtomicBool::new(false);

    pub(crate) struct Notifications {
        mailbox: Mailbox,
    }

    impl Notifications {
        pub(crate) fn new() -> Self {
            REQUEST_AUTHORIZATION.call_once(|| autoreleasepool(request_authorization));
            Self {
                mailbox: Mailbox::default(),
            }
        }

        pub(crate) fn update(&mut self, snapshot: &Snapshot) {
            let authorized = AUTHORIZED.load(Ordering::Relaxed);
            self.mailbox.update(&snapshot.messages, |message| {
                if authorized {
                    autoreleasepool(|| post(Notification::from(message)));
                }
            });
        }
    }

    fn center() -> id {
        Class::get("UNUserNotificationCenter").map_or(nil, |class| unsafe {
            msg_send![class, currentNotificationCenter]
        })
    }

    fn request_authorization() {
        let center = center();
        if center.is_null() {
            eprintln!("FleetConsole: UserNotifications center unavailable");
            return;
        }
        let completion = ConcreteBlock::new(|granted: BOOL, error: id| {
            let granted = granted == YES;
            AUTHORIZED.store(granted, Ordering::Relaxed);
            if error.is_null() {
                let status = if granted { "authorized" } else { "declined" };
                eprintln!("FleetConsole: notifications {status}");
            } else {
                log_error("notification authorization failed", error);
            }
        })
        .copy();
        let options = AUTHORIZATION_SOUND | AUTHORIZATION_ALERT;
        unsafe {
            let _: () = msg_send![center, requestAuthorizationWithOptions: options
                completionHandler: &*completion];
        }
    }

    fn post(notification: Notification<'_>) {
        let center = center();
        if center.is_null() {
            return;
        }
        let completion = ConcreteBlock::new(|error: id| {
            if !error.is_null() {
                log_error("could not post notification", error);
            }
        })
        .copy();
        unsafe {
            let content = StrongPtr::new(msg_send![class!(UNMutableNotificationContent), new]);
            let content = *content;
            let _: () = msg_send![content, setTitle: ns_string(&notification.title)];
            let _: () = msg_send![content, setBody: ns_string(notification.body)];
            if let Some(subtitle) = notification.subtitle {
                let _: () = msg_send![content, setSubtitle: ns_string(subtitle)];
            }
            let sound: id = msg_send![class!(UNNotificationSound), defaultSound];
            let _: () = msg_send![content, setSound: sound];
            let request: id = msg_send![class!(UNNotificationRequest),
                requestWithIdentifier: ns_string(&notification.identifier) content: content trigger: nil];
            let _: () = msg_send![center, addNotificationRequest: request
                withCompletionHandler: &*completion];
        }
    }

    unsafe fn ns_string(value: &str) -> id {
        let value = NSString::alloc(nil).init_str(value);
        msg_send![value, autorelease]
    }

    fn log_error(message: &str, error: id) {
        unsafe {
            let description: id = msg_send![error, localizedDescription];
            let text = description.UTF8String();
            if !text.is_null() {
                let text = CStr::from_ptr(text).to_string_lossy();
                eprintln!("FleetConsole: {message}: {text}");
                return;
            }
        }
        eprintln!("FleetConsole: {message}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::Snapshot;

    fn delivered(mailbox: &mut Mailbox, messages: &[Message]) -> Vec<i64> {
        let mut ids = Vec::new();
        mailbox.update(messages, |message| ids.push(message.id));
        ids
    }

    fn problem(id: i64) -> Message {
        Message {
            id,
            kind: "problem".into(),
            ..Message::default()
        }
    }

    #[test]
    fn ignores_initial_history_and_never_replays_it_on_reconnect() {
        let mut mailbox = Mailbox::default();
        assert!(delivered(&mut mailbox, &[problem(9), problem(8)]).is_empty());
        assert_eq!(
            delivered(&mut mailbox, &[problem(12), problem(10), problem(9)]),
            [12, 10]
        );
        assert!(delivered(&mut mailbox, &[]).is_empty());
        assert!(delivered(&mut mailbox, &[problem(10), problem(8)]).is_empty());
        assert_eq!(delivered(&mut mailbox, &[problem(13), problem(12)]), [13]);
        assert!(delivered(&mut mailbox, &[problem(13)]).is_empty());
    }

    #[test]
    fn first_empty_snapshot_starts_tracking_and_only_unseen_asks_or_problems_post() {
        let mut mailbox = Mailbox::default();
        assert!(delivered(&mut mailbox, &[]).is_empty());
        let snapshot: Snapshot = serde_json::from_str(
            r#"{
                "generatedAt":1000,"daemon":{"version":"1.3.0","pid":7,"startedAt":990,
                    "tickIntervalSec":5,"lastReconcileAt":999},
                "messages":[
                    {"id":6,"kind":"status"},
                    {"id":5,"kind":"problem","seenAt":999},
                    {"id":4,"kind":"question","needsReply":true,"reply":"yes"},
                    {"id":3,"kind":"question","needsReply":true,"seenAt":999},
                    {"id":2,"kind":"question","needsReply":true,"agent":"Codex","body":"Proceed?"},
                    {"id":1,"kind":"problem","agent":"Codex","body":"Failed","serviceName":"Web"}
                ]
            }"#,
        )
        .unwrap();
        assert_eq!(delivered(&mut mailbox, &snapshot.messages), [2, 1]);
        assert!(delivered(&mut mailbox, &[problem(6)]).is_empty());

        let ask = Notification::from(&snapshot.messages[4]);
        assert_eq!(ask.identifier, "fleet.message.2");
        assert_eq!(ask.title, "Codex needs an answer");
        assert_eq!(ask.body, "Proceed?");
        assert_eq!(ask.subtitle, None);

        let problem = Notification::from(&snapshot.messages[5]);
        assert_eq!(problem.identifier, "fleet.message.1");
        assert_eq!(problem.title, "Codex: problem");
        assert_eq!(problem.body, "Failed");
        assert_eq!(problem.subtitle, Some("Web"));
    }
}
