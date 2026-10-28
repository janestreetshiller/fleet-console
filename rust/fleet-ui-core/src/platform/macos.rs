//! macOS specifics.

use super::{run_bounded, Capability, StatusArea, Support, Volume};
use crate::observe::{Metric, Reason};
use std::time::Duration;

pub(super) const CAPABILITIES: &[Capability] = &[
    Capability {
        value: "cpu",
        support: Support::Measured,
        source: "host processor load via sysinfo",
    },
    Capability {
        value: "memory",
        support: Support::Measured,
        source: "sysinfo used memory (host_statistics64); the Swift app's memory figure may differ",
    },
    Capability {
        value: "disk",
        support: Support::Measured,
        source:
            "statfs of /System/Volumes/Data; excludes purgeable space the Swift app counts as free",
    },
    Capability {
        value: "network",
        support: Support::Measured,
        source: "en* interface counters via getifaddrs",
    },
    Capability {
        value: "gpu",
        support: Support::NotMeasured,
        source: "IOAccelerator statistics are read by the Swift app only",
    },
    Capability {
        value: "processes",
        support: Support::Measured,
        source: "libproc via sysinfo, names only",
    },
    Capability {
        value: "thermal",
        support: Support::NotMeasured,
        source: "no sensor read; CPU load is never relabelled as temperature",
    },
];

pub(super) fn is_user_volume(mount: &str, _filesystem: &str) -> bool {
    mount == "/"
        || mount == "/System/Volumes/Data"
        || (mount.starts_with("/Volumes/") && !mount.starts_with("/Volumes/com.apple"))
}

pub(super) fn primary_volume(volumes: &[Volume]) -> Option<&Volume> {
    volumes
        .iter()
        .find(|v| v.mount == "/System/Volumes/Data")
        .or_else(|| volumes.iter().find(|v| v.mount == "/"))
}

/// Wi-Fi and wired links are `en*`. Tunnels (`utun*`), AirDrop (`awdl*`) and
/// bridges are excluded, matching the Swift app's physical-interface rule.
pub(super) fn is_physical_interface(name: &str) -> bool {
    name.starts_with("en")
}

pub(super) fn gpu_busy_percent() -> Metric {
    Metric::Unavailable(Reason::NotMeasured)
}

pub(super) fn status_area() -> StatusArea {
    StatusArea::MenuBar
}

pub(super) fn notify(title: &str, body: &str) -> Result<(), String> {
    let quote = |s: &str| s.replace('\\', "\\\\").replace('"', "\\\"");
    let script = format!(
        "display notification \"{}\" with title \"{}\"",
        quote(body),
        quote(title)
    );
    run_bounded(
        "/usr/bin/osascript",
        &["-e", &script],
        Duration::from_secs(3),
    )
    .map(|_| ())
    .ok_or_else(|| "osascript did not post the notification".to_string())
}
