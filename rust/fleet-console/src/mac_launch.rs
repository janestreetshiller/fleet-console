use std::ffi::{c_void, CStr};
use std::sync::LazyLock;

use cocoa::base::{id, nil, BOOL, YES};
use cocoa::foundation::{NSAutoreleasePool, NSString};
use futures::channel::mpsc::UnboundedSender;
use objc::declare::ClassDecl;
use objc::runtime::{Class, Object, Sel};
use objc::{class, msg_send, sel, sel_impl};

use crate::{Module, ShellEvent, BUNDLE_ID, DASHBOARD_ROUTES};

const DASHBOARD_NOTIFICATION: &str = "com.fleetconsole.openDashboard";
const DASHBOARD_MODULE_KEY: &str = "module";
const OBSERVER_SENDER: &str = "fleetConsoleSender";
const POLICY_REGULAR: isize = 0;
const POLICY_ACCESSORY: isize = 1;

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFGetTypeID(value: *const c_void) -> usize;
    fn CFBooleanGetTypeID() -> usize;
    fn CFBooleanGetValue(value: *const c_void) -> u8;
}

#[derive(Debug, PartialEq, Eq)]
struct Review {
    enabled: bool,
    regular_activation: bool,
}

impl Review {
    fn new(args: &[String], review_build: bool) -> Self {
        Self {
            enabled: review_build || args.iter().any(|arg| arg == "--review"),
            regular_activation: review_build,
        }
    }

    fn dashboard(&self, requested: Option<Module>) -> Option<Module> {
        requested.or_else(|| self.enabled.then_some(Module::Overview))
    }
}

struct BundleIdentity {
    identifier: String,
    dashboard_notification: String,
}

impl BundleIdentity {
    fn new(identifier: String) -> Self {
        let dashboard_notification = if identifier == BUNDLE_ID {
            DASHBOARD_NOTIFICATION.to_owned()
        } else {
            format!("{identifier}.fleetConsoleOpenDashboard")
        };
        Self {
            identifier,
            dashboard_notification,
        }
    }
}

pub(super) struct Launch {
    bundle: Option<BundleIdentity>,
    review: Review,
}

impl Launch {
    pub(super) fn new(args: &[String]) -> Self {
        let (bundle, review_build) = unsafe {
            let pool = NSAutoreleasePool::new(nil);
            let bundle: id = msg_send![class!(NSBundle), mainBundle];
            let identity = bundle_identity(bundle);
            let review_build = identity.is_some() && plist_review_build(bundle);
            pool.drain();
            (identity, review_build)
        };
        Self {
            bundle,
            review: Review::new(args, review_build),
        }
    }

    pub(super) fn startup_dashboard(&self, requested: Option<Module>) -> Option<Module> {
        self.review.dashboard(requested)
    }

    pub(super) fn enables_onboarding(&self) -> bool {
        !self.review.enabled
            && self.bundle.as_ref().is_some_and(|bundle| bundle.identifier == BUNDLE_ID)
            && std::env::var_os(fleet_proto::STATE_ROOT_VARIABLE).is_none_or(|root| root.is_empty())
    }

    pub(super) fn apply_activation_policy(&self) {
        let policy = if self.review.regular_activation {
            POLICY_REGULAR
        } else {
            POLICY_ACCESSORY
        };
        unsafe {
            let app: id = msg_send![class!(NSApplication), sharedApplication];
            let _: BOOL = msg_send![app, setActivationPolicy: policy];
        }
    }

    pub(super) fn handoff(&self, requested: Option<Module>) -> bool {
        let Some(bundle) = &self.bundle else {
            return false;
        };
        unsafe {
            let pool = NSAutoreleasePool::new(nil);
            let existing = earlier_instance(&bundle.identifier);
            if existing == nil {
                pool.drain();
                return false;
            }
            let pid: i32 = msg_send![existing, processIdentifier];
            eprintln!("FleetConsole: already running (pid {pid}); handing off");
            if let Some(module) = requested {
                post_dashboard(&bundle.dashboard_notification, module);
            }
            let _: BOOL = msg_send![existing, activateWithOptions: 0usize];
            pool.drain();
        }
        true
    }

    pub(super) fn observe_dashboard(&self, tx: &UnboundedSender<ShellEvent>) -> Option<Observer> {
        let bundle = self.bundle.as_ref()?;
        Some(Observer::new(&bundle.dashboard_notification, tx.clone()))
    }
}

unsafe fn bundle_identity(bundle: id) -> Option<BundleIdentity> {
    let url: id = msg_send![bundle, bundleURL];
    let extension: id = msg_send![url, pathExtension];
    let app_extension: BOOL = msg_send![extension, isEqualToString: ns_string("app")];
    if app_extension != YES {
        return None;
    }
    let package_type: id =
        msg_send![bundle, objectForInfoDictionaryKey: ns_string("CFBundlePackageType")];
    let identifier: id = msg_send![bundle, bundleIdentifier];
    if string(package_type) != Some("APPL") {
        return None;
    }
    let identifier = string(identifier).filter(|identifier| !identifier.is_empty())?;
    Some(BundleIdentity::new(identifier.to_owned()))
}

unsafe fn plist_review_build(bundle: id) -> bool {
    let value: id = msg_send![bundle, objectForInfoDictionaryKey: ns_string("FleetConsoleReviewBuild")];
    let value = value.cast::<c_void>();
    !value.is_null() && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value) != 0
}

unsafe fn earlier_instance(identifier: &str) -> id {
    let current: id = msg_send![class!(NSRunningApplication), currentApplication];
    let current_pid = std::process::id() as i32;
    let current_stamp = (launch_time(current), current_pid);
    let others: id =
        msg_send![class!(NSRunningApplication), runningApplicationsWithBundleIdentifier: ns_string(identifier)];
    let count: usize = msg_send![others, count];
    let mut earliest = nil;
    let mut earliest_stamp = current_stamp;
    for index in 0..count {
        let candidate: id = msg_send![others, objectAtIndex: index];
        let terminated: BOOL = msg_send![candidate, isTerminated];
        if terminated == YES {
            continue;
        }
        let pid: i32 = msg_send![candidate, processIdentifier];
        if pid == current_pid {
            continue;
        }
        let stamp = (launch_time(candidate), pid);
        if stamp
            .0
            .total_cmp(&earliest_stamp.0)
            .then_with(|| stamp.1.cmp(&earliest_stamp.1))
            .is_lt()
        {
            earliest = candidate;
            earliest_stamp = stamp;
        }
    }
    earliest
}

unsafe fn launch_time(application: id) -> f64 {
    let date: id = msg_send![application, launchDate];
    if date == nil {
        f64::INFINITY
    } else {
        msg_send![date, timeIntervalSinceReferenceDate]
    }
}

unsafe fn post_dashboard(notification: &str, module: Module) {
    let route = DASHBOARD_ROUTES
        .iter()
        .find_map(|(route, candidate)| (*candidate == module).then_some(*route))
        .expect("all dashboard modules have launch routes");
    let user_info: id = msg_send![class!(NSDictionary), dictionaryWithObject: ns_string(route)
        forKey: ns_string(DASHBOARD_MODULE_KEY)];
    let center: id = msg_send![class!(NSDistributedNotificationCenter), defaultCenter];
    let _: () = msg_send![center, postNotificationName: ns_string(notification)
        object: nil userInfo: user_info deliverImmediately: YES];
}

pub(super) struct Observer(id);

impl Observer {
    fn new(notification: &str, tx: UnboundedSender<ShellEvent>) -> Self {
        unsafe {
            let pool = NSAutoreleasePool::new(nil);
            let observer: id = msg_send![observer_class(), new];
            let sender = Box::into_raw(Box::new(tx)).cast::<c_void>();
            (*observer).set_ivar(OBSERVER_SENDER, sender);
            let center: id = msg_send![class!(NSDistributedNotificationCenter), defaultCenter];
            let _: () = msg_send![center, addObserver: observer
                selector: sel!(fleetConsoleOpenDashboard:) name: ns_string(notification) object: nil];
            pool.drain();
            Self(observer)
        }
    }
}

impl Drop for Observer {
    fn drop(&mut self) {
        unsafe {
            let pool = NSAutoreleasePool::new(nil);
            let center: id = msg_send![class!(NSDistributedNotificationCenter), defaultCenter];
            let _: () = msg_send![center, removeObserver: self.0];
            let sender = *(*self.0).get_ivar::<*mut c_void>(OBSERVER_SENDER);
            let _: () = msg_send![self.0, release];
            drop(Box::from_raw(sender.cast::<UnboundedSender<ShellEvent>>()));
            pool.drain();
        }
    }
}

fn observer_class() -> &'static Class {
    static CLASS: LazyLock<&'static Class> = LazyLock::new(|| {
        let mut class = ClassDecl::new("FleetConsoleDashboardObserver", class!(NSObject))
            .expect("dashboard observer class name is unused");
        class.add_ivar::<*mut c_void>(OBSERVER_SENDER);
        unsafe {
            class.add_method(
                sel!(fleetConsoleOpenDashboard:),
                open_dashboard as extern "C" fn(&Object, Sel, id),
            );
        }
        class.register()
    });
    *CLASS
}

extern "C" fn open_dashboard(observer: &Object, _: Sel, notification: id) {
    unsafe {
        let info: id = msg_send![notification, userInfo];
        let value: id = msg_send![info, objectForKey: ns_string(DASHBOARD_MODULE_KEY)];
        let module = string(value)
            .and_then(|value| DASHBOARD_ROUTES.iter().find(|(route, _)| *route == value))
            .map_or(Module::Overview, |(_, module)| *module);
        let sender = *observer.get_ivar::<*mut c_void>(OBSERVER_SENDER);
        let sender = &*sender.cast::<UnboundedSender<ShellEvent>>();
        let _ = sender.unbounded_send(ShellEvent::DashboardHandoff(module));
    }
}

unsafe fn ns_string(value: &str) -> id {
    let value = NSString::alloc(nil).init_str(value);
    msg_send![value, autorelease]
}

unsafe fn string<'a>(value: id) -> Option<&'a str> {
    let is_string: BOOL = msg_send![value, isKindOfClass: class!(NSString)];
    if is_string != YES {
        return None;
    }
    let text = value.UTF8String();
    if text.is_null() {
        return None;
    }
    CStr::from_ptr(text).to_str().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn review_flag_opens_dashboard_without_upgrading_activation_policy() {
        let ordinary = Review::new(&["--review=false".into()], false);
        assert_eq!(ordinary.dashboard(None), None);
        assert!(!ordinary.regular_activation);

        let cli = Review::new(&["--review".into()], false);
        assert_eq!(cli.dashboard(None), Some(Module::Overview));
        assert_eq!(cli.dashboard(Some(Module::Events)), Some(Module::Events));
        assert!(!cli.regular_activation);

        let plist = Review::new(&[], true);
        assert_eq!(plist.dashboard(None), Some(Module::Overview));
        assert!(plist.regular_activation);
    }

    #[test]
    fn temporary_bundle_cannot_post_the_installed_apps_dashboard_notification() {
        assert_eq!(
            BundleIdentity::new(BUNDLE_ID.into()).dashboard_notification,
            DASHBOARD_NOTIFICATION
        );
        let fixture = BundleIdentity::new("com.fleetconsole.launch-verification".into());
        assert_eq!(
            fixture.dashboard_notification,
            "com.fleetconsole.launch-verification.fleetConsoleOpenDashboard"
        );
    }
}
