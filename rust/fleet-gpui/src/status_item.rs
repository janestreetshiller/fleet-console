//! The status-area item.
//!
//! macOS: an `NSStatusItem` in the menu bar, created on the main thread
//! through the Objective-C runtime. Its button shows the F/C logo as a
//! template image; a click sends on a channel that a GPUI task reads, which
//! opens, focuses or closes the quick view as a popover under the item.
//!
//! Linux: this client does not publish a StatusNotifierItem. The window shows
//! `fleet_ui_core::platform::status_area()`'s answer in words: either that a
//! host exists but no item is published, or why no host is available. The
//! client then runs as an ordinary window and quits when it is closed.

use fleet_ui_core::platform::StatusArea;

/// Where the status item sits, in points relative to the top-left corner of
/// its display: the left edge and bottom edge of the item, and its width.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Anchor {
    pub display: u32,
    pub x: f32,
    pub y: f32,
    pub width: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Unavailable {
    /// No item, for this reason.
    Immediate(String),
    /// The reason needs a session-bus query; run `describe(status_area())`
    /// off the main thread.
    Probe,
}

/// Top-left corner for a popover of `window_width` under the item: right
/// edges aligned, kept 8 points inside the display.
pub fn popover_origin(anchor: Anchor, display_width: f32, window_width: f32) -> (f32, f32) {
    let right = anchor.x + anchor.width;
    let max_x = (display_width - window_width - 8.0).max(8.0);
    ((right - window_width).clamp(8.0, max_x), anchor.y + 4.0)
}

/// The sentence a window shows when there is no status-area item.
pub fn describe(area: &StatusArea) -> Option<String> {
    match area {
        StatusArea::MenuBar => None,
        StatusArea::StatusNotifier => Some(
            "A StatusNotifierItem host is running, but this client does not publish a tray item yet; it runs as an ordinary window."
                .into(),
        ),
        StatusArea::Unavailable(reason) => Some(format!(
            "No status-area item: {reason}. The client runs as an ordinary window."
        )),
    }
}

// objc 0.2's `msg_send!`, `sel!` and `class!` expand to a test of
// `feature = "cargo-clippy"`, which this crate does not declare.
#[cfg(target_os = "macos")]
#[allow(unexpected_cfgs)]
mod mac {
    use super::{Anchor, Unavailable};
    use crate::logo::{self, Tone};
    use cocoa::base::{id, nil, YES};
    use cocoa::foundation::{NSPoint, NSRect, NSSize, NSString};
    use futures::channel::mpsc::{unbounded, UnboundedReceiver, UnboundedSender};
    use objc::declare::ClassDecl;
    use objc::runtime::{Class, Object, Sel};
    use objc::{class, msg_send, sel, sel_impl};
    use std::sync::{Mutex, OnceLock};

    const TARGET_CLASS: &str = "FleetConsoleStatusItemTarget";
    /// `NSVariableStatusItemLength`.
    const VARIABLE_LENGTH: f64 = -1.0;

    static CLICKS: Mutex<Option<UnboundedSender<()>>> = Mutex::new(None);

    extern "C" fn clicked(_this: &Object, _cmd: Sel, _sender: id) {
        if let Ok(guard) = CLICKS.lock() {
            if let Some(tx) = guard.as_ref() {
                let _ = tx.unbounded_send(());
            }
        }
    }

    fn target_class() -> &'static Class {
        static CLASS: OnceLock<&'static Class> = OnceLock::new();
        CLASS.get_or_init(|| {
            if let Some(existing) = Class::get(TARGET_CLASS) {
                return existing;
            }
            let mut decl = ClassDecl::new(TARGET_CLASS, class!(NSObject))
                .expect("the status item target class name is unused");
            // SAFETY: the method signature matches an action selector taking
            // one object argument.
            unsafe {
                decl.add_method(
                    sel!(fleetStatusItemClicked:),
                    clicked as extern "C" fn(&Object, Sel, id),
                );
            }
            decl.register()
        })
    }

    /// An autoreleased NSString.
    unsafe fn ns_string(text: &str) -> id {
        unsafe {
            let s: id = NSString::alloc(nil).init_str(text);
            msg_send![s, autorelease]
        }
    }

    /// The logo as an 18 by 15 point template image: the F opaque, the C at
    /// partial alpha, overlap cells between, so the menu bar tints it for
    /// light and dark appearances.
    unsafe fn logo_image() -> id {
        const CELL: f64 = 3.0;
        unsafe {
            let size = NSSize::new(CELL * logo::COLUMNS as f64, CELL * logo::ROWS as f64);
            let image: id = msg_send![class!(NSImage), alloc];
            let image: id = msg_send![image, initWithSize: size];
            if image == nil {
                return nil;
            }
            let _: () = msg_send![image, lockFocus];
            for (row, column, tone) in logo::cells() {
                let alpha: f64 = match tone {
                    Tone::Bright => 1.0,
                    Tone::Dither => 0.7,
                    Tone::Dark => 0.45,
                };
                let color: id = msg_send![class!(NSColor), colorWithWhite: 0.0f64 alpha: alpha];
                let _: () = msg_send![color, set];
                let rect = NSRect::new(
                    NSPoint::new(
                        column as f64 * CELL,
                        (logo::ROWS - 1 - row) as f64 * CELL,
                    ),
                    NSSize::new(CELL, CELL),
                );
                let _: () = msg_send![class!(NSBezierPath), fillRect: rect];
            }
            let _: () = msg_send![image, unlockFocus];
            let _: () = msg_send![image, setTemplate: YES];
            msg_send![image, autorelease]
        }
    }

    /// The menu bar item. Lives for the rest of the process; AppKit objects
    /// here are touched only on the main thread.
    pub struct Item {
        item: id,
        _target: id,
    }

    impl Item {
        /// Must run on the main thread after the application has launched,
        /// which is where GPUI's `Application::run` callback runs.
        pub fn install() -> Result<(Self, UnboundedReceiver<()>), Unavailable> {
            let refuse = |why: &str| {
                Unavailable::Immediate(format!(
                    "No menu bar item: {why}. The client runs as an ordinary window."
                ))
            };
            let (tx, rx) = unbounded();
            // SAFETY: AppKit calls on the main thread with checked results.
            unsafe {
                let bar: id = msg_send![class!(NSStatusBar), systemStatusBar];
                if bar == nil {
                    return Err(refuse("the system status bar is unavailable"));
                }
                let item: id = msg_send![bar, statusItemWithLength: VARIABLE_LENGTH];
                if item == nil {
                    return Err(refuse("the status bar did not create an item"));
                }
                // The status bar does not keep the item alive by itself.
                let item: id = msg_send![item, retain];
                let button: id = msg_send![item, button];
                if button == nil {
                    let _: () = msg_send![bar, removeStatusItem: item];
                    return Err(refuse("the status item has no button"));
                }
                let image = logo_image();
                if image != nil {
                    let _: () = msg_send![button, setImage: image];
                } else {
                    let _: () = msg_send![button, setTitle: ns_string("FC")];
                }
                let _: () = msg_send![button, setToolTip: ns_string("FleetConsole")];
                // VoiceOver reads this native control even though the GPUI
                // windows expose no accessibility tree.
                let _: () =
                    msg_send![button, setAccessibilityLabel: ns_string("FleetConsole quick view")];
                let target: id = msg_send![target_class(), new];
                let _: () = msg_send![button, setTarget: target];
                let _: () = msg_send![button, setAction: sel!(fleetStatusItemClicked:)];
                if let Ok(mut clicks) = CLICKS.lock() {
                    *clicks = Some(tx);
                }
                Ok((
                    Self {
                        item,
                        _target: target,
                    },
                    rx,
                ))
            }
        }

        pub fn anchor(&self) -> Option<Anchor> {
            // SAFETY: read-only AppKit queries on the main thread.
            unsafe {
                let button: id = msg_send![self.item, button];
                if button == nil {
                    return None;
                }
                let window: id = msg_send![button, window];
                if window == nil {
                    return None;
                }
                let frame: NSRect = msg_send![window, frame];
                let screen: id = msg_send![window, screen];
                if screen == nil {
                    return None;
                }
                let screen_frame: NSRect = msg_send![screen, frame];
                let description: id = msg_send![screen, deviceDescription];
                let number: id = msg_send![description, objectForKey: ns_string("NSScreenNumber")];
                if number == nil {
                    return None;
                }
                let display: u32 = msg_send![number, unsignedIntValue];
                Some(Anchor {
                    display,
                    x: (frame.origin.x - screen_frame.origin.x) as f32,
                    y: (screen_frame.origin.y + screen_frame.size.height - frame.origin.y) as f32,
                    width: frame.size.width as f32,
                })
            }
        }
    }
}

#[cfg(target_os = "macos")]
pub use mac::Item;

/// No status item is published on this platform; see the module notes.
#[cfg(not(target_os = "macos"))]
pub struct Item;

#[cfg(not(target_os = "macos"))]
impl Item {
    pub fn install() -> Result<(Self, futures::channel::mpsc::UnboundedReceiver<()>), Unavailable> {
        Err(Unavailable::Probe)
    }

    pub fn anchor(&self) -> Option<Anchor> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn popover_hangs_under_the_item_inside_the_display() {
        let anchor = Anchor {
            display: 1,
            x: 1200.0,
            y: 24.0,
            width: 30.0,
        };
        assert_eq!(popover_origin(anchor, 1512.0, 600.0), (630.0, 28.0));
        let near_left = Anchor { x: 40.0, ..anchor };
        assert_eq!(popover_origin(near_left, 1512.0, 600.0).0, 8.0);
        let near_right = Anchor { x: 1500.0, ..anchor };
        assert_eq!(popover_origin(near_right, 1512.0, 600.0).0, 904.0);
    }

    #[test]
    fn missing_status_area_is_explained() {
        assert_eq!(describe(&StatusArea::MenuBar), None);
        let text = describe(&StatusArea::Unavailable("no session bus".into())).unwrap();
        assert!(text.contains("no session bus") && text.contains("ordinary window"));
        assert!(describe(&StatusArea::StatusNotifier)
            .unwrap()
            .contains("does not publish"));
    }
}
