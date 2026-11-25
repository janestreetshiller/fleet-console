use std::path::Path;
use std::time::Duration;

pub const SAMPLE_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Meters {
    pub cpu: Option<u32>,
    pub ram: Option<u32>,
    pub disk: Option<u32>,
}

impl Meters {
    pub fn text(self) -> String {
        format!(
            "CPU {}   RAM {}   DISK {}",
            value_text(self.cpu),
            value_text(self.ram),
            value_text(self.disk)
        )
    }

    pub fn accessibility(self) -> String {
        format!(
            "FleetConsole fleet — CPU {}, RAM {}, DISK {}",
            value_text(self.cpu),
            value_text(self.ram),
            value_text(self.disk)
        )
    }
}

pub fn value_text(value: Option<u32>) -> String {
    match value {
        Some(percent) => format!("{percent}%"),
        None => "—".to_string(),
    }
}

fn percent_of(share: f64) -> Option<u32> {
    if share.is_finite() {
        Some((share.clamp(0.0, 1.0) * 100.0).round() as u32)
    } else {
        None
    }
}

pub struct Sampler {
    system: sysinfo::System,
    disks: sysinfo::Disks,
    cpu_primed: bool,
}

impl Default for Sampler {
    fn default() -> Self {
        Self::new()
    }
}

impl Sampler {
    pub fn new() -> Self {
        let mut system = sysinfo::System::new();
        system.refresh_cpu_usage();
        system.refresh_memory();
        Self {
            system,
            disks: sysinfo::Disks::new_with_refreshed_list(),
            cpu_primed: false,
        }
    }

    pub fn sample(&mut self) -> Meters {
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        self.disks.refresh();
        let cpu = if self.cpu_primed {
            let usage = self.system.global_cpu_usage();
            if usage.is_finite() {
                Some(usage.clamp(0.0, 100.0).round() as u32)
            } else {
                None
            }
        } else {
            None
        };
        self.cpu_primed = true;
        Meters {
            cpu,
            ram: memory_percent(&self.system),
            disk: disk_percent(&self.disks),
        }
    }
}

fn disk_percent(disks: &sysinfo::Disks) -> Option<u32> {
    let disk = disks
        .list()
        .iter()
        .find(|disk| disk.mount_point() == Path::new("/"))?;
    let total = disk.total_space();
    let available = disk.available_space();
    if total == 0 || available > total {
        return None;
    }
    percent_of((total - available) as f64 / total as f64)
}

#[cfg(not(target_os = "macos"))]
fn memory_percent(system: &sysinfo::System) -> Option<u32> {
    let total = system.total_memory();
    if total == 0 {
        return None;
    }
    percent_of(system.used_memory() as f64 / total as f64)
}

#[cfg(target_os = "macos")]
fn memory_percent(system: &sysinfo::System) -> Option<u32> {
    let total = system.total_memory();
    if total == 0 {
        return None;
    }
    percent_of(mac_memory_used(total)? as f64 / total as f64)
}

#[cfg(target_os = "macos")]
#[allow(deprecated)]
fn mac_memory_used(total: u64) -> Option<u64> {
    unsafe {
        let mut stats: libc::vm_statistics64 = std::mem::zeroed();
        let mut count = libc::HOST_VM_INFO64_COUNT;
        let status = libc::host_statistics64(
            libc::mach_host_self(),
            libc::HOST_VM_INFO64,
            &mut stats as *mut libc::vm_statistics64 as *mut i32,
            &mut count,
        );
        if status != libc::KERN_SUCCESS {
            return None;
        }
        let page_size = libc::sysconf(libc::_SC_PAGESIZE);
        if page_size <= 0 {
            return None;
        }
        let page = page_size as u64;
        let wired = u64::from(stats.wire_count) * page;
        let compressed = u64::from(stats.compressor_page_count) * page;
        let cached =
            (u64::from(stats.external_page_count) + u64::from(stats.purgeable_count)) * page;
        let app = (u64::from(stats.active_count)
            + u64::from(stats.inactive_count)
            + u64::from(stats.speculative_count))
            * page;
        let app = app.saturating_sub(cached);
        Some((app + wired + compressed).min(total))
    }
}
