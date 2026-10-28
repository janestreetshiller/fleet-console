//! Linux specifics.

use super::{run_bounded, Capability, StatusArea, Support, Volume};
use crate::observe::{Metric, Reason};
use std::path::Path;
use std::time::Duration;

pub(super) const CAPABILITIES: &[Capability] = &[
    Capability {
        value: "cpu",
        support: Support::Measured,
        source: "/proc/stat via sysinfo",
    },
    Capability {
        value: "memory",
        support: Support::Measured,
        source: "MemTotal minus MemAvailable via sysinfo",
    },
    Capability {
        value: "disk",
        support: Support::Measured,
        source: "statvfs of /",
    },
    Capability {
        value: "network",
        support: Support::Measured,
        source: "/proc/net/dev counters, excluding loopback, bridges, containers and tunnels",
    },
    Capability {
        value: "gpu",
        support: Support::Conditional,
        source: "amdgpu gpu_busy_percent in sysfs; Intel i915/xe and NVIDIA report unavailable",
    },
    Capability {
        value: "processes",
        support: Support::Measured,
        source: "/proc via sysinfo, names only",
    },
    Capability {
        value: "thermal",
        support: Support::NotMeasured,
        source: "no sensor read; CPU load is never relabelled as temperature",
    },
];

const PSEUDO_FILESYSTEMS: &[&str] = &[
    "tmpfs",
    "devtmpfs",
    "overlay",
    "squashfs",
    "proc",
    "sysfs",
    "ramfs",
    "autofs",
    "efivarfs",
    "fuse.portal",
    "nsfs",
    "tracefs",
    "debugfs",
];

pub(super) fn is_user_volume(mount: &str, filesystem: &str) -> bool {
    if PSEUDO_FILESYSTEMS.contains(&filesystem) || filesystem.starts_with("cgroup") {
        return false;
    }
    !(mount.starts_with("/boot")
        || mount.starts_with("/snap/")
        || mount.starts_with("/run/")
        || mount.starts_with("/var/lib/docker")
        || mount.starts_with("/var/lib/containers"))
}

pub(super) fn primary_volume(volumes: &[Volume]) -> Option<&Volume> {
    volumes
        .iter()
        .find(|v| v.mount == "/")
        .or_else(|| volumes.first())
}

const VIRTUAL_PREFIXES: &[&str] = &[
    "lo",
    "docker",
    "veth",
    "br-",
    "virbr",
    "tailscale",
    "tun",
    "tap",
    "wg",
    "vboxnet",
    "zt",
    "cni",
    "flannel",
];

pub(super) fn is_physical_interface(name: &str) -> bool {
    !VIRTUAL_PREFIXES.iter().any(|p| name.starts_with(p))
}

/// amdgpu exposes `gpu_busy_percent`; take the busiest card. Other drivers do
/// not publish a comparable counter in sysfs, so they stay unavailable.
pub(super) fn gpu_busy_percent() -> Metric {
    gpu_busy_percent_in(Path::new("/sys/class/drm"))
}

fn gpu_busy_percent_in(root: &Path) -> Metric {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Metric::Unavailable(Reason::NotMeasured);
    };
    let busiest = entries
        .flatten()
        .filter(|e| {
            let name = e.file_name();
            let name = name.to_string_lossy();
            name.starts_with("card") && !name.contains('-')
        })
        .filter_map(|e| std::fs::read_to_string(e.path().join("device/gpu_busy_percent")).ok())
        .filter_map(|text| text.trim().parse::<f64>().ok())
        .reduce(f64::max);
    Metric::from_option(busiest, Reason::NotMeasured)
}

pub(super) fn status_area() -> StatusArea {
    if std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_none()
        && std::env::var_os("XDG_RUNTIME_DIR").is_none()
    {
        return StatusArea::Unavailable("no session bus".into());
    }
    let reply = run_bounded(
        "busctl",
        &[
            "--user",
            "--no-pager",
            "call",
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            "s",
            "org.kde.StatusNotifierWatcher",
        ],
        Duration::from_millis(800),
    );
    match reply.as_deref().map(str::trim) {
        Some("b true") => StatusArea::StatusNotifier,
        Some(_) => StatusArea::Unavailable(
            "no StatusNotifierItem host on the session bus (GNOME needs the AppIndicator extension)".into(),
        ),
        None => StatusArea::Unavailable("could not query the session bus with busctl".into()),
    }
}

pub(super) fn notify(title: &str, body: &str) -> Result<(), String> {
    run_bounded(
        "notify-send",
        &["--app-name=FleetConsole", title, body],
        Duration::from_secs(3),
    )
    .map(|_| ())
    .ok_or_else(|| "notify-send is unavailable or failed".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interface_filter_keeps_physical_links() {
        for name in ["eth0", "enp3s0", "wlan0", "wlp2s0"] {
            assert!(is_physical_interface(name), "{name}");
        }
        for name in ["lo", "docker0", "veth12", "br-abc", "tailscale0", "wg0"] {
            assert!(!is_physical_interface(name), "{name}");
        }
    }

    #[test]
    fn pseudo_filesystems_are_not_storage() {
        assert!(is_user_volume("/", "ext4"));
        assert!(is_user_volume("/home", "btrfs"));
        assert!(!is_user_volume("/run/user/1000", "tmpfs"));
        assert!(!is_user_volume("/boot", "vfat"));
        assert!(!is_user_volume("/var/lib/docker/overlay2/x", "overlay"));
    }

    #[test]
    fn gpu_busy_reads_the_busiest_amdgpu_card() {
        let root = tempfile::tempdir().unwrap();
        for (card, value) in [("card0", "12\n"), ("card1", "64\n")] {
            let dir = root.path().join(card).join("device");
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("gpu_busy_percent"), value).unwrap();
        }
        std::fs::create_dir_all(root.path().join("card1-HDMI-A-1")).unwrap();
        assert_eq!(gpu_busy_percent_in(root.path()), Metric::Measured(64.0));
    }

    #[test]
    fn missing_gpu_counter_is_not_measured() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("card0/device")).unwrap();
        assert_eq!(
            gpu_busy_percent_in(root.path()),
            Metric::Unavailable(Reason::NotMeasured)
        );
    }
}
